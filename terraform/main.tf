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
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
}

# Local variables
locals {
  cluster_name = "kyuubi-local"
  namespace    = "kyuubi"
  
  # Vault configuration
  vault_namespace = "vault-system"
  vault_release   = "vault"
  
  # FluxCD configuration
  flux_namespace = "flux-system"
  
  # Common labels
  common_labels = {
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "kyuubi-platform"
  }
}

# Kubernetes provider configuration
provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Helm provider configuration
provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

# Vault provider configuration (will be configured after Vault is deployed)
provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

# GitHub provider for FluxCD
provider "github" {
  token = var.github_token
  owner = var.github_owner
}

# FluxCD provider
provider "flux" {
  kubernetes = {
    config_path = "~/.kube/config"
  }
  git = {
    url = "https://github.com/${var.github_owner}/${var.github_repository}.git"
    http = {
      username = var.github_owner
      password = var.github_token
    }
  }
} 