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


def get_loaded_files(table_name):
    """Retrieve list of previously loaded files from Iceberg metadata table."""
    try:
        df = spark.sql(f"SELECT file_path FROM iceberg.metadata.{table_name}_loaded_files")
        return set(row.file_path for row in df.collect())
    except:
        return set()  # If metadata table does not exist, assume no files loaded

def save_loaded_files(table_name, file_paths):
    """Save newly processed files to metadata table."""
    df = spark.createDataFrame([(path,) for path in file_paths], ["file_path"])
    df.write.mode("append").saveAsTable(f"iceberg.metadata.{table_name}_loaded_files")

def load_spark_df(file_list):
    """Load multiple parquet files into a DataFrame."""
    if not file_list:
        return None
    file_paths = [f"s3a://datalake/{path}" for path in file_list]
    return spark.read.parquet(*file_paths)

def load_to_lakehouse(df, table_name, load_type):
    print(f"Loading data to lakehouse table: {table_name} as {load_type} load")

    # Create namespace if it doesn't exist
    spark.sql("CREATE NAMESPACE IF NOT EXISTS iceberg.src")

    ds_name = f"iceberg.src.{table_name}"
    print(f"Writing to table: {ds_name}")

    # Check if the table exists
    table_exists = False
    try:
        table_check = spark.sql(f"SHOW TABLES IN iceberg.src LIKE '{table_name}'")
        if table_check.count() > 0:
            table_exists = True
    except:
        table_exists = False

    try:
        if load_type == "full":
            df.writeTo(ds_name) \
              .option("write.format.default", "parquet") \
              .option("format-version", "2") \
              .createOrReplace()
        else:
            if table_exists:
                df.writeTo(ds_name) \
                  .option("write.format.default", "parquet") \
                  .option("format-version", "2") \
                  .append()
            else:
                print(f"Table {ds_name} does not exist, creating it now.")
                df.writeTo(ds_name) \
                  .option("write.format.default", "parquet") \
                  .option("format-version", "2") \
                  .create()

        print(f"{load_type.capitalize()} load operation completed successfully")

    except Exception as e:
        print(f"Error writing to table: {str(e)}")
        raise

if __name__ == "__main__":
    try:
        if len(sys.argv) < 3:
            print("Usage: extract_load.py <table_name> <load_type: full | incremental>")
            sys.exit(1)

        table_name = sys.argv[1]
        load_type = sys.argv[2].lower()  # "full" or "incremental"
        print(f"Processing table: {table_name} with {load_type} load")

        print("Initializing Spark session")
        spark = SparkSession.builder.config(conf=conf).getOrCreate()
        
        print(f"Spark session created, version: {spark.version}")
        print(f"S3 endpoint: {STORAGE_URI}")
        print(f"Warehouse location: {WAREHOUSE}")
        print(f"REST catalog URI: {CATALOG_URI}")

        # List objects in MinIO
        print("Listing objects from datalake")
        objects = client.list_objects("datalake", recursive=True, prefix=f"airbyte/{table_name}/")
        file_list = [obj.object_name for obj in objects]

        if not file_list:
            print(f"No files found for table: {table_name}")
            sys.exit(0)

        if load_type == "full":
            # Always load the latest file, ignore tracking
            latest_file = sorted(file_list)[-1]  # Assuming lexicographical order corresponds to timestamps
            df = load_spark_df([latest_file])
            if df:
                print(f"Loaded DataFrame with {df.count()} rows")
                load_to_lakehouse(df, table_name, load_type)
                print(f"Successfully performed full load for iceberg.src.{table_name}")
        
        else:  # Incremental Load
            loaded_files = get_loaded_files(table_name)
            new_files = [f for f in file_list if f not in loaded_files]
            print(f"New files found: {len(new_files)}")

            if new_files:
                df = load_spark_df(new_files)
                if df:
                    print(f"Loaded DataFrame with {df.count()} rows")
                    load_to_lakehouse(df, table_name, load_type)
                    save_loaded_files(table_name, new_files)
                    print(f"Successfully loaded new files to iceberg.src.{table_name}")
        
        # Expire Snapshots
        current_timestamp = datetime.datetime.now()
        three_days_ago = current_timestamp + datetime.timedelta(days=-3)
        spark.sql(f"CALL iceberg.system.expire_snapshots('src.{table_name}', TIMESTAMP '{three_days_ago}')")
        print(f"Successfully expired snapshots for: iceberg.src.{table_name} until {three_days_ago}.")

        print("Stopping Spark session")
        spark.stop()
    
    except Exception as e:
        print(f"ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
