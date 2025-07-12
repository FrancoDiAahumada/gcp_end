# Especifica la versión del proveedor para evitar bugs
terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.44.0"  # Versión 5.x estable sin el bug
    }
  }
  
  # ✅ AGREGAR ESTA CONFIGURACIÓN DE BACKEND
  backend "gcs" {
    bucket = "weather-etl-terraform-state-464514"
    prefix = "terraform/state"
  }
}

# Configura el proveedor de Google Cloud con el proyecto y la región especificados en las variables
provider "google" {
  project = var.project_id
  region  = var.region
}

# ✅ AGREGAR: Habilitar APIs necesarias ANTES que todo lo demás
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",              # ✅ CRÍTICO: Cloud Run API
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = var.project_id
  service = each.value
  
  disable_dependent_services = true
}

# Crea un bucket de Google Cloud Storage para almacenar datos meteorológicos
resource "google_storage_bucket" "weather_data_bucket" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia
  
  name                        = var.bucket_name                # Nombre del bucket, definido por una variable
  location                    = var.region                     # Región donde se crea el bucket
  force_destroy               = true                           # Permite eliminar el bucket aunque tenga objetos
  uniform_bucket_level_access = true                           # Acceso uniforme a nivel de bucket
}

# Crea un dataset de BigQuery para almacenar datos meteorológicos
resource "google_bigquery_dataset" "weather_dataset" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia
  
  dataset_id = var.dataset_name                                # ID del dataset, definido por una variable
  location   = var.region                                      # Región donde se crea el dataset
}

# También necesitas importar el topic de Pub/Sub
resource "google_pubsub_topic" "weather_topic" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia
  
  name    = "weather-trigger"
  project = "weather-etl-pipeline-464514"
}

resource "google_cloudfunctions2_function" "weather_extract" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia crítica
  
  name     = "weather-etl-extract"
  location = "us-central1"
  project  = "weather-etl-pipeline-464514"
  
  build_config {
    runtime     = "python311"
    entry_point = "extract_weather_data"
    docker_repository = "projects/weather-etl-pipeline-464514/locations/us-central1/repositories/gcf-artifacts"
    service_account = "projects/weather-etl-pipeline-464514/serviceAccounts/990904885293-compute@developer.gserviceaccount.com"
    
    source {
      storage_source {
        bucket     = "gcf-v2-sources-990904885293-us-central1"
        object     = "weather-etl-extract/function-source.zip"
      }
    }
  }
  
  service_config {
    min_instance_count = 0
    max_instance_count = 100
    available_memory   = "256M"
    available_cpu      = "0.1666"
    timeout_seconds    = 540
    max_instance_request_concurrency = 1
    all_traffic_on_latest_revision = true
    ingress_settings = "ALLOW_ALL"
    service_account_email = "990904885293-compute@developer.gserviceaccount.com"
    
    environment_variables = {
      BUCKET_NAME           = var.bucket_name
      DATASET_ID           = var.dataset_name
      LOG_EXECUTION_ID     = "true"
      OPENWEATHER_API_KEY  = var.openweather_api_key  # ✅ Usando variable
      PROJECT_ID           = var.project_id
    }
  }
  
  event_trigger {
    trigger_region = "us-central1"
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.weather_topic.id  # ✅ Usar referencia
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = "990904885293-compute@developer.gserviceaccount.com"
  }

  labels = {
    deployment-tool = "cli-gcloud"
  }
}

resource "google_cloudfunctions2_function" "weather_transform" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia crítica
  
  name     = "weather-etl-transform"
  location = "us-central1"
  project  = "weather-etl-pipeline-464514"
  
  build_config {
    runtime     = "python311"
    entry_point = "transform_weather_data"
    docker_repository = "projects/weather-etl-pipeline-464514/locations/us-central1/repositories/gcf-artifacts"
    service_account = "projects/weather-etl-pipeline-464514/serviceAccounts/990904885293-compute@developer.gserviceaccount.com"
    
    source {
      storage_source {
        bucket = "gcf-v2-sources-990904885293-us-central1"
        object = "weather-etl-transform/function-source.zip"
      }
    }
  }
  
  service_config {
    min_instance_count = 0
    max_instance_count = 100
    available_memory   = "256M"
    available_cpu      = "0.1666"
    timeout_seconds    = 540
    max_instance_request_concurrency = 1
    all_traffic_on_latest_revision = true
    ingress_settings = "ALLOW_ALL"
    service_account_email = "990904885293-compute@developer.gserviceaccount.com"
    
    environment_variables = {
      DATASET_ID       = "weather_analytics"
      LOG_EXECUTION_ID = "true"
      PROJECT_ID       = "weather-etl-pipeline-464514"
    }
  }
  
  event_trigger {
    trigger_region = "us-central1"
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.weather_topic.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
    service_account_email = "990904885293-compute@developer.gserviceaccount.com"
  }

  labels = {
    deployment-tool = "cli-gcloud"
  }
}

# Dataset para logs
resource "google_bigquery_dataset" "etl_logs" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia
  
  dataset_id = "etl_logs"
  location   = "US"
  project    = var.project_id
}

# Sink para logs
resource "google_logging_project_sink" "logs_to_bigquery" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia
  
  name        = "logs-to-bq"
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/etl_logs"
  filter      = "resource.type=cloud_function"
  project     = var.project_id
  
  unique_writer_identity = true
  
  bigquery_options {
    use_partitioned_tables = true
  }
}

# Canal de notificación por email
resource "google_monitoring_notification_channel" "email" {
  depends_on = [google_project_service.required_apis]  # ✅ AGREGAR dependencia
  
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