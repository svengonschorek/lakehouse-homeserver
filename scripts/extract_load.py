import os, sys, pyspark

from minio import Minio
from pyspark.sql import SparkSession

# Minio client config
client = Minio(
    os.environ['MINIO_ENDPOINT'],
    access_key=os.environ['AWS_ACCESS_KEY_ID'],
    secret_key=os.environ['AWS_SECRET_ACCESS_KEY'],
    secure=False
)

#Spark config
NESSIE_HOST = os.environ.get('NESSIE_HOST', 'nessie')
NESSIE_PORT = os.environ.get('NESSIE_PORT', '19120')
WAREHOUSE_BUCKET = os.environ.get('WAREHOUSE_BUCKET', 'lakehouse')

CATALOG_URI = f"http://{NESSIE_HOST}:{NESSIE_PORT}/api/v1"  # Nessie Server URI
WAREHOUSE = f"s3://{WAREHOUSE_BUCKET}/"                     # Minio Address to Write to
STORAGE_URI = "http://" + os.environ['MINIO_ENDPOINT']      # Minio endpoint from env vars

conf = (
    pyspark.SparkConf()
        .setAppName("ReadParquetFromMinIO")
        .set("spark.hadoop.fs.s3a.endpoint", "http://" + os.environ['MINIO_ENDPOINT'])
        .set("spark.hadoop.fs.s3a.access.key", os.environ['AWS_ACCESS_KEY_ID'])
        .set("spark.hadoop.fs.s3a.secret.key", os.environ['AWS_SECRET_ACCESS_KEY'])
        .set("spark.hadoop.fs.s3a.path.style.access", "true")
        .set("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .set("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        # setup spark sql
        .set('spark.sql.extensions', 'org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions,org.projectnessie.spark.extensions.NessieSparkSessionExtensions')
        # Configure Nessie catalog
        .set('spark.sql.catalog.nessie', 'org.apache.iceberg.spark.SparkCatalog')
        .set('spark.sql.catalog.nessie.uri', CATALOG_URI)
        .set('spark.sql.catalog.nessie.ref', 'main')
        .set('spark.sql.catalog.nessie.authentication.type', 'NONE')
        .set('spark.sql.catalog.nessie.catalog-impl', 'org.apache.iceberg.nessie.NessieCatalog')
        # Set Minio as the S3 endpoint for Iceberg storage
        .set('spark.sql.catalog.nessie.s3.endpoint', STORAGE_URI)
        .set('spark.sql.catalog.nessie.warehouse', WAREHOUSE)
        .set('spark.sql.catalog.nessie.io-impl', 'org.apache.iceberg.aws.s3.S3FileIO')
)

def load_spark_df(object_path):

    # Define MinIO Path (use s3a:// prefix)
    minio_path = "s3a://datalake/" + object_path

    # Read Parquet file
    df = spark.read.parquet(minio_path)

    # Show DataFrame contents
    return df

def load_to_lakehouse(df, table_name):
    # Check if namespace exists using a try-except approach
    try:
        spark.sql("USE nessie.src")
    except Exception as e:
        if "SCHEMA_NOT_FOUND" in str(e):
            spark.sql("CREATE NAMESPACE nessie.src")
    
    ds_name = "nessie.src." + table_name
    df.writeTo(ds_name).createOrReplace()


if __name__ == "__main__":

    # get input variable
    table_name = sys.argv[1]

    # Initialize SparkSession
    spark = SparkSession.builder.config(conf=conf).getOrCreate()

    objects = client.list_objects("datalake", recursive=True, prefix="airbyte/")
    for obj in objects:
        if table_name in obj._object_name:
            df = load_spark_df(obj._object_name)
            load_to_lakehouse(df, table_name)

            # stop spark executor
            spark.stop()
