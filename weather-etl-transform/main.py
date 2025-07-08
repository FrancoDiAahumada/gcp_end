from google.cloud import bigquery
import functions_framework
import os
import datetime

PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_ID = os.environ.get('DATASET_ID', 'weather_analytics')

@functions_framework.cloud_event
def transform_weather_data(cloud_event):
    """Transforma datos crudos desde raw_weather y los guarda en clean_weather"""

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

    return {
        "message": "Transformación completada exitosamente",
        "timestamp": datetime.datetime.utcnow().isoformat()
    }
