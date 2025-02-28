# Lakehouse Data Platform

A complete data lakehouse platform with Spark, Trino, and Nessie.

## Components

- **Nessie**: Git-like data catalog service
- **Trino**: SQL query engine
- **Spark**: Data processing engine

## Setup and Configuration

### Prerequisites

- Docker and Docker Compose
- At least 8GB RAM available for Docker

### Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/lakehouse.git
   cd lakehouse
   ```

2. Create or edit the .env file with your configuration:

3. Start the data platform:
   ```bash
   docker-compose up -d
   ```

4. Access the services:
   - Trino UI: http://localhost:8082
   - Spark UI: http://localhost:8080
   - Spark History Server: http://localhost:18080
   - Nessie UI: http://localhost:19120

### Environment Variables

All configuration is done through environment variables in the `.env` file:

| Variable | Description |
|----------|-------------|
| MINIO_HOST | MinIO hostname |
| MINIO_PORT | MinIO API port |
| MINIO_ACCESS_KEY | MinIO access key |
| MINIO_SECRET_KEY | MinIO secret key |
| NESSIE_HOST | Nessie hostname |
| NESSIE_PORT | Nessie API port |
| WAREHOUSE_BUCKET | S3 bucket for data warehouse |
| USE_EXTERNAL_NETWORK | Use external Docker network |
| NETWORK_NAME | Docker network name |

## Usage

### Loading Data to Lakehouse

Use the Python script to load data:

```bash
docker exec -it spark-master python /opt/spark/scripts/extract_load.py table_name
```

### Querying with Trino

Connect to Trino and query data:

```bash
docker exec -it trino trino
```

```sql
-- In Trino CLI
USE nessie.src;
SELECT * FROM your_table LIMIT 10;
```

### Using with dbt

This lakehouse can be used with dbt for data transformations. To connect dbt:

1. Install dbt and the iceberg adapter:
   ```bash
   pip install dbt-core dbt-trino
   ```

2. Configure dbt profiles.yml:
   ```yaml
   lakehouse:
     target: dev
     outputs:
       dev:
         type: trino
         host: localhost
         port: 8082
         user: trino
         catalog: nessie
         schema: src
   ```

## Deployment

For server deployment:

1. Clone the repository on your server
2. Configure `.env` with appropriate values
3. Start with `docker-compose up -d`
4. For production, consider setting up monitoring, backups, and TLS certificates

## Maintenance

- **Scaling**: Add more Spark workers by scaling that service
- **Monitoring**: Consider adding Prometheus/Grafana for monitoring

## Troubleshooting

- If containers fail to start, check logs with `docker-compose logs service_name`
- Ensure all ports are available and not used by other services
- Verify network connectivity between containers with `docker exec -it container_name ping other_container`
