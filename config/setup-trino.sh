#!/bin/bash

# Create trino.properties from template with environment variables
sed -e "s|NESSIE_HOST|${NESSIE_HOST}|g" \
    -e "s|NESSIE_PORT|${NESSIE_PORT}|g" \
    -e "s|WAREHOUSE_BUCKET|${WAREHOUSE_BUCKET}|g" \
    -e "s|MINIO_HOST|${MINIO_HOST}|g" \
    -e "s|MINIO_PORT|${MINIO_PORT}|g" \
    -e "s|AWS_REGION|${AWS_REGION}|g" \
    -e "s|MINIO_ACCESS_KEY|${MINIO_ACCESS_KEY}|g" \
    -e "s|MINIO_SECRET_KEY|${MINIO_SECRET_KEY}|g" \
    /etc/trino/catalog/trino-template.properties > /etc/trino/catalog/trino.properties

exec "$@"