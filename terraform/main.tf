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
  }
}

# Kubernetes Provider Configuration
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "minikube"
}

# Helm Provider Configuration
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}

# Vault Provider Configuration
provider "vault" {
  address = var.vault_address
  token   = var.vault_token
  
  # Skip TLS verification for development
  skip_tls_verify = true
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
  vault_namespace   = "vault-system"
  app_namespace     = "kyuubi"
  flux_namespace    = "flux-system"
  ingress_namespace = "ingress-nginx"
} 