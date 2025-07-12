variable "project_id" {
  description = "The GCP project ID"
  type        = string
  default     = "weather-etl-pipeline-464514"
}

variable "region" {
  description = "The GCP region"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Name of the storage bucket"
  type        = string
  default     = "weather-data-bucket-unique-name"
}

variable "dataset_name" {
  description = "Name of the BigQuery dataset"
  type        = string
  default     = "weather_analytics"
}

variable "openweather_api_key" {
  description = "OpenWeather API key"
  type        = string
  sensitive   = true
}

variable "notification_email" {
  description = "Email for monitoring notifications"
  type        = string
}

variable "enable_monitoring" {
  description = "Habilitar dashboard y alertas"
  type        = bool
  default     = true
}