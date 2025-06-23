# Phase 4: Vault Authentication Methods and Configuration
# This file configures Vault after it's deployed

# Get Kubernetes cluster CA certificate
data "kubernetes_config_map" "cluster_info" {
  metadata {
    name      = "cluster-info"
    namespace = "kube-public"
  }
}

# Local values to handle sensitive variables
locals {
  # Create a non-sensitive map from the sensitive variable for for_each
  kyuubi_secrets_map = var.create_vault_secrets ? nonsensitive(var.kyuubi_secrets) : {}
  # Extract CA certificate from kubeconfig
  kubernetes_ca_cert = try(
    yamldecode(data.kubernetes_config_map.cluster_info.data["kubeconfig"])["clusters"][0]["cluster"]["certificate-authority-data"],
    base64decode(data.kubernetes_config_map.cluster_info.data["kubeconfig"])
  )
}

# Wait for Vault to be accessible before configuring it
resource "null_resource" "wait_for_vault_api" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Vault API via port-forward..."
      # Start port-forward in background
      kubectl port-forward -n ${var.vault_namespace} svc/vault 8200:8200 > /dev/null 2>&1 &
      PF_PID=$!
      # Give some time for port-forward to establish
      for i in {1..30}; do
        if curl -s http://127.0.0.1:8200/v1/sys/health >/dev/null 2>&1; then
          echo "Vault port-forward ready"
          break
        fi
        sleep 2
      done
      export VAULT_ADDR=http://127.0.0.1:8200
      export VAULT_TOKEN=root
      # Verify Vault status
      vault status || true
    EOT
    interpreter = ["/bin/sh", "-c"]
  }
}

# Vault KV mount for Kyuubi secrets
resource "vault_mount" "kyuubi_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "kyuubi"
  type        = "kv-v2"
  description = "KV store for Kyuubi application secrets"
}

# Vault KV mount for Airflow secrets
resource "vault_mount" "airflow_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "airflow"
  type        = "kv-v2"
  description = "KV store for Airflow application secrets"
}

# Vault KV mount for Grafana secrets
resource "vault_mount" "grafana_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "grafana"
  type        = "kv-v2"
  description = "KV store for Grafana application secrets"
}

# Vault KV mount for Keycloak secrets
resource "vault_mount" "keycloak_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "keycloak"
  type        = "kv-v2"
  description = "KV store for Keycloak application secrets"
}

# Vault KV mount for Metabase secrets
resource "vault_mount" "metabase_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "metabase"
  type        = "kv-v2"
  description = "KV store for Metabase application secrets"
}

# Vault KV mount for Kafka secrets
resource "vault_mount" "kafka_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "kafka"
  type        = "kv-v2"
  description = "KV store for Kafka platform secrets"
}

# Vault KV mount for Trino secrets
resource "vault_mount" "trino_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "trino"
  type        = "kv-v2"
  description = "KV store for Trino query engine secrets"
}

# Vault PKI mount for certificate management
resource "vault_mount" "pki" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path                      = "pki"
  type                      = "pki"
  description               = "PKI mount for certificate management"
  default_lease_ttl_seconds = 86400    # 1 day
  max_lease_ttl_seconds     = 31536000 # 1 year
}

# Store cluster CA certificate in Vault for reference
resource "vault_kv_secret_v2" "cluster_certificates" {
  depends_on = [vault_mount.kyuubi_kv]
  
  mount = vault_mount.kyuubi_kv.path
  name  = "certificates/cluster"
  
  data_json = jsonencode({
    kubernetes_ca_cert = base64decode(
      yamldecode(data.kubernetes_config_map.cluster_info.data["kubeconfig"])["clusters"][0]["cluster"]["certificate-authority-data"]
    )
    cluster_endpoint = yamldecode(data.kubernetes_config_map.cluster_info.data["kubeconfig"])["clusters"][0]["cluster"]["server"]
  })
}

# Vault authentication backend for Kubernetes
resource "vault_auth_backend" "kubernetes" {
  depends_on = [null_resource.wait_for_vault_api]
  
  type = "kubernetes"
  path = "kubernetes"
}

# Configure Kubernetes auth backend
resource "vault_kubernetes_auth_backend_config" "kubernetes" {
  depends_on = [vault_auth_backend.kubernetes]
  
  backend              = vault_auth_backend.kubernetes.path
  kubernetes_host      = "https://kubernetes.default.svc:443"
  kubernetes_ca_cert   = base64decode(
    yamldecode(data.kubernetes_config_map.cluster_info.data["kubeconfig"])["clusters"][0]["cluster"]["certificate-authority-data"]
  )
}

# OIDC auth backend for Keycloak
resource "vault_auth_backend" "oidc" {
  count = 0  # disabled; managed outside Terraform
  type  = "oidc"
  path  = "oidc"
}

# Configure JWT/OIDC auth backend for Keycloak
resource "vault_jwt_auth_backend" "keycloak" {
  count = 0
  path  = "oidc"    # required but ignored due to count=0
  type  = "oidc"
}

# OIDC role for Vault users
resource "vault_jwt_auth_backend_role" "default" {
  count = 0
  backend   = "oidc"
  role_name = "default"
  user_claim = "sub"
}

# Vault policies for Kyuubi
resource "vault_policy" "kyuubi_read" {
  depends_on = [vault_mount.kyuubi_kv]
  
  name = "kyuubi-read"
  policy = <<EOT
# Allow reading secrets from kyuubi path
path "kyuubi/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "kyuubi/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "kyuubi_write" {
  depends_on = [vault_mount.kyuubi_kv]
  
  name = "kyuubi-write"
  policy = <<EOT
# Allow full access to kyuubi secrets
path "kyuubi/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kyuubi/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Vault policies for Airflow
resource "vault_policy" "airflow_read" {
  depends_on = [vault_mount.airflow_kv]
  
  name = "airflow-read"
  policy = <<EOT
# Allow reading secrets from airflow path
path "airflow/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "airflow/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "airflow_write" {
  depends_on = [vault_mount.airflow_kv]
  
  name = "airflow-write"
  policy = <<EOT
# Allow full access to airflow secrets
path "airflow/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "airflow/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Vault policies for Grafana
resource "vault_policy" "grafana_read" {
  depends_on = [vault_mount.grafana_kv]
  
  name = "grafana-read"
  policy = <<EOT
# Allow reading secrets from grafana path
path "grafana/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "grafana/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "grafana_write" {
  depends_on = [vault_mount.grafana_kv]
  
  name = "grafana-write"
  policy = <<EOT
# Allow full access to grafana secrets
path "grafana/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "grafana/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Vault policies for Keycloak
resource "vault_policy" "keycloak_read" {
  depends_on = [vault_mount.keycloak_kv]
  
  name = "keycloak-read"
  policy = <<EOT
# Allow reading secrets from keycloak path
path "keycloak/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "keycloak/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "keycloak_write" {
  depends_on = [vault_mount.keycloak_kv]
  
  name = "keycloak-write"
  policy = <<EOT
# Allow full access to keycloak secrets
path "keycloak/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "keycloak/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Vault policies for Metabase
resource "vault_policy" "metabase_read" {
  depends_on = [vault_mount.metabase_kv]
  
  name = "metabase-read"
  policy = <<EOT
# Allow reading secrets from metabase path
path "metabase/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "metabase/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "metabase_write" {
  depends_on = [vault_mount.metabase_kv]
  
  name = "metabase-write"
  policy = <<EOT
# Allow full access to metabase secrets
path "metabase/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "metabase/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Vault policies for Kafka
resource "vault_policy" "kafka_read" {
  depends_on = [vault_mount.kafka_kv]
  
  name = "kafka-read"
  policy = <<EOT
# Allow reading secrets from kafka path
path "kafka/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "kafka/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "kafka_write" {
  depends_on = [vault_mount.kafka_kv]
  
  name = "kafka-write"
  policy = <<EOT
# Allow full access to kafka secrets
path "kafka/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "kafka/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Vault policies for Trino
resource "vault_policy" "trino_read" {
  depends_on = [vault_mount.trino_kv]
  
  name = "trino-read"
  policy = <<EOT
# Allow reading secrets from trino path
path "trino/data/*" {
  capabilities = ["read"]
}

# Allow listing secrets
path "trino/metadata/*" {
  capabilities = ["list"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}
EOT
}

resource "vault_policy" "trino_write" {
  depends_on = [vault_mount.trino_kv]
  
  name = "trino-write"
  policy = <<EOT
# Allow full access to trino secrets
path "trino/data/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "trino/metadata/*" {
  capabilities = ["list", "read", "delete"]
}

# Allow reading certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/ca/pem" {
  capabilities = ["read"]
}

# Allow reading own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Kubernetes auth role for Kyuubi service accounts
resource "vault_kubernetes_auth_backend_role" "kyuubi" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "kyuubi"
  bound_service_account_names      = ["kyuubi", "kyuubi-dbt", "kyuubi-dbt-shared"]
  bound_service_account_namespaces = [var.kyuubi_namespace]
  token_ttl                        = 3600
  token_policies                   = ["kyuubi-read"]
}

# Kubernetes auth role for Vault Secrets Operator
resource "vault_kubernetes_auth_backend_role" "vault_secrets_operator" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "vault-secrets-operator"
  bound_service_account_names      = ["vault-secrets-operator-controller-manager"]
  bound_service_account_namespaces = ["vault-secrets-operator-system"]
  token_ttl                        = 3600
  token_policies                   = ["kyuubi-read"]
}

# Kubernetes auth role for Airflow service accounts
resource "vault_kubernetes_auth_backend_role" "airflow" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "airflow"
  bound_service_account_names      = ["airflow-sa"]
  bound_service_account_namespaces = ["airflow"]
  token_ttl                        = 3600
  token_policies                   = ["airflow-read"]
}

# Kubernetes auth role for Grafana service accounts
resource "vault_kubernetes_auth_backend_role" "grafana" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "grafana"
  bound_service_account_names      = ["grafana-sa"]
  bound_service_account_namespaces = ["grafana"]
  token_ttl                        = 3600
  token_policies                   = ["grafana-read"]
}

# Kubernetes auth role for Keycloak service accounts
resource "vault_kubernetes_auth_backend_role" "keycloak" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "keycloak"
  bound_service_account_names      = ["keycloak-sa"]
  bound_service_account_namespaces = ["keycloak"]
  token_ttl                        = 3600
  token_policies                   = ["keycloak-read"]
}

# Kubernetes auth role for Metabase service accounts
resource "vault_kubernetes_auth_backend_role" "metabase" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "metabase"
  bound_service_account_names      = ["metabase-sa"]
  bound_service_account_namespaces = ["metabase"]
  token_ttl                        = 3600
  token_policies                   = ["metabase-read"]
}

# Kubernetes auth role for Kafka platform service accounts
resource "vault_kubernetes_auth_backend_role" "kafka" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "kafka"
  bound_service_account_names      = ["default"]  # Kafka services use default service account
  bound_service_account_namespaces = [var.kafka_platform_namespace]
  token_ttl                        = 3600
  token_policies                   = ["kafka-read"]
}

# Kubernetes auth role for Trino service accounts
resource "vault_kubernetes_auth_backend_role" "trino" {
  depends_on = [vault_kubernetes_auth_backend_config.kubernetes]
  
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "trino"
  bound_service_account_names      = ["trino-sa"]
  bound_service_account_namespaces = ["trino"]
  token_ttl                        = 3600
  token_policies                   = ["trino-read"]
}

# Create secrets in Vault
resource "vault_kv_secret_v2" "kyuubi_secrets" {
  depends_on = [vault_mount.kyuubi_kv]
  
  for_each = local.kyuubi_secrets_map
  
  mount = vault_mount.kyuubi_kv.path
  name  = each.value.path
  
  data_json = jsonencode(each.value.data)
}

# Create Airflow secrets in Vault
resource "vault_kv_secret_v2" "airflow_secrets" {
  depends_on = [vault_mount.airflow_kv]
  
  count = var.create_vault_secrets ? 1 : 0
  
  mount = vault_mount.airflow_kv.path
  name  = "airflow"
  
  data_json = jsonencode({
    postgres_db       = var.kyuubi_secrets.airflow.data.postgres_db
    postgres_user     = var.kyuubi_secrets.airflow.data.postgres_user
    postgres_password = var.kyuubi_secrets.airflow.data.postgres_password
    postgres_host     = var.kyuubi_secrets.airflow.data.postgres_host
    postgres_port     = var.kyuubi_secrets.airflow.data.postgres_port
    sql_alchemy_conn  = var.kyuubi_secrets.airflow.data.sql_alchemy_conn
    fernet_key        = var.kyuubi_secrets.airflow.data.fernet_key
  })
}

# Create Grafana secrets in Vault
resource "vault_kv_secret_v2" "grafana_secrets" {
  depends_on = [vault_mount.grafana_kv]
  
  count = var.create_vault_secrets ? 1 : 0
  
  mount = vault_mount.grafana_kv.path
  name  = "grafana"
  
  data_json = jsonencode({
    username = var.kyuubi_secrets.grafana.data.username
    password = var.kyuubi_secrets.grafana.data.password
  })
}

# Create Keycloak secrets in Vault
resource "vault_kv_secret_v2" "keycloak_secrets" {
  depends_on = [vault_mount.keycloak_kv]
  
  count = var.create_vault_secrets ? 1 : 0
  
  mount = vault_mount.keycloak_kv.path
  name  = "keycloak"
  
  data_json = jsonencode({
    username = "admin"
    password = "admin123"
  })
}

# Create Metabase secrets in Vault
resource "vault_kv_secret_v2" "metabase_secrets" {
  depends_on = [vault_mount.metabase_kv]
  
  count = var.create_vault_secrets ? 1 : 0
  
  mount = vault_mount.metabase_kv.path
  name  = "metabase"
  
  data_json = jsonencode({
    db_name  = "metabase_db"
    username = "metabase"
    password = "metabase123"
    host     = "metabase-db"
    port     = "5432"
  })
}

# Create Kafka secrets in Vault
resource "vault_kv_secret_v2" "kafka_secrets" {
  depends_on = [vault_mount.kafka_kv]
  
  count = var.create_vault_secrets ? 1 : 0
  
  mount = vault_mount.kafka_kv.path
  name  = "config"
  
  data_json = jsonencode({
    # Debezium Postgres Connector credentials
    postgres_cdc_host     = "postgres-cdc.source-data.svc.cluster.local"
    postgres_cdc_port     = "5432"
    postgres_cdc_user     = "cdc_user"
    postgres_cdc_password = "cdc_pass"
    postgres_cdc_database = "inventory"
    
    # MinIO S3 credentials (reusing from kyuubi secrets)
    s3_access_key_id     = var.kyuubi_secrets.minio.data.access_key
    s3_secret_access_key = var.kyuubi_secrets.minio.data.secret_key
    s3_endpoint          = var.kyuubi_secrets.minio.data.endpoint
    
    # Schema Registry URL
    schema_registry_url = "http://schema-registry.kafka-platform.svc.cluster.local:8081"
    
    # Kafka Bootstrap Servers
    kafka_bootstrap_servers = "kafka.kafka-platform.svc.cluster.local:9092"
    
    # Kafka Connect URL
    kafka_connect_url = "http://kafka-connect.kafka-platform.svc.cluster.local:8083"
  })
}

# Create Trino secrets in Vault
resource "vault_kv_secret_v2" "trino_secrets" {
  depends_on = [vault_mount.trino_kv]
  
  count = var.create_vault_secrets ? 1 : 0
  
  mount = vault_mount.trino_kv.path
  name  = "config"
  
  data_json = jsonencode({
    # Hive Metastore connection
    hive_metastore_uri = "thrift://hive-metastore.kyuubi.svc.cluster.local:9083"
    
    # MinIO S3 configuration (reusing from kyuubi secrets)
    s3_access_key     = var.kyuubi_secrets.minio.data.access_key
    s3_secret_key     = var.kyuubi_secrets.minio.data.secret_key
    s3_endpoint       = var.kyuubi_secrets.minio.data.endpoint
    s3_path_style_access = "true"
    
    # Database connections
    postgres_host     = "postgres-cdc.source-data.svc.cluster.local"
    postgres_port     = "5432"
    postgres_database = "inventory"
    postgres_user     = "cdc_user"
    postgres_password = "cdc_pass"
    
    # MariaDB connection for additional catalogs
    mariadb_host     = var.kyuubi_secrets.database.data.mariadb_host
    mariadb_port     = var.kyuubi_secrets.database.data.mariadb_port
    mariadb_user     = var.kyuubi_secrets.database.data.mariadb_user
    mariadb_password = var.kyuubi_secrets.database.data.mariadb_password
    
    # JVM and Memory settings
    trino_max_memory = "4GB"
    trino_max_memory_per_node = "2GB"
    
    # Trino coordinator and worker settings
    coordinator_heap_size = "2G"
    worker_heap_size = "2G"
  })
} 