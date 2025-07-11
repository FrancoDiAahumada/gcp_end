import logging
from google.cloud import logging as cloud_logging
from google.cloud import bigquery
import functions_framework
import os
import datetime

# Configura Cloud Logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_ID = os.environ.get('DATASET_ID', 'weather_analytics')

@functions_framework.http
def main(request):
    """HTTP Cloud Function para transformar datos meteorológicos"""
    try:
        logger.info("🟢 ETL-TRANSFORM: Iniciando transformación")
        
        client = bigquery.Client()
        
        query = f"""
        CREATE OR REPLACE TABLE `{PROJECT_ID}.{DATASET_ID}.clean_weather` AS
        SELECT
            id,
            city,
            country,
            ROUND(temperature, 1) AS temperature,
            ROUND(feels_like, 1) AS feels_like,
            humidity,
            pressure,
            weather_main,
            weather_description,
            wind_speed,
            wind_direction,
            cloudiness,
            visibility,
            DATE(sunrise) AS sunrise_date,
            TIME(sunrise) AS sunrise_time,
            DATE(sunset) AS sunset_date,
            TIME(sunset) AS sunset_time,
            DATETIME(extraction_timestamp) AS ingestion_datetime
        FROM `{PROJECT_ID}.{DATASET_ID}.raw_weather`
        """
        
        job = client.query(query)
        job.result()
        
        # Obtener el número de filas procesadas
        processed_count = job.num_dml_affected_rows if hasattr(job, 'num_dml_affected_rows') else None
        
        logger.info(f"✅ ETL-TRANSFORM: Completado - {processed_count if processed_count is not None else 'N/A'} registros")
        
        response = {
            "status": "success",
            "message": "Transformación completada exitosamente",
            "processed_rows": processed_count,
            "timestamp": datetime.datetime.utcnow().isoformat()
        }
        
        return response, 200
        
    except Exception as e:
        logger.error(f"🚨 ETL-TRANSFORM: Error - {str(e)}")
        error_response = {
            "status": "error",
            "message": f"Error en transformación: {str(e)}",
            "timestamp": datetime.datetime.utcnow().isoformat()
        }
        return error_response, 500