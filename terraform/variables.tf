variable "project_id" {
  description = "ID del proyecto de Google Cloud"
  type        = string
  default     = "weather-etl-pipeline-464514"
}

variable "region" {
  description = "Región para desplegar recursos"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Nombre del bucket de Cloud Storage"
  type        = string
  default     = "weather-data-bucket-unique-name"
}

variable "dataset_name" {
  description = "Nombre del dataset de BigQuery"
  type        = string
  default     = "weather_analytics"
}

variable "openweather_api_key" {
  type        = string
  description = "API key para OpenWeather"
}