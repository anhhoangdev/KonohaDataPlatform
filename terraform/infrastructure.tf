# Phase 1: Basic Infrastructure
# This file contains the basic Kubernetes resources that need to be deployed first

# Create namespaces
resource "kubernetes_namespace" "vault" {
  metadata {
    name = var.vault_namespace
    labels = {
      "app.kubernetes.io/name"       = "vault"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "kubernetes_namespace" "kyuubi" {
  metadata {
    name = var.kyuubi_namespace
    labels = {
      "app.kubernetes.io/name"       = "kyuubi"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Kafka platform namespace (for brokers, connect, akhq)
resource "kubernetes_namespace" "kafka_platform" {
  metadata {
    name = var.kafka_platform_namespace
    labels = {
      "app.kubernetes.io/name"       = "kafka"
      "app.kubernetes.io/component"  = "streaming"
      "app.kubernetes.io/part-of"    = "data-platform"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Source-data namespace (upstream Postgres or other systems)
resource "kubernetes_namespace" "source_data" {
  metadata {
    name = "source-data"
    labels = {
      "app.kubernetes.io/name"       = "source-data"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Create service accounts
resource "kubernetes_service_account" "vault" {
  metadata {
    name      = "vault"
    namespace = kubernetes_namespace.vault.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "vault"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  
  automount_service_account_token = true
}

resource "kubernetes_service_account" "kyuubi" {
  metadata {
    name      = "kyuubi"
    namespace = kubernetes_namespace.kyuubi.metadata[0].name
    annotations = {
      "vault.hashicorp.com/agent-inject"               = "true"
      "vault.hashicorp.com/role"                       = "kyuubi"
      "vault.hashicorp.com/agent-inject-secret-config" = "kyuubi/data/config"
    }
    labels = {
      "app.kubernetes.io/name"       = "kyuubi"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  
  automount_service_account_token = true
}

resource "kubernetes_service_account" "kyuubi_dbt" {
  metadata {
    name      = "kyuubi-dbt"
    namespace = kubernetes_namespace.kyuubi.metadata[0].name
    annotations = {
      "vault.hashicorp.com/agent-inject"               = "true"
      "vault.hashicorp.com/role"                       = "kyuubi"
      "vault.hashicorp.com/agent-inject-secret-config" = "kyuubi/data/dbt"
    }
    labels = {
      "app.kubernetes.io/name"       = "kyuubi-dbt"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  
  automount_service_account_token = true
}

resource "kubernetes_service_account" "kyuubi_dbt_shared" {
  metadata {
    name      = "kyuubi-dbt-shared"
    namespace = kubernetes_namespace.kyuubi.metadata[0].name
    annotations = {
      "vault.hashicorp.com/agent-inject"               = "true"
      "vault.hashicorp.com/role"                       = "kyuubi"
      "vault.hashicorp.com/agent-inject-secret-config" = "kyuubi/data/dbt-shared"
    }
    labels = {
      "app.kubernetes.io/name"       = "kyuubi-dbt-shared"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  
  automount_service_account_token = true
}

# Create Vault authentication secret
resource "kubernetes_secret" "vault_auth" {
  metadata {
    name      = "vault-auth"
    namespace = kubernetes_namespace.vault.metadata[0].name
    labels = {
      "app.kubernetes.io/name"       = "vault-auth"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  
  type = "Opaque"
  
  data = {
    token = var.vault_token
  }
} 