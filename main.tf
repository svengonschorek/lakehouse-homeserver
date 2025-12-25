terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6.2"
    }
  }
}

provider "docker" {}

resource "docker_network" "lakehouse_network" {
  name = var.network_name
}

resource "docker_volume" "postgres_data" {
  name = "postgres_data"
}

resource "docker_volume" "spark_logs" {
  name = "spark_logs"
}

resource "docker_image" "postgres" {
  name = "postgres:13"
}

resource "docker_image" "iceberg_rest" {
  name = "tabulario/iceberg-rest:1.6.0"
}

resource "docker_image" "trino" {
  name = "trinodb/trino"
}

resource "docker_image" "spark_image" {
  name = "spark-image"
  build {
    context    = "."
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "postgres" {
  name  = "postgres"
  image = docker_image.postgres.image_id

  ports {
    internal = 5432
    external = var.postgres_port
  }

  env = [
    "PGDATA=/var/lib/postgresql/data",
    "POSTGRES_USER=${var.catalog_jdbc_user}",
    "POSTGRES_PASSWORD=${var.catalog_jdbc_password}",
    "POSTGRES_DB=iceberg_catalog",
    "POSTGRES_HOST_AUTH_METHOD=md5"
  ]

  volumes {
    volume_name    = docker_volume.postgres_data.name
    container_path = "/var/lib/postgresql/data"
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ${var.catalog_jdbc_user} -d iceberg_catalog"]
    interval = "5s"
    timeout  = "5s"
    retries  = 5
  }

  networks_advanced {
    name = docker_network.lakehouse_network.name
  }
}

resource "docker_container" "rest_catalog" {
  name  = "rest-catalog"
  image = docker_image.iceberg_rest.image_id

  ports {
    internal = 8181
    external = var.rest_port
  }

  env = [
    "CATALOG_IMPL=org.apache.iceberg.rest.RESTCatalog",
    "CATALOG_S3_ENDPOINT=http://${var.minio_host}:${var.minio_port}",
    "CATALOG_WAREHOUSE=s3://${var.warehouse_bucket}/",
    "CATALOG_IO__IMPL=org.apache.iceberg.aws.s3.S3FileIO",
    "AWS_S3_ENDPOINT=http://${var.minio_host}:${var.minio_port}",
    "AWS_REGION=${var.aws_region}",
    "AWS_ACCESS_KEY_ID=${var.minio_access_key}",
    "AWS_SECRET_ACCESS_KEY=${var.minio_secret_key}",
    "CATALOG_URI=jdbc:postgresql://postgres/iceberg_catalog",
    "CATALOG_JDBC_USER=${var.catalog_jdbc_user}",
    "CATALOG_JDBC_PASSWORD=${var.catalog_jdbc_password}"
  ]

  depends_on = [docker_container.postgres]

  networks_advanced {
    name = docker_network.lakehouse_network.name
  }
}

resource "docker_container" "trino" {
  name  = "trino"
  image = docker_image.trino.image_id

  ports {
    internal = 8080
    external = var.trino_port
  }

  volumes {
    host_path      = "${path.cwd}/config/iceberg-template.properties"
    container_path = "/etc/trino/catalog/iceberg-template.properties"
  }

  volumes {
    host_path      = "${path.cwd}/config/setup-trino.sh"
    container_path = "/usr/local/bin/setup-trino.sh"
  }

  env = [
    "REST_HOST=${var.rest_host}",
    "REST_PORT=${var.rest_port}",
    "MINIO_HOST=${var.minio_host}",
    "MINIO_PORT=${var.minio_port}",
    "MINIO_ACCESS_KEY=${var.minio_access_key}",
    "MINIO_SECRET_KEY=${var.minio_secret_key}",
    "WAREHOUSE_BUCKET=${var.warehouse_bucket}"
  ]

  entrypoint = ["/usr/local/bin/setup-trino.sh", "/usr/lib/trino/bin/run-trino"]

  depends_on = [docker_container.rest_catalog]

  networks_advanced {
    name = docker_network.lakehouse_network.name
  }
}

resource "docker_container" "spark_master" {
  name  = "spark-master"
  image = docker_image.spark_image.image_id

  ports {
    internal = 8080
    external = var.spark_ui_port
  }

  ports {
    internal = 7077
    external = var.spark_master_port
  }

  volumes {
    host_path      = "${path.cwd}/scripts"
    container_path = "/opt/spark/scripts"
  }

  volumes {
    host_path      = "${path.cwd}/data"
    container_path = "/opt/spark/data"
  }

  volumes {
    volume_name    = docker_volume.spark_logs.name
    container_path = "/opt/spark/spark-events"
  }

  volumes {
    host_path      = "${path.cwd}/warehouse"
    container_path = "/opt/spark/warehouse"
  }

  env = [
    "SPARK_NO_DAEMONIZE=true",
    "REST_HOST=${var.rest_host}",
    "REST_PORT=${var.rest_port}",
    "MINIO_HOST=${var.minio_host}",
    "MINIO_PORT=${var.minio_port}",
    "MINIO_ENDPOINT=${var.minio_host}:${var.minio_port}",
    "WAREHOUSE_BUCKET=${var.warehouse_bucket}",
    "AWS_REGION=${var.aws_region}",
    "AWS_ACCESS_KEY_ID=${var.minio_access_key}",
    "AWS_SECRET_ACCESS_KEY=${var.minio_secret_key}",
    "MINIO_ACCESS_KEY=${var.minio_access_key}",
    "MINIO_SECRET_KEY=${var.minio_secret_key}"
  ]

  entrypoint = ["./entrypoint.sh", "master"]

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://spark-master:8080"]
    interval = "5s"
    timeout  = "3s"
    retries  = 3
  }

  depends_on = [docker_container.rest_catalog]

  networks_advanced {
    name = docker_network.lakehouse_network.name
  }
}

resource "docker_container" "spark_history_server" {
  name  = "spark-history"
  image = docker_image.spark_image.image_id

  ports {
    internal = 18080
    external = var.spark_history_port
  }

  volumes {
    host_path      = "${path.cwd}/scripts"
    container_path = "/opt/spark/scripts"
  }

  volumes {
    host_path      = "${path.cwd}/data"
    container_path = "/opt/spark/data"
  }

  volumes {
    volume_name    = docker_volume.spark_logs.name
    container_path = "/opt/spark/spark-events"
  }

  volumes {
    host_path      = "${path.cwd}/warehouse"
    container_path = "/opt/spark/warehouse"
  }

  env = [
    "SPARK_NO_DAEMONIZE=true",
    "REST_HOST=${var.rest_host}",
    "REST_PORT=${var.rest_port}",
    "MINIO_HOST=${var.minio_host}",
    "MINIO_PORT=${var.minio_port}",
    "MINIO_ENDPOINT=${var.minio_host}:${var.minio_port}",
    "WAREHOUSE_BUCKET=${var.warehouse_bucket}",
    "AWS_REGION=${var.aws_region}",
    "AWS_ACCESS_KEY_ID=${var.minio_access_key}",
    "AWS_SECRET_ACCESS_KEY=${var.minio_secret_key}",
    "MINIO_ACCESS_KEY=${var.minio_access_key}",
    "MINIO_SECRET_KEY=${var.minio_secret_key}"
  ]

  entrypoint = ["./entrypoint.sh", "history"]

  depends_on = [docker_container.spark_master]

  networks_advanced {
    name = docker_network.lakehouse_network.name
  }
}

resource "docker_container" "spark_worker" {
  name  = "spark-worker"
  image = docker_image.spark_image.image_id

  volumes {
    host_path      = "${path.cwd}/scripts"
    container_path = "/opt/spark/scripts"
  }

  volumes {
    host_path      = "${path.cwd}/data"
    container_path = "/opt/spark/data"
  }

  volumes {
    volume_name    = docker_volume.spark_logs.name
    container_path = "/opt/spark/spark-events"
  }

  volumes {
    host_path      = "${path.cwd}/warehouse"
    container_path = "/opt/spark/warehouse"
  }

  env = [
    "SPARK_NO_DAEMONIZE=true",
    "REST_HOST=${var.rest_host}",
    "REST_PORT=${var.rest_port}",
    "MINIO_HOST=${var.minio_host}",
    "MINIO_PORT=${var.minio_port}",
    "MINIO_ENDPOINT=${var.minio_host}:${var.minio_port}",
    "AWS_ACCESS_KEY_ID=${var.minio_access_key}",
    "AWS_SECRET_ACCESS_KEY=${var.minio_secret_key}",
    "WAREHOUSE_BUCKET=${var.warehouse_bucket}",
    "AWS_REGION=${var.aws_region}",
    "MINIO_ACCESS_KEY=${var.minio_access_key}",
    "MINIO_SECRET_KEY=${var.minio_secret_key}"
  ]

  entrypoint = ["./entrypoint.sh", "worker"]

  depends_on = [docker_container.spark_master]

  networks_advanced {
    name = docker_network.lakehouse_network.name
  }
}