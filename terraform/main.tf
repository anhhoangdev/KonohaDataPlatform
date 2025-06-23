# LocalDataPlatform Terraform Configuration
# This configuration deploys HashiCorp Vault and FluxCD on Kubernetes

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 3.20"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    kustomization = {
      source  = "kbst/kustomization"
      version = "~> 0.9"
    }
  }
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  config_path    = var.kubernetes_config_path
  config_context = var.kubernetes_context
}

# Helm Provider Configuration
provider "helm" {
  kubernetes {
    config_path    = var.kubernetes_config_path
    config_context = var.kubernetes_context
  }
}

# Vault Provider Configuration
provider "vault" {
  address = "http://127.0.0.1:8200"
  token   = var.vault_token == "" ? "root" : var.vault_token
}

# Kubectl provider for applying rendered manifests
provider "kubectl" {
  config_path       = var.kubernetes_config_path
  apply_retry_count = 5
}

# Kustomization provider to render overlays
provider "kustomization" {
  kubeconfig_path = var.kubernetes_config_path
}

# Data sources
data "kubernetes_service_account" "vault" {
  metadata {
    name      = "vault"
    namespace = var.vault_namespace
  }
  depends_on = [kubernetes_service_account.vault]
}

# Local variables
locals {
  vault_namespace        = "vault-system"
  app_namespace          = "kyuubi"
  flux_namespace         = "flux-system"
  ingress_namespace      = "ingress-nginx"
  kafka_platform_namespace = var.kafka_platform_namespace
} 