variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8200"
}

variable "vault_token" {
  description = "Vault authentication token"
  type        = string
  default     = ""
  sensitive   = true
}

# Namespace Configuration Variables
variable "vault_namespace" {
  description = "Kubernetes namespace for Vault"
  type        = string
  default     = "vault-system"
}

variable "kyuubi_namespace" {
  description = "Kubernetes namespace for Kyuubi applications"
  type        = string
  default     = "kyuubi"
}

variable "vault_dev_mode" {
  description = "Enable Vault development mode"
  type        = bool
  default     = true
}

variable "vault_ui_enabled" {
  description = "Enable Vault UI"
  type        = bool
  default     = true
}

variable "vault_storage_size" {
  description = "Vault storage size"
  type        = string
  default     = "10Gi"
}

variable "vault_replicas" {
  description = "Number of Vault replicas"
  type        = number
  default     = 1
}

variable "enable_auto_unseal" {
  description = "Enable auto-unseal for Vault"
  type        = bool
  default     = false
}

variable "enable_vault_secrets_operator" {
  description = "Enable Vault Secrets Operator for Kubernetes secret management"
  type        = bool
  default     = true
}

variable "vault_log_level" {
  description = "Vault log level"
  type        = string
  default     = "info"
  validation {
    condition     = contains(["trace", "debug", "info", "warn", "error"], var.vault_log_level)
    error_message = "Log level must be one of: trace, debug, info, warn, error."
  }
}

variable "create_vault_secrets" {
  description = "Create initial Vault secrets for Kyuubi"
  type        = bool
  default     = true
}

variable "kyuubi_secrets" {
  description = "Secrets to create for Kyuubi applications"
  type = map(object({
    path = string
    data = map(string)
  }))
  default = {
    database = {
      path = "kyuubi/database"
      data = {
        mariadb_user     = "kyuubi"
        mariadb_password = "kyuubi123"
        mariadb_database = "kyuubi_metastore"
        mariadb_host     = "mariadb"
        mariadb_port     = "3306"
      }
    }
    spark = {
      path = "kyuubi/spark"
      data = {
        spark_executor_memory = "12g"
        spark_executor_cores  = "2"
        spark_max_executors   = "9"
        spark_driver_memory   = "4g"
      }
    }
    kyuubi_server = {
      path = "kyuubi/server"
      data = {
        kyuubi_user_timeout   = "PT30S"
        kyuubi_server_timeout = "PT15M"
        kyuubi_log_level      = "INFO"
      }
    }
    # 🔐 MinIO credentials used by MinIO itself, Hive Metastore, and Kyuubi
    # These values are ONLY intended for local development. Override them in
    # terraform.tfvars (or via CI secrets) for non-dev environments.
    minio = {
      path = "kyuubi/minio"
      data = {
        access_key = "minioadmin"
        secret_key = "minioadmin123"
        endpoint   = "http://minio:9000"
      }
    }
    # 📊 Metabase internal Postgres database credentials
    metabase = {
      path = "kyuubi/metabase"
      data = {
        db_name  = "metabase_db"
        username = "metabase"
        password = "metabase123"
        host     = "metabase-db"
        port     = "5432"
      }
    }
    # 🔑 Keycloak administrator credentials (dev only)
    keycloak = {
      path = "kyuubi/keycloak"
      data = {
        username = "admin"
        password = "admin123"
      }
    }
    # ☁️ Airflow credentials (webserver/scheduler) and backend Postgres
    airflow = {
      path = "kyuubi/airflow"
      data = {
        postgres_db       = "airflow"
        postgres_user     = "airflow"
        postgres_password = "airflow"
        postgres_host     = "airflow-postgresql"
        postgres_port     = "5432"
        sql_alchemy_conn  = "postgresql+psycopg2://airflow:airflow@airflow-postgresql:5432/airflow"
        fernet_key        = "YlCImzjge_TeZc7jGvKjg8nqxCjFpZDOWl5bpFtXlDA="
      }
    }
    # 📈 Grafana admin credentials
    grafana = {
      path = "kyuubi/grafana"
      data = {
        username = "admin"
        password = "admin123"
      }
    }
  }
  sensitive = true
}

# FluxCD Configuration Variables
variable "enable_fluxcd" {
  description = "Enable FluxCD GitOps"
  type        = bool
  default     = true
}

variable "git_repository_url" {
  description = "Git repository URL for FluxCD"
  type        = string
  default     = ""
}

variable "git_branch" {
  description = "Git branch to monitor"
  type        = string
  default     = "main"
}

variable "git_auth_secret" {
  description = "Name of the Git authentication secret"
  type        = string
  default     = ""
}

variable "git_username" {
  description = "Git username for authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "git_password" {
  description = "Git password/token for authentication"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_image_automation" {
  description = "Enable FluxCD image automation controllers"
  type        = bool
  default     = false
}

# Ingress Configuration Variables
variable "enable_ingress" {
  description = "Enable NGINX Ingress Controller"
  type        = bool
  default     = true
}

variable "enable_vault_ingress" {
  description = "Enable Vault Ingress"
  type        = bool
  default     = true
}

variable "enable_kyuubi_ingress" {
  description = "Enable Kyuubi Ingress"
  type        = bool
  default     = true
}

variable "vault_ingress_host" {
  description = "Hostname for Vault Ingress"
  type        = string
  default     = "vault.local"
}

variable "kyuubi_ingress_host" {
  description = "Hostname for Kyuubi Ingress"
  type        = string
  default     = "kyuubi.local"
}

variable "enable_tls" {
  description = "Enable TLS for Ingress"
  type        = bool
  default     = false
}

variable "tls_secret_name" {
  description = "Name of the TLS secret"
  type        = string
  default     = "tls-secret"
}

variable "tls_cert_data" {
  description = "TLS certificate data (base64 encoded)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tls_key_data" {
  description = "TLS private key data (base64 encoded)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_cert_manager" {
  description = "Enable cert-manager for automatic TLS certificates"
  type        = bool
  default     = false
}

variable "create_self_signed_issuer" {
  description = "Create self-signed ClusterIssuer"
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificates"
  type        = string
  default     = ""
}

# Monitoring
variable "enable_monitoring" {
  description = "Enable monitoring components"
  type        = bool
  default     = false
}

# Kubernetes Configuration Variables
variable "kubernetes_context" {
  description = "Kubernetes context to use for deployment"
  type        = string
  default     = "minikube"
}

variable "kubernetes_config_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "~/.kube/config"
} 