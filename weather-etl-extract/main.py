import json
import requests
from google.cloud import storage
from google.cloud import bigquery
from datetime import datetime
import functions_framework
import logging
import os
from flask import jsonify

# ✅ NUEVO: Configurar logging estructurado para monitoreo
from google.cloud import logging as cloud_logging

# Configurar logging de Google Cloud
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Configuración desde variables de entorno
API_KEY = os.environ.get('OPENWEATHER_API_KEY', 'demo-key')
BUCKET_NAME = os.environ.get('BUCKET_NAME', 'weather-etl-bucket')
PROJECT_ID = os.environ.get('PROJECT_ID', 'weather-etl-pipeline-464514')
DATASET_ID = os.environ.get('DATASET_ID', 'weather_analytics')

# Lista de ciudades para consultar
CITIES = [
    'Santiago,CL', 'Buenos Aires,AR', 'Lima,PE', 'Bogota,CO',
    'Mexico City,MX', 'Madrid,ES', 'London,UK', 'New York,US',
    'Tokyo,JP', 'Sydney,AU'
]

def convert_datetimes_to_str(data_list):
    for item in data_list:
        for key, value in item.items():
            if isinstance(value, datetime):
                item[key] = value.isoformat()
    return data_list

@functions_framework.http
def main(request):
    """Función HTTP para extraer datos meteorológicos de OpenWeatherMap API"""
    
    # ✅ NUEVO: Logging de inicio con timestamp
    start_time = datetime.utcnow()
    logger.info("🟢 WEATHER-ETL: Iniciando extracción de datos meteorológicos", extra={
        'start_time': start_time.isoformat(),
        'cities_to_process': len(CITIES),
        'function_name': 'extract_weather_data'
    })
    
    try:
        storage_client = storage.Client()
        bigquery_client = bigquery.Client()
        
        bucket = storage_client.bucket(BUCKET_NAME)
        table_ref = bigquery_client.dataset(DATASET_ID).table('raw_weather')
        
        extracted_data = []
        timestamp = datetime.utcnow()
        date_str = timestamp.strftime('%Y-%m-%d')
        
        # ✅ NUEVO: Contadores para métricas
        successful_extractions = 0
        failed_extractions = 0
        
        for city in CITIES:
            try:
                # ✅ NUEVO: Log inicio de extracción por ciudad
                logger.info(f"🌤️ WEATHER-ETL: Procesando ciudad {city}")
                
                url = f"http://api.openweathermap.org/data/2.5/weather"
                params = {
                    'q': city,
                    'appid': API_KEY,
                    'units': 'metric'
                }
                
                response = requests.get(url, timeout=30)
                response.raise_for_status()
                data = response.json()
                
                weather_record = {
                    'id': f"{data['id']}_{int(timestamp.timestamp())}",
                    'city': data['name'],
                    'country': data['sys']['country'],
                    'temperature': data['main']['temp'],
                    'feels_like': data['main']['feels_like'],
                    'humidity': data['main']['humidity'],
                    'pressure': data['main']['pressure'],
                    'weather_main': data['weather'][0]['main'],
                    'weather_description': data['weather'][0]['description'],
                    'wind_speed': data.get('wind', {}).get('speed', 0),
                    'wind_direction': data.get('wind', {}).get('deg', 0),
                    'cloudiness': data.get('clouds', {}).get('all', 0),
                    'visibility': data.get('visibility', 0),
                    'sunrise': datetime.fromtimestamp(data['sys']['sunrise']).isoformat(),
                    'sunset': datetime.fromtimestamp(data['sys']['sunset']).isoformat(),
                    'extraction_timestamp': timestamp.isoformat(),
                    'api_response_raw': json.dumps(data)
                }
                
                extracted_data.append(weather_record)
                successful_extractions += 1
                
                # ✅ NUEVO: Log éxito por ciudad
                logger.info(f"✅ WEATHER-ETL: Datos extraídos exitosamente para {city}", extra={
                    'city': city,
                    'temperature': data['main']['temp'],
                    'weather': data['weather'][0]['main'],
                    'status': 'success'
                })
                
            except requests.exceptions.RequestException as e:
                failed_extractions += 1
                # ✅ NUEVO: Log específico para errores de API
                logger.error(f"🌐 WEATHER-ETL: Error de API para {city}: {str(e)}", extra={
                    'city': city,
                    'error_type': 'api_error',
                    'error_message': str(e),
                    'status': 'failed'
                })
                continue
                
            except Exception as e:
                failed_extractions += 1
                # ✅ NUEVO: Log para errores generales
                logger.error(f"❌ WEATHER-ETL: Error procesando {city}: {str(e)}", extra={
                    'city': city,
                    'error_type': 'processing_error',
                    'error_message': str(e),
                    'status': 'failed'
                })
                continue
        
        # ✅ NUEVO: Validar que tenemos datos para procesar
        if not extracted_data:
            logger.error("🚨 WEATHER-ETL: No se pudieron extraer datos de ninguna ciudad", extra={
                'total_cities': len(CITIES),
                'successful_extractions': 0,
                'failed_extractions': len(CITIES),
                'status': 'critical_failure'
            })
            return jsonify({
                'status': 'error',
                'message': 'No se pudo extraer información meteorológica'
            }), 500
        
        # Aseguramos que no haya objetos datetime sin convertir
        extracted_data = convert_datetimes_to_str(extracted_data)
        
        # ✅ NUEVO: Log antes de guardar en Storage
        logger.info(f"💾 WEATHER-ETL: Guardando datos en Cloud Storage")
        
        # Guardar datos en Cloud Storage
        blob_name = f"raw/daily/{date_str}/weather_data_{timestamp.strftime('%H%M%S')}.json"
        blob = bucket.blob(blob_name)
        
        try:
            blob.upload_from_string(json.dumps(extracted_data, default=str))
            logger.info(f"✅ WEATHER-ETL: Datos guardados en Storage: {blob_name}", extra={
                'storage_path': blob_name,
                'file_size_bytes': len(json.dumps(extracted_data, default=str)),
                'status': 'storage_success'
            })
        except Exception as e:
            logger.error(f"❌ WEATHER-ETL: Error guardando en Storage: {str(e)}", extra={
                'storage_path': blob_name,
                'error_type': 'storage_error',
                'status': 'storage_failed'
            })
            return jsonify({
                'status': 'error',
                'message': f'Error guardando en Storage: {str(e)}'
            }), 500

        # ✅ NUEVO: Log antes de cargar a BigQuery
        logger.info(f"📊 WEATHER-ETL: Cargando datos a BigQuery")
        
        # Convertir datetime a string para BigQuery
        for record in extracted_data:
            for key, value in record.items():
                if isinstance(value, datetime):
                    record[key] = value.isoformat()

        # Cargar datos a BigQuery
        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            autodetect=False,
            write_disposition=bigquery.WriteDisposition.WRITE_APPEND
        )

        try:
            job = bigquery_client.load_table_from_json(
                extracted_data, table_ref, job_config=job_config
            )
            job.result()
            
            # ✅ NUEVO: Log éxito de BigQuery
            logger.info(f"✅ WEATHER-ETL: Datos cargados exitosamente a BigQuery", extra={
                'bq_table': f"{DATASET_ID}.raw_weather",
                'records_loaded': len(extracted_data),
                'job_id': job.job_id,
                'status': 'bq_success'
            })
            
        except Exception as e:
            logger.error(f"❌ WEATHER-ETL: Error cargando a BigQuery: {str(e)}", extra={
                'bq_table': f"{DATASET_ID}.raw_weather",
                'error_type': 'bigquery_error',
                'error_message': str(e),
                'status': 'bq_failed'
            })
            return jsonify({
                'status': 'error',
                'message': f'Error cargando a BigQuery: {str(e)}'
            }), 500

        # ✅ NUEVO: Log de resumen final con métricas
        end_time = datetime.utcnow()
        execution_time = (end_time - start_time).total_seconds()
        
        logger.info(f"🎉 WEATHER-ETL: Proceso completado exitosamente", extra={
            'execution_time_seconds': execution_time,
            'total_cities_processed': len(CITIES),
            'successful_extractions': successful_extractions,
            'failed_extractions': failed_extractions,
            'success_rate': (successful_extractions / len(CITIES)) * 100,
            'records_stored': len(extracted_data),
            'storage_path': blob_name,
            'bq_table': f"{DATASET_ID}.raw_weather",
            'status': 'complete_success'
        })
        
        # Respuesta HTTP exitosa
        return jsonify({
            'status': 'success',
            'message': 'Extracción de datos meteorológicos completada',
            'data': {
                'execution_time_seconds': execution_time,
                'cities_processed': len(CITIES),
                'successful_extractions': successful_extractions,
                'failed_extractions': failed_extractions,
                'success_rate': round((successful_extractions / len(CITIES)) * 100, 2),
                'records_stored': len(extracted_data),
                'storage_path': blob_name,
                'bq_table': f"{DATASET_ID}.raw_weather"
            }
        }), 200
        
    except Exception as e:
        # ✅ NUEVO: Log de error crítico
        end_time = datetime.utcnow()
        execution_time = (end_time - start_time).total_seconds()
        
        logger.error(f"🚨 WEATHER-ETL: Error crítico en la función", extra={
            'execution_time_seconds': execution_time,
            'error_type': 'critical_error',
            'error_message': str(e),
            'status': 'critical_failure'
        })
        
        # Respuesta HTTP de error
        return jsonify({
            'status': 'error',
            'message': f'Error crítico: {str(e)}'
        }), 500