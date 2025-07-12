output "bucket_name" {
  value = google_storage_bucket.weather_data_bucket.name
}

output "bigquery_dataset" {
  value = google_bigquery_dataset.weather_dataset.dataset_id
}

output "pubsub_topic" {
  value = google_pubsub_topic.weather_topic.name
}
