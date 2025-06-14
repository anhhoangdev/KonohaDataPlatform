# Configure Vault secrets for Kyuubi platform
resource "vault_mount" "kyuubi" {
  path        = "kyuubi"
  type        = "kv-v2"
  description = "KV store for Kyuubi platform secrets"
  
  depends_on = [helm_release.vault]
}

# Database credentials
resource "vault_kv_secret_v2" "database" {
  mount = vault_mount.kyuubi.path
  name  = "database"
  
  data_json = jsonencode({
    mariadb_root_password = "kyuubi-root-password"
    mariadb_user         = "kyuubi"
    mariadb_password     = "kyuubi-password"
    mariadb_database     = "metastore"
    
    # Hive Metastore database connection
    hive_metastore_connection_url      = "jdbc:mysql://mariadb:3306/metastore"
    hive_metastore_connection_user     = "kyuubi"
    hive_metastore_connection_password = "kyuubi-password"
  })
}

# Spark configuration secrets
resource "vault_kv_secret_v2" "spark" {
  mount = vault_mount.kyuubi.path
  name  = "spark"
  
  data_json = jsonencode({
    # Spark Kubernetes configuration
    spark_kubernetes_namespace                           = local.namespace
    spark_kubernetes_authenticate_driver_serviceaccount = "kyuubi-sa"
    spark_kubernetes_container_image                     = "spark-engine-iceberg:${var.spark_image_tag}"
    spark_kubernetes_container_image_pullpolicy          = "Never"
    
    # Spark resource configuration
    spark_driver_memory          = "5g"
    spark_driver_memory_overhead = "1g"
    spark_driver_cores          = "1"
    spark_executor_memory       = var.spark_executor_memory
    spark_executor_cores        = var.spark_executor_cores
    spark_executor_instances    = "2"
    
    # Dynamic allocation
    spark_dynamicallocation_enabled                           = "true"
    spark_dynamicallocation_minexecutors                     = "0"
    spark_dynamicallocation_maxexecutors                     = var.spark_max_executors
    spark_dynamicallocation_executoridletimeout              = "60s"
    spark_dynamicallocation_cachedexecutoridletimeout        = "1800s"
    spark_dynamicallocation_sustainedschedulerbacklogtimeout = "1s"
    spark_dynamicallocation_schedulerbacklogtimeout          = "1s"
    
    # Hive integration
    spark_sql_catalogimplementation = "hive"
    spark_hive_metastore_uris      = "thrift://hive-metastore:9083"
    
    # Additional Spark configuration
    spark_eventlog_enabled = "true"
    spark_eventlog_dir     = "/tmp/spark-events"
    spark_serializer       = "org.apache.spark.serializer.KryoSerializer"
    spark_jars_ivy         = "/tmp/.ivy2"
    spark_user             = "spark"
  })
}

# Kyuubi server configuration
resource "vault_kv_secret_v2" "kyuubi" {
  mount = vault_mount.kyuubi.path
  name  = "kyuubi-server"
  
  data_json = jsonencode({
    # Frontend configuration
    kyuubi_frontend_bind_host = "0.0.0.0"
    kyuubi_frontend_bind_port = "10009"
    kyuubi_frontend_rest_bind_port = "10099"
    
    # Engine configuration
    kyuubi_session_engine_type = "SPARK_SQL"
    kyuubi_session_engine_spark_main_resource = "local:///opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar"
    kyuubi_engine_spark_application_name = "kyuubi-spark-sql-engine"
    
    # High availability
    kyuubi_ha_enabled = "false"
    
    # Authentication
    kyuubi_authentication = "NONE"
    
    # Session timeouts
    kyuubi_user_session_timeout   = var.kyuubi_user_timeout
    kyuubi_server_session_timeout = var.kyuubi_server_timeout
  })
}

# AWS/S3 credentials (for Iceberg)
resource "vault_kv_secret_v2" "aws" {
  mount = vault_mount.kyuubi.path
  name  = "aws"
  
  data_json = jsonencode({
    aws_access_key_id     = "minioadmin"
    aws_secret_access_key = "minioadmin"
    aws_region           = "us-east-1"
    aws_s3_endpoint      = "http://minio:9000"
    aws_s3_path_style_access = "true"
  })
}

# Monitoring credentials (if enabled)
resource "vault_kv_secret_v2" "monitoring" {
  count = var.enable_monitoring ? 1 : 0
  mount = vault_mount.kyuubi.path
  name  = "monitoring"
  
  data_json = jsonencode({
    grafana_admin_user     = "admin"
    grafana_admin_password = "kyuubi-grafana-password"
    prometheus_retention   = "15d"
  })
}

# Vault policy for Kyuubi applications
resource "vault_policy" "kyuubi_policy" {
  name = "kyuubi-policy"
  
  policy = <<EOT
# Allow reading all secrets under kyuubi path
path "kyuubi/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "kyuubi/metadata/*" {
  capabilities = ["list"]
}

# Allow token renewal
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow token lookup
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Kubernetes auth method for Vault
resource "vault_auth_backend" "kubernetes" {
  type = "kubernetes"
  path = "kubernetes"
}

# Configure Kubernetes auth
resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  backend         = vault_auth_backend.kubernetes.path
  kubernetes_host = "https://kubernetes.default.svc:443"
}

# Kubernetes auth role for Kyuubi service account
resource "vault_kubernetes_auth_backend_role" "kyuubi" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "kyuubi-role"
  bound_service_account_names      = ["kyuubi-sa"]
  bound_service_account_namespaces = [local.namespace]
  token_ttl                        = 3600
  token_policies                   = [vault_policy.kyuubi_policy.name]
} 