# Delay para esperar que las métricas estén disponibles
resource "time_sleep" "wait_for_metrics" {
  depends_on = [
    google_cloudfunctions_function.weather_extract,
    google_cloudfunctions_function.weather_transform
  ]
  create_duration = "10m"
}

# Notification channel
resource "google_monitoring_notification_channel" "email" {
  display_name = "Email Notifications"
  type         = "email"
  labels = {
    email_address = var.notification_email
  }
}

resource "google_monitoring_dashboard" "weather_etl_dashboard" {
  depends_on = [time_sleep.wait_for_metrics]
  
  dashboard_json = jsonencode({
    displayName = "Weather ETL Pipeline Dashboard"
    
    mosaicLayout = {
      tiles = [
        # Tile 1: Pipeline Status - SIN sparkChart
        {
          width = 4
          height = 2
          widget = {
            title = "Pipeline Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_function\" AND resource.label.function_name=~\"weather-.*\""
                  aggregation = {
                    alignmentPeriod = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
              # sparkChart REMOVIDO - esta es la causa del error
            }
          }
        },
        
        # Tile 2: Function Executions - Usando métricas alternativas
        {
          width = 8
          height = 4
          widget = {
            title = "Function Executions per Minute"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/log_entry_count\" AND resource.label.function_name=\"weather-etl-extract\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                  targetAxis = "Y1"
                  legendTemplate = "Extract Function"
                },
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/log_entry_count\" AND resource.label.function_name=\"weather-etl-transform\""
                      aggregation = {
                        alignmentPeriod = "60s"
                        perSeriesAligner = "ALIGN_RATE"
                      }
                    }
                  }
                  plotType = "LINE"
                  targetAxis = "Y1"
                  legendTemplate = "Transform Function"
                }
              ]
              yAxis = {
                label = "Log Entries/min"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # Tile 3: Memory Usage - Usando métricas alternativas
        {
          width = 6
          height = 3
          widget = {
            title = "Memory Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/user_memory_bytes\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Memory (bytes)"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # Tile 4: BigQuery Jobs
        {
          width = 6
          height = 3
          widget = {
            title = "BigQuery Jobs"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"bigquery_project\" AND metric.type=\"bigquery.googleapis.com/job/query_count\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
                plotType = "STACKED_BAR"
              }]
            }
          }
        },
        
        # Tile 5: Error Logs
        {
          width = 12
          height = 4
          widget = {
            title = "Recent Errors & Logs"
            logsPanel = {
              filter = "resource.type=\"cloud_function\" AND (severity>=ERROR OR jsonPayload.message=~\".*error.*\")"
              resourceNames = ["projects/${var.project_id}"]
            }
          }
        }
      ]
    }
  })
}

# Alertas críticas - CORREGIDAS
resource "google_monitoring_alert_policy" "function_errors" {
  depends_on = [time_sleep.wait_for_metrics]
  
  display_name = "Weather ETL Function Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      # Usando métricas de logging en lugar de function/executions
      filter = "resource.type=\"cloud_function\" AND metric.type=\"logging.googleapis.com/log_entry_count\" AND jsonPayload.severity=\"ERROR\""
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 5  # 5 errores en 5 minutos
      duration        = "300s"
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
}

resource "google_monitoring_alert_policy" "memory_usage" {
  depends_on = [time_sleep.wait_for_metrics]
  
  display_name = "High Memory Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "Memory usage > 128MB"
    
    condition_threshold {
      # Usando user_memory_bytes en lugar de memory_utilization
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/user_memory_bytes\""
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 134217728  # 128MB en bytes
      duration        = "300s"
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
}

# Output del dashboard URL
output "dashboard_url" {
  value = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.weather_etl_dashboard.id}?project=${var.project_id}"
  description = "URL del dashboard de monitoreo"
}