# Weather ETL Pipeline en GCP ☔️🚀

Este proyecto construye un pipeline de Extracción, Transformación y Carga (ETL) en Google Cloud Platform para recolectar datos meteorológicos desde la API de OpenWeather, almacenarlos en formato crudo y luego procesarlos para su análisis.

---

## 🌍 Tecnologías utilizadas

* **Google Cloud Functions**: para ejecutar código de extracción y transformación
* **Google Cloud Storage**: para almacenar los datos en formato JSON (data lake)
* **Google BigQuery**: para consultas y almacenamiento estructurado
* **Google Pub/Sub**: para disparar eventos entre componentes
* **Google Cloud Scheduler**: para automatizar la ejecución diaria
* **Terraform**: para definir la infraestructura como código
* **Git/GitHub**: para versionar el código del proyecto

---

## 🏠 Arquitectura del pipeline

```
 Cloud Scheduler
      ⬇
   Pub/Sub Topic
      ⬇
+----------------------------+
|  Cloud Function: extract  | -----> Almacena datos en Cloud Storage (raw) y BigQuery (raw_weather)
+----------------------------+
                                      ⬇
                         +-----------------------------+
                         | Cloud Function: transform   | -----> Crea tabla clean_weather en BigQuery
                         +-----------------------------+
```

---

## 🚀 Flujo del ETL

1. **Extracción:**

   * API: OpenWeather
   * Ciudades: Santiago, Buenos Aires, Lima, Bogotá, etc.
   * Datos obtenidos: temperatura, humedad, presión, viento, etc.

2. **Almacenamiento crudo:**

   * Cloud Storage (estructura: `raw/daily/YYYY-MM-DD/*.json`)
   * BigQuery (tabla: `raw_weather`)

3. **Transformación:**

   * Limpieza de campos, estructuras, y preparación para análisis
   * Tabla resultante: `clean_weather`

4. **Automatización:**

   * Cloud Scheduler ejecuta todos los días a las 10:00 (hora Santiago)
   * Pub/Sub dispara la ejecución de ambas funciones

---

## 📁 Estructura del repositorio

```
weather-function/
├── dags/                    # DAGs para Apache Airflow (opcional)
├── extract_function/       # Código de extracción
├── transform_function/    # Código de transformación
├── terraform/             # Infraestructura como código
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   └── outputs.tf
└── README.md
```

---

## ✅ Despliegue con Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

> Si los recursos ya existen en GCP, se pueden importar para evitar errores 409:

```bash
terraform import google_bigquery_dataset.weather_dataset your-project-id:weather_analytics
terraform import google_storage_bucket.weather_data_bucket your-bucket-name
terraform import google_pubsub_topic.weather_topic projects/your-project-id/topics/weather-trigger
```

---

## 🚀 Estado actual del proyecto

* [x] Extracción y carga a Cloud Storage y BigQuery
* [x] Transformación de datos en BigQuery
* [x] Automatización con Pub/Sub + Scheduler
* [x] Infraestructura definida y versionada con Terraform
* [ ] Agregar dashboards o visualizaciones (próximo paso)

---

## 🤝 Contribución y uso

Este repositorio está pensado como referencia y formación para roles de Data Engineer Junior. Puedes adaptarlo, escalarlo, y versionarlo para proyectos reales.

---

## 🚀 Autor

Franco Ahumada - 2025
Stack actual: Python ⭐ GCP ⭐ Terraform ⭐ GitHub CI CD
