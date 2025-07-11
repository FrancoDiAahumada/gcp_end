resource "google_monitoring_dashboard" "weather_etl_dashboard" {
  dashboard_json = jsonencode({
    displayName = "Weather ETL Pipeline Dashboard"
    
    mosaicLayout = {
      tiles = [
        # Tile 1: Pipeline Status
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
              sparkChart = {
                sparkChartType = "SPARK_LINE"
              }
            }
          }
        },
        
        # Tile 2: Function Executions
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
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\" AND resource.label.function_name=\"weather-etl-extract\""
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
                      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\" AND resource.label.function_name=\"weather-etl-transform\""
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
                label = "Executions/min"
                scale = "LINEAR"
              }
            }
          }
        },
        
        # Tile 3: Memory Usage
        {
          width = 6
          height = 3
          widget = {
            title = "Memory Usage"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/memory_utilization\""
                    aggregation = {
                      alignmentPeriod = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
                plotType = "LINE"
              }]
              yAxis = {
                label = "Memory %"
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

# Alertas críticas
resource "google_monitoring_alert_policy" "function_errors" {
  display_name = "Weather ETL Function Errors"
  combiner     = "OR"
  
  conditions {
    display_name = "Function error rate too high"
    
    condition_threshold {
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/executions\""
      
      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_RATE"
        cross_series_reducer = "REDUCE_MEAN"
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 0.05  # 5% error rate
      duration        = "300s"
    }
  }
  
  notification_channels = [google_monitoring_notification_channel.email.name]
  
  alert_strategy {
    auto_close = "1800s"  # 30 minutes
  }
}

resource "google_monitoring_alert_policy" "memory_usage" {
  display_name = "High Memory Usage"
  combiner     = "OR"
  
  conditions {
    display_name = "Memory usage > 80%"
    
    condition_threshold {
      filter = "resource.type=\"cloud_function\" AND metric.type=\"cloudfunctions.googleapis.com/function/memory_utilization\""
      
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
      
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8  # 80%
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