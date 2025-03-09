import os, sys, pyspark, datetime

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
REST_HOST = os.environ.get('REST_HOST', 'rest-catalog')
REST_PORT = os.environ.get('REST_PORT', '8181')
WAREHOUSE_BUCKET = os.environ.get('WAREHOUSE_BUCKET', 'lakehouse')
MINIO_HOST = os.environ.get('MINIO_HOST')
MINIO_PORT = os.environ.get('MINIO_PORT')

# API endpoints and paths - CRITICAL that these are consistent across services
CATALOG_URI = f"http://{REST_HOST}:{REST_PORT}"  # REST Catalog API URI 
WAREHOUSE = f"s3://{WAREHOUSE_BUCKET}/"          # Warehouse bucket URI
STORAGE_URI = f"http://{MINIO_HOST}:{MINIO_PORT}"  # S3 endpoint URI

conf = (
    pyspark.SparkConf()
        .setAppName("ReadParquetFromMinIO")
        
        # Global runtime configuration
        .set("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .set("spark.sql.defaultCatalog", "iceberg")
        # Configure AWS credentials globally
        .set("spark.hadoop.fs.s3a.access.key", os.environ['AWS_ACCESS_KEY_ID'])
        .set("spark.hadoop.fs.s3a.secret.key", os.environ['AWS_SECRET_ACCESS_KEY'])
        .set("spark.hadoop.fs.s3a.endpoint", STORAGE_URI)
        .set("spark.hadoop.fs.s3a.path.style.access", "true")
        .set("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .set("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem")
        .set("spark.hadoop.fs.s3a.aws.credentials.provider", "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider")
        # REST catalog configuration
        .set("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog")
        .set("spark.sql.catalog.iceberg.catalog-impl", "org.apache.iceberg.rest.RESTCatalog")
        .set("spark.sql.catalog.iceberg.uri", CATALOG_URI)
        .set("spark.sql.catalog.iceberg.warehouse", WAREHOUSE)
        .set("spark.sql.catalog.iceberg.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        # REST catalog S3 settings - CRITICAL for correct endpoint
        .set("spark.sql.catalog.iceberg.s3.endpoint", STORAGE_URI)
        .set("spark.sql.catalog.iceberg.s3.path-style-access", "true")
        .set("spark.sql.catalog.iceberg.s3.access-key-id", os.environ['AWS_ACCESS_KEY_ID'])
        .set("spark.sql.catalog.iceberg.s3.secret-access-key", os.environ['AWS_SECRET_ACCESS_KEY'])
)

def load_spark_df(object_path):
    # Define MinIO Path (use s3a:// prefix)
    minio_path = "s3a://datalake/" + object_path

    # Read Parquet file
    df = spark.read.parquet(minio_path)

    # Show DataFrame contents
    return df

def load_to_lakehouse(df, table_name):
    print(f"Starting to load data to lakehouse table: {table_name}")
    
    # Create namespace if it doesn't exist
    try:
        spark.sql("CREATE NAMESPACE IF NOT EXISTS iceberg.src")
        print("Namespace iceberg.src exists or was created")
    except Exception as e:
        print(f"Error checking namespace: {str(e)}")
    
    # Use catalog.schema.table format for writing
    ds_name = "iceberg.src." + table_name
    print(f"Writing to table: {ds_name}")
    
    try:
        # Add additional properties to make tables compatible with Trino
        # Using more minimal options to avoid S3 configuration conflicts
        print("Starting table write operation")
        df.writeTo(ds_name) \
          .option("write.format.default", "parquet") \
          .option("format-version", "2") \
          .createOrReplace()
        print("Table write operation completed successfully")
    except Exception as e:
        print(f"Error writing to table: {str(e)}")
        raise


if __name__ == "__main__":
    try:
        # Get input table name
        table_name = sys.argv[1]
        print(f"Processing table: {table_name}")

        # Initialize SparkSession with detailed configuration
        print("Initializing Spark session")
        spark = SparkSession.builder.config(conf=conf).getOrCreate()
        print(f"Spark session created, version: {spark.version}")
        
        # Print S3 configuration for debugging
        print(f"S3 endpoint: {STORAGE_URI}")
        print(f"Warehouse location: {WAREHOUSE}")
        print(f"REST catalog URI: {CATALOG_URI}")

        # List objects from MinIO
        print("Listing objects from datalake")
        objects = client.list_objects("datalake", recursive=True, prefix="airbyte/")
        found = False
        
        # Process matching objects
        for obj in objects:
            if table_name in obj._object_name:
                found = True
                print(f"Found matching object: {obj._object_name}")
                df = load_spark_df(obj._object_name)
                print(f"Loaded DataFrame with {df.count()} rows")
                
                # Write to Iceberg table
                load_to_lakehouse(df, table_name)
                print(f"Successfully loaded data to table: iceberg.src.{table_name}")

                # Expire Snapshots
                current_timestamp = datetime.datetime.now()
                three_days_ago= current_timestamp + datetime.timedelta(days=-3)
                spark.sql(f"CALL iceberg.system.expire_snapshots('src.{table_name}',TIMESTAMP '{three_days_ago}')")
                print(f"Successfully expired snapshots for: iceberg.src.{table_name} until {three_days_ago}.")
                
                # Stop Spark session
                print("Stopping Spark session")
                spark.stop()
                break
        
        if not found:
            print(f"No objects found matching table name: {table_name}")
    
    except Exception as e:
        print(f"ERROR: {str(e)}")
        # Print more detailed error information
        import traceback
        traceback.print_exc()
        sys.exit(1)
