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
      columns = 12
      tiles = [
        # Tile 1: Pipeline Status - CORREGIDO
        {
          width = 4
          height = 2
          xPos = 0
          yPos = 0
          widget = {
            title = "Function Invocations"
            scorecard = {
              timeSeriesQuery = {
                timeSeriesFilter = {
                  # CORREGIDO: Usar sintaxis correcta para regex
                  filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=monitoring.regex.full_match(\"weather-.*\")"
                  aggregation = {
                    alignmentPeriod = "300s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
                # AGREGADO: Especificar el tipo de métrica
                unitOverride = "1"
              }
              sparkChartView = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        
        # Tile 2: Function Executions - CORREGIDO
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
                    # AGREGADO: Especificar el tipo de métrica
                    unitOverride = "1/s"
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
                    # AGREGADO: Especificar el tipo de métrica
                    unitOverride = "1/s"
                  }
                  plotType = "LINE"
                  targetAxis = "Y1"
                  legendTemplate = "Transform Function"
                }
              ]
              yAxis = {
                label = "Executions/sec"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # Tile 3: Error Logs - CORREGIDO
        {
          width = 12
          height = 4
          xPos = 0
          yPos = 4
          widget = {
            title = "Recent Errors & Logs"
            logsPanel = {
              # CORREGIDO: Usar sintaxis correcta para filtros de logs
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
      # CORREGIDO: Usar filtro específico para métricas de Cloud Functions
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_count\""
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.labels.function_name"]
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

# NUEVA: Alerta específica para errores en logs
resource "google_monitoring_alert_policy" "function_log_errors" {
  depends_on = [time_sleep.wait_for_metrics]
  
  display_name = "Weather ETL Function Log Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Error logs detected"
    
    condition_threshold {
      # CORREGIDO: Usar filtro correcto para logs de error
      filter = "resource.type=\"cloud_function\" AND log_name=\"projects/${var.project_id}/logs/cloudfunctions.googleapis.com%2Fcloud-functions\" AND severity>=ERROR"
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_SUM"
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 1
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
    display_name = "Memory usage > 80%"
    
    condition_threshold {
      # CORREGIDO: Usar métrica correcta para memoria
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/user_memory_bytes\""
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields    = ["resource.labels.function_name"]
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 134217728  # 128MB en bytes
      duration        = "300s"
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
}

# NUEVA: Alerta para tiempo de ejecución
resource "google_monitoring_alert_policy" "execution_time" {
  depends_on = [time_sleep.wait_for_metrics]
  
  display_name = "Function Execution Time Too High"
  combiner     = "OR"
  
  conditions {
    display_name = "Execution time > 30 seconds"
    
    condition_threshold {
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/execution_times\""
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_PERCENTILE_95"
        cross_series_reducer = "REDUCE_MAX"
        group_by_fields      = ["resource.labels.function_name"]
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 30000  # 30 segundos en milisegundos
      duration        = "300s"
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
}

# Canal de notificación por email - YA EXISTE EN main.tf
# resource "google_monitoring_notification_channel" "email" {
#   display_name = "Email Notification Channel"
#   type         = "email"
#   
#   labels = {
#     email_address = var.notification_email
#   }
# }

# Output del dashboard URL
output "dashboard_url" {
  value = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.weather_etl_dashboard.id}?project=${var.project_id}"
  description = "URL del dashboard de monitoreo"
}

# Output de las alertas
output "alert_policies" {
  value = {
    function_errors = google_monitoring_alert_policy.function_errors.name
    log_errors = google_monitoring_alert_policy.function_log_errors.name
    memory_usage = google_monitoring_alert_policy.memory_usage.name
    execution_time = google_monitoring_alert_policy.execution_time.name
  }
  description = "Nombres de las políticas de alerta creadas"
}