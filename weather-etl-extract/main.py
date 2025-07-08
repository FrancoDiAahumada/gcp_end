import json
import requests
from google.cloud import storage
from google.cloud import bigquery
from datetime import datetime
import functions_framework
import logging
import os

# Configuración desde variables de entorno
API_KEY = os.environ.get('OPENWEATHER_API_KEY')
BUCKET_NAME = os.environ.get('BUCKET_NAME')
PROJECT_ID = os.environ.get('PROJECT_ID')
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

@functions_framework.cloud_event
def extract_weather_data(cloud_event):
    """Extrae datos meteorológicos de OpenWeatherMap API"""
    
    storage_client = storage.Client()
    bigquery_client = bigquery.Client()
    
    bucket = storage_client.bucket(BUCKET_NAME)
    table_ref = bigquery_client.dataset(DATASET_ID).table('raw_weather')
    
    extracted_data = []
    timestamp = datetime.utcnow()
    date_str = timestamp.strftime('%Y-%m-%d')
    
    for city in CITIES:
        try:
            url = f"http://api.openweathermap.org/data/2.5/weather"
            params = {
                'q': city,
                'appid': API_KEY,
                'units': 'metric'
            }
            
            response = requests.post(url, timeout=30)
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
            
        except Exception as e:
            logging.error(f"Error extracting data for {city}: {e}")
            continue
    
    # Aseguramos que no haya objetos datetime sin convertir
    extracted_data = convert_datetimes_to_str(extracted_data)
    

    # Guardar datos en Cloud Storage
    blob_name = f"raw/daily/{date_str}/weather_data_{timestamp.strftime('%H%M%S')}.json"
    blob = bucket.blob(blob_name)
    blob.upload_from_string(json.dumps(extracted_data, default=str))

    # ✅ Convertir datetime a string para BigQuery
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

    job = bigquery_client.load_table_from_json(
        extracted_data, table_ref, job_config=job_config
    )
    job.result()

    
    logging.info(f"✅ Successfully extracted {len(extracted_data)} records")
    logging.info(f"🕓 Timestamp: {timestamp.isoformat()}")
    logging.info(f"📦 Storage path: {blob_name}")
