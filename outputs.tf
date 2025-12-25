output "postgres_endpoint" {
  description = "PostgreSQL connection endpoint"
  value       = "localhost:${var.postgres_port}"
}

output "rest_catalog_endpoint" {
  description = "REST catalog service endpoint"
  value       = "http://localhost:${var.rest_port}"
}

output "trino_endpoint" {
  description = "Trino query engine endpoint"
  value       = "http://localhost:${var.trino_port}"
}

output "spark_ui_endpoint" {
  description = "Spark master UI endpoint"
  value       = "http://localhost:${var.spark_ui_port}"
}

output "spark_master_endpoint" {
  description = "Spark master connection endpoint"
  value       = "spark://localhost:${var.spark_master_port}"
}

output "spark_history_endpoint" {
  description = "Spark history server endpoint"
  value       = "http://localhost:${var.spark_history_port}"
}

output "network_name" {
  description = "Docker network name"
  value       = docker_network.lakehouse_network.name
}