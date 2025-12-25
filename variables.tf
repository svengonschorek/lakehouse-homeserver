variable "network_name" {
  description = "Name of the Docker network"
  type        = string
  default     = "homeserver_network"
}

variable "postgres_port" {
  description = "External port for PostgreSQL"
  type        = number
  default     = 5432
}

variable "catalog_jdbc_user" {
  description = "PostgreSQL username for Iceberg catalog"
  type        = string
  default     = "admin"
}

variable "catalog_jdbc_password" {
  description = "PostgreSQL password for Iceberg catalog"
  type        = string
  sensitive   = true
  default     = "password"
}

variable "rest_port" {
  description = "External port for REST catalog service"
  type        = number
  default     = 8181
}

variable "rest_host" {
  description = "Hostname for REST catalog service"
  type        = string
  default     = "rest-catalog"
}

variable "minio_host" {
  description = "MinIO hostname or IP address"
  type        = string
  default     = "192.168.178.36"
}

variable "minio_port" {
  description = "MinIO port"
  type        = number
  default     = 9000
}

variable "minio_access_key" {
  description = "MinIO access key"
  type        = string
  sensitive   = true
  default     = "Fx1EG8Mi9byz7LBmJHZN"
}

variable "minio_secret_key" {
  description = "MinIO secret key"
  type        = string
  sensitive   = true
  default     = "iKPdd1RjBOWd2Wzza56ruJ9r0fu7p88ViNMcvQWO"
}

variable "warehouse_bucket" {
  description = "S3 bucket name for data warehouse"
  type        = string
  default     = "lakehouse"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "trino_port" {
  description = "External port for Trino"
  type        = number
  default     = 8082
}

variable "spark_ui_port" {
  description = "External port for Spark UI"
  type        = number
  default     = 8080
}

variable "spark_master_port" {
  description = "External port for Spark master"
  type        = number
  default     = 7077
}

variable "spark_history_port" {
  description = "External port for Spark history server"
  type        = number
  default     = 18080
}