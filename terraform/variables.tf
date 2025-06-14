variable "github_token" {
  description = "GitHub personal access token for FluxCD"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub owner/organization name"
  type        = string
  default     = "your-github-username"
}

variable "github_repository" {
  description = "GitHub repository name for GitOps"
  type        = string
  default     = "LocalDataPlatform"
}

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://localhost:8200"
}

variable "vault_token" {
  description = "Vault root token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "minikube_cpus" {
  description = "Number of CPUs for Minikube"
  type        = number
  default     = 12
}

variable "minikube_memory" {
  description = "Memory allocation for Minikube in MB"
  type        = number
  default     = 24576
}

variable "minikube_disk_size" {
  description = "Disk size for Minikube"
  type        = string
  default     = "50g"
}

variable "kyuubi_image_tag" {
  description = "Kyuubi server image tag"
  type        = string
  default     = "1.10.0"
}

variable "spark_image_tag" {
  description = "Spark engine image tag"
  type        = string
  default     = "1.5.0"
}

variable "hive_metastore_image_tag" {
  description = "Hive Metastore image tag"
  type        = string
  default     = "3.1.3"
}

variable "enable_vault_ui" {
  description = "Enable Vault UI"
  type        = bool
  default     = true
}

variable "vault_dev_mode" {
  description = "Run Vault in development mode"
  type        = bool
  default     = true
}

variable "flux_target_path" {
  description = "Path in Git repository for FluxCD to sync"
  type        = string
  default     = "./infrastructure"
}

variable "flux_branch" {
  description = "Git branch for FluxCD to sync"
  type        = string
  default     = "main"
}

variable "enable_monitoring" {
  description = "Enable Prometheus and Grafana monitoring"
  type        = bool
  default     = false
}

variable "kyuubi_user_timeout" {
  description = "Timeout for USER-level Kyuubi sessions"
  type        = string
  default     = "PT30S"
}

variable "kyuubi_server_timeout" {
  description = "Timeout for SERVER-level Kyuubi sessions"
  type        = string
  default     = "PT15M"
}

variable "spark_executor_memory" {
  description = "Memory allocation for Spark executors"
  type        = string
  default     = "12g"
}

variable "spark_executor_cores" {
  description = "CPU cores for Spark executors"
  type        = number
  default     = 2
}

variable "spark_max_executors" {
  description = "Maximum number of Spark executors"
  type        = number
  default     = 9
} 