# Especifica la versión del proveedor para evitar bugs
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.44.0"  # Versión específica estable
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.1"
    }
  }
  
  # ✅ AGREGAR ESTA CONFIGURACIÓN DE BACKEND
  backend "gcs" {
    bucket = "weather-etl-terraform-state-464514"
    prefix = "terraform/state"
  }
}

# Configura el proveedor de Google Cloud con timeouts aumentados
provider "google" {
  project = var.project_id
  region  = var.region
  
  # Configuración de timeouts para evitar errores de plugin
  request_timeout = "60s"
  
  # Configuración de retry
  batching {
    enable_batching = true
    send_after      = "10s"
  }
}

# Habilitar APIs necesarias PRIMERO
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = false
  disable_on_destroy        = false
  
  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

# Delay para asegurar que las APIs estén completamente habilitadas
resource "time_sleep" "wait_for_apis" {
  depends_on = [google_project_service.required_apis]
  create_duration = "30s"
}

# Crea un bucket de Google Cloud Storage para almacenar datos meteorológicos
resource "google_storage_bucket" "weather_data_bucket" {
  depends_on = [time_sleep.wait_for_apis]
  
  name                        = var.bucket_name
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true
  
  # Configuración de lifecycle para evitar costos
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

# Crea un dataset de BigQuery para almacenar datos meteorológicos
resource "google_bigquery_dataset" "weather_dataset" {
  dataset_id = var.dataset_name                                # ID del dataset, definido por una variable
  location   = var.region                                      # Región donde se crea el dataset
}

resource "google_cloudfunctions2_function" "weather_extract" {
  depends_on = [
    time_sleep.wait_for_apis,
    google_storage_bucket.weather_data_bucket,
    google_bigquery_dataset.weather_dataset
  ]
  
  name     = "weather-etl-extract"
  location = "us-central1"
  project  = var.project_id
  
  build_config {
    runtime     = "python311"
    entry_point = "extract_weather_data"
    docker_repository = "projects/${var.project_id}/locations/us-central1/repositories/gcf-artifacts"
    
    source {
      storage_source {
        bucket     = "gcf-v2-sources-990904885293-us-central1"
        object     = "weather-etl-extract/function-source.zip"
      }
    }
  }
  
  service_config {
    min_instance_count = 0
    max_instance_count = 10
    available_memory   = "256M"
    available_cpu      = "0.1666"
    timeout_seconds    = 540
    max_instance_request_concurrency = 1
    all_traffic_on_latest_revision = true
    ingress_settings = "ALLOW_ALL"
    
environment_variables = {
      BUCKET_NAME           = var.bucket_name
      DATASET_ID           = var.dataset_name
      LOG_EXECUTION_ID     = "true"
      OPENWEATHER_API_KEY  = var.openweather_api_key
      PROJECT_ID           = var.project_id
    }
  }
  
  event_trigger {
    trigger_region = "us-central1"
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.weather_topic.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }

  labels = {
    deployment-tool = "terraform"
    environment     = "production"
  }
  
  timeouts {
    create = "15m"
    update = "15m"
    delete = "10m"
  }
}


# Función Cloud Function para transformar datos
resource "google_cloudfunctions2_function" "weather_transform" {
  depends_on = [
    time_sleep.wait_for_apis,
    google_storage_bucket.weather_data_bucket,
    google_bigquery_dataset.weather_dataset
  ]
  
  name     = "weather-etl-transform"
  location = "us-central1"
  project  = var.project_id
  
  build_config {
    runtime     = "python311"
    entry_point = "transform_weather_data"
    docker_repository = "projects/${var.project_id}/locations/us-central1/repositories/gcf-artifacts"
    
    source {
      storage_source {
        bucket = "gcf-v2-sources-990904885293-us-central1"
        object = "weather-etl-transform/function-source.zip"
        # generation = "1751904491030691" - Omitido para evitar errores de formato
      }
    }
  }
  
  service_config {
    min_instance_count = 0
    max_instance_count = 10
    available_memory   = "256M"
    available_cpu      = "0.1666"
    timeout_seconds    = 540
    max_instance_request_concurrency = 1
    all_traffic_on_latest_revision = true
    ingress_settings = "ALLOW_ALL"
    
    environment_variables = {
      DATASET_ID       = var.dataset_name
      LOG_EXECUTION_ID = "true"
      PROJECT_ID       = var.project_id
    }
  }
  
  event_trigger {
    trigger_region = "us-central1"
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.weather_topic.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }

  labels = {
    deployment-tool = "cli-gcloud"
  }
}

# También necesitas importar el topic de Pub/Sub
resource "google_pubsub_topic" "weather_topic" {
  name    = "weather-trigger"
  project = "weather-etl-pipeline-464514"
}

# Dataset para logs
resource "google_bigquery_dataset" "etl_logs" {
  dataset_id = "etl_logs"
  location   = "US"
  project    = var.project_id
}

# Sink para logs
resource "google_logging_project_sink" "logs_to_bigquery" {
  depends_on = [
    google_bigquery_dataset.etl_logs,
    time_sleep.wait_for_apis
  ]
  
  name        = "logs-to-bq"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/etl_logs"
  filter      = "resource.type=cloud_function AND resource.labels.function_name=~\"weather-.*\""
  project     = var.project_id
  
  unique_writer_identity = true
  
  bigquery_options {
    use_partitioned_tables = true
  }
}

# Canal de notificación por email
resource "google_monitoring_notification_channel" "email" {
  display_name = "Alertas ETL por correo"
  type         = "email"
  project      = var.project_id
  
  labels = {
    email_address = var.notification_email
  }
}

# ✅ AGREGAR OUTPUTS
output "bucket_name" {
  value = google_storage_bucket.weather_data_bucket.name
}

output "bigquery_dataset" {
  value = google_bigquery_dataset.weather_dataset.dataset_id
}

output "pubsub_topic" {
  value = google_pubsub_topic.weather_topic.name
}