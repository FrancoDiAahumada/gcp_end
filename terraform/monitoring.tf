# Crea el dataset de BigQuery donde se exportarán los logs
resource "google_bigquery_dataset" "etl_logs" {
  dataset_id = "etl_logs"
  project    = var.project_id
  location   = "US"
}

# Crea un sink para exportar logs desde Cloud Logging a BigQuery
resource "google_logging_project_sink" "logs_to_bigquery" {
  name        = "logs-to-bq"
  project     = var.project_id
  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/etl_logs"
  filter      = "resource.type=cloud_function"
  unique_writer_identity = true
}

# Canal de notificación por correo
resource "google_monitoring_notification_channel" "email" {
  display_name = "Alertas ETL por correo"
  type         = "email"

  labels = {
    email_address = var.notification_email
  }
}
