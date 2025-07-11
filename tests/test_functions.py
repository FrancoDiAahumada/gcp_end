import pytest
from unittest.mock import Mock, patch, MagicMock
import json
from datetime import datetime

def test_extract_function():
    """Test de la función de extracción"""
    with patch('requests.post') as mock_post, \
         patch('google.cloud.storage.Client') as mock_storage, \
         patch('google.cloud.bigquery.Client') as mock_bigquery:
        
        # Mock de la respuesta de la API
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "id": 123456,
            "name": "Santiago",
            "sys": {"country": "CL", "sunrise": 1640995200, "sunset": 1641038400},
            "main": {"temp": 25.5, "feels_like": 27.0, "humidity": 60, "pressure": 1013},
            "weather": [{"main": "Clear", "description": "clear sky"}],
            "wind": {"speed": 5.2, "deg": 180},
            "clouds": {"all": 10},
            "visibility": 10000
        }
        mock_post.return_value = mock_response
        
        # Mock de Google Cloud Storage
        mock_bucket = Mock()
        mock_blob = Mock()
        mock_storage.return_value.bucket.return_value = mock_bucket
        mock_bucket.blob.return_value = mock_blob
        
        # Mock de BigQuery
        mock_job = Mock()
        mock_job.result.return_value = None
        mock_bigquery.return_value.load_table_from_json.return_value = mock_job
        
        # Importar y ejecutar la función
        from functions.extract.main import extract_weather_data
        
        # Simular cloud_event
        cloud_event = Mock()
        
        # Ejecutar la función
        result = extract_weather_data(cloud_event)
        
        # Verificaciones
        assert result["status"] == "success"
        assert result["records"] == 10  # 10 ciudades configuradas
        mock_post.assert_called()
        mock_blob.upload_from_string.assert_called()

def test_transform_function():
    """Test de la función de transformación"""
    with patch('google.cloud.bigquery.Client') as mock_bigquery:
        
        # Mock del cliente BigQuery
        mock_client = Mock()
        mock_job = Mock()
        mock_job.result.return_value = None
        mock_client.query.return_value = mock_job
        
        # Mock para el conteo de registros
        mock_count_result = Mock()
        mock_count_result.total_records = 10
        mock_count_job = Mock()
        mock_count_job.result.return_value = [mock_count_result]
        
        # Configurar el mock para devolver diferentes resultados según la query
        def query_side_effect(query):
            if "COUNT(*)" in query:
                return mock_count_job
            return mock_job
        
        mock_client.query.side_effect = query_side_effect
        mock_bigquery.return_value = mock_client
        
        # Importar y ejecutar la función
        from functions.transform.main import transform_weather_data
        
        # Simular cloud_event
        cloud_event = Mock()
        
        # Ejecutar la función
        result = transform_weather_data(cloud_event)
        
        # Verificaciones
        assert result["message"] == "Transformación completada exitosamente"
        assert result["processed_records"] == 10
        assert "timestamp" in result
        mock_client.query.assert_called()

def test_extract_function_api_error():
    """Test de manejo de errores en la API"""
    with patch('requests.post') as mock_post, \
         patch('google.cloud.storage.Client') as mock_storage, \
         patch('google.cloud.bigquery.Client') as mock_bigquery:
        
        # Mock de error en la API
        mock_post.side_effect = Exception("API Error")
        
        # Mock básico de los servicios de Google Cloud
        mock_storage.return_value.bucket.return_value.blob.return_value = Mock()
        mock_bigquery.return_value.load_table_from_json.return_value.result.return_value = None
        
        # Importar la función
        from functions.extract.main import extract_weather_data
        
        # Simular cloud_event
        cloud_event = Mock()
        
        # La función debería manejar el error y continuar
        result = extract_weather_data(cloud_event)
        
        # Verificar que se completó sin fallar completamente
        assert result["status"] == "success"
        assert result["records"] == 0  # No se procesaron registros debido al error

def test_transform_function_bigquery_error():
    """Test de manejo de errores en BigQuery"""
    with patch('google.cloud.bigquery.Client') as mock_bigquery:
        
        # Mock que simula error en BigQuery
        mock_client = Mock()
        mock_client.query.side_effect = Exception("BigQuery Error")
        mock_bigquery.return_value = mock_client
        
        # Importar la función
        from functions.transform.main import transform_weather_data
        
        # Simular cloud_event
        cloud_event = Mock()
        
        # La función debería lanzar la excepción
        with pytest.raises(Exception) as exc_info:
            transform_weather_data(cloud_event)
        
        assert "BigQuery Error" in str(exc_info.value)

# Test de utilidades
def test_convert_datetimes_to_str():
    """Test de la función de conversión de datetime"""
    from functions.extract.main import convert_datetimes_to_str
    
    test_data = [
        {
            "id": 1,
            "timestamp": datetime(2023, 1, 1, 12, 0, 0),
            "name": "test"
        }
    ]
    
    result = convert_datetimes_to_str(test_data)
    
    assert isinstance(result[0]["timestamp"], str)
    assert result[0]["timestamp"] == "2023-01-01T12:00:00"
    assert result[0]["name"] == "test"