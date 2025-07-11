# Delay para esperar que las métricas estén disponibles
resource "time_sleep" "wait_for_metrics" {
  depends_on = [
    google_cloudfunctions2_function.weather_extract,
    google_cloudfunctions2_function.weather_transform
  ]
  create_duration = "2m"
}

resource "google_monitoring_dashboard" "weather_etl_dashboard" {
  depends_on = [time_sleep.wait_for_metrics]
  
  dashboard_json = jsonencode({
    displayName = "Weather ETL Pipeline Dashboard"
    
    mosaicLayout = {
      columns = 12  # AGREGADO: Especificar número de columnas
      tiles = [
        # Tile 1: Pipeline Status
        {
          width = 4
          height = 2
          xPos = 0
          yPos = 0
          widget = {
            title = "Pipeline Status"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=~\"weather-.*\""
                  aggregation = {
                    alignmentPeriod = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }
          }
        },
        
        # Tile 2: Function Executions
        {
          width = 8
          height = 4
          xPos = 4
          yPos = 0
          widget = {
            title = "Function Executions"
            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"weather-etl-extract\""
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
                      filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"weather-etl-transform\""
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
                label = "Executions"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # Tile 3: Error Logs
        {
          width = 12
          height = 4
          xPos = 0
          yPos = 4
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
      # CORREGIDO: Usar sintaxis correcta para filtros
      filter = "resource.type=\"cloud_function\" AND severity=\"ERROR\""
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 5
      duration        = "300s"
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
  
  alert_strategy {
    auto_close = "1800s"
  }
}

resource "google_monitoring_alert_policy" "memory_usage" {
  depends_on = [time_sleep.wait_for_metrics]
  
  display_name = "High Memory Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "Memory usage > 128MB"
    
    condition_threshold {
      # CORREGIDO: Usar métrica simple sin DISTRIBUTION
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/active_instances\""
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"  # CORREGIDO: Cambiar de ALIGN_MEAN
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 10  # Número de instancias activas
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