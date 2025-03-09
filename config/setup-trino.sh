#!/bin/bash

# Create trino.properties from template with environment variables
sed -e "s|REST_HOST|${REST_HOST}|g" \
    -e "s|REST_PORT|${REST_PORT}|g" \
    -e "s|WAREHOUSE_BUCKET|${WAREHOUSE_BUCKET}|g" \
    -e "s|MINIO_HOST|${MINIO_HOST}|g" \
    -e "s|MINIO_PORT|${MINIO_PORT}|g" \
    -e "s|MINIO_ACCESS_KEY|${MINIO_ACCESS_KEY}|g" \
    -e "s|MINIO_SECRET_KEY|${MINIO_SECRET_KEY}|g" \
    /etc/trino/catalog/iceberg-template.properties > /etc/trino/catalog/iceberg.properties

exec "$@"
