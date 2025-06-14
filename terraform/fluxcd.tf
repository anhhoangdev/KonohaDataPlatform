# Create FluxCD namespace
resource "kubernetes_namespace" "flux_system" {
  metadata {
    name = local.flux_namespace
    labels = merge(local.common_labels, {
      "name" = local.flux_namespace
    })
  }
}

# Install FluxCD
resource "flux_bootstrap_git" "this" {
  path = var.flux_target_path
  
  depends_on = [kubernetes_namespace.flux_system]
}

# Create Git repository source for FluxCD
resource "kubernetes_manifest" "git_repository" {
  manifest = {
    apiVersion = "source.toolkit.fluxcd.io/v1"
    kind       = "GitRepository"
    metadata = {
      name      = "kyuubi-platform"
      namespace = local.flux_namespace
    }
    spec = {
      interval = "1m"
      ref = {
        branch = var.flux_branch
      }
      url = "https://github.com/${var.github_owner}/${var.github_repository}.git"
      secretRef = {
        name = "github-credentials"
      }
    }
  }
  
  depends_on = [flux_bootstrap_git.this]
}

# GitHub credentials secret for FluxCD
resource "kubernetes_secret" "github_credentials" {
  metadata {
    name      = "github-credentials"
    namespace = local.flux_namespace
  }
  
  data = {
    username = var.github_owner
    password = var.github_token
  }
  
  type = "Opaque"
}

# Kustomization for infrastructure components
resource "kubernetes_manifest" "infrastructure_kustomization" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "infrastructure"
      namespace = local.flux_namespace
    }
    spec = {
      interval = "5m"
      path     = "./infrastructure/apps"
      prune    = true
      sourceRef = {
        kind = "GitRepository"
        name = "kyuubi-platform"
      }
      healthChecks = [
        {
          apiVersion = "apps/v1"
          kind       = "Deployment"
          name       = "mariadb"
          namespace  = "default"
        },
        {
          apiVersion = "apps/v1"
          kind       = "Deployment"
          name       = "hive-metastore"
          namespace  = "default"
        }
      ]
      dependsOn = [
        {
          name = "vault-secrets"
        }
      ]
    }
  }
  
  depends_on = [kubernetes_manifest.git_repository]
}

# Kustomization for Kyuubi applications
resource "kubernetes_manifest" "kyuubi_kustomization" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "kyuubi"
      namespace = local.flux_namespace
    }
    spec = {
      interval = "5m"
      path     = "./infrastructure/apps/kyuubi/overlays/minikube"
      prune    = true
      sourceRef = {
        kind = "GitRepository"
        name = "kyuubi-platform"
      }
      healthChecks = [
        {
          apiVersion = "apps/v1"
          kind       = "Deployment"
          name       = "kyuubi-dbt"
          namespace  = local.namespace
        },
        {
          apiVersion = "apps/v1"
          kind       = "Deployment"
          name       = "kyuubi-dbt-shared"
          namespace  = local.namespace
        }
      ]
      dependsOn = [
        {
          name = "infrastructure"
        }
      ]
    }
  }
  
  depends_on = [kubernetes_manifest.infrastructure_kustomization]
}

# Kustomization for Vault secrets synchronization
resource "kubernetes_manifest" "vault_secrets_kustomization" {
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "vault-secrets"
      namespace = local.flux_namespace
    }
    spec = {
      interval = "10m"
      path     = "./infrastructure/vault-secrets"
      prune    = true
      sourceRef = {
        kind = "GitRepository"
        name = "kyuubi-platform"
      }
      postBuild = {
        substitute = {
          VAULT_ADDR      = "http://vault.${local.vault_namespace}.svc.cluster.local:8200"
          KYUUBI_NAMESPACE = local.namespace
        }
      }
    }
  }
  
  depends_on = [kubernetes_manifest.git_repository]
}

# Monitoring kustomization (if enabled)
resource "kubernetes_manifest" "monitoring_kustomization" {
  count = var.enable_monitoring ? 1 : 0
  
  manifest = {
    apiVersion = "kustomize.toolkit.fluxcd.io/v1"
    kind       = "Kustomization"
    metadata = {
      name      = "monitoring"
      namespace = local.flux_namespace
    }
    spec = {
      interval = "5m"
      path     = "./infrastructure/monitoring"
      prune    = true
      sourceRef = {
        kind = "GitRepository"
        name = "kyuubi-platform"
      }
      healthChecks = [
        {
          apiVersion = "apps/v1"
          kind       = "Deployment"
          name       = "prometheus-server"
          namespace  = "monitoring"
        },
        {
          apiVersion = "apps/v1"
          kind       = "Deployment"
          name       = "grafana"
          namespace  = "monitoring"
        }
      ]
      dependsOn = [
        {
          name = "vault-secrets"
        }
      ]
    }
  }
  
  depends_on = [kubernetes_manifest.vault_secrets_kustomization]
}

# FluxCD notification for Slack/Discord (optional)
resource "kubernetes_manifest" "notification_provider" {
  count = var.enable_monitoring ? 1 : 0
  
  manifest = {
    apiVersion = "notification.toolkit.fluxcd.io/v1beta1"
    kind       = "Provider"
    metadata = {
      name      = "slack"
      namespace = local.flux_namespace
    }
    spec = {
      type    = "slack"
      channel = "kyuubi-alerts"
      secretRef = {
        name = "slack-webhook"
      }
    }
  }
  
  depends_on = [flux_bootstrap_git.this]
}

# FluxCD alert for deployment failures
resource "kubernetes_manifest" "deployment_alert" {
  count = var.enable_monitoring ? 1 : 0
  
  manifest = {
    apiVersion = "notification.toolkit.fluxcd.io/v1beta1"
    kind       = "Alert"
    metadata = {
      name      = "kyuubi-deployment-alert"
      namespace = local.flux_namespace
    }
    spec = {
      providerRef = {
        name = "slack"
      }
      eventSeverity = "error"
      eventSources = [
        {
          kind      = "Kustomization"
          name      = "*"
          namespace = local.flux_namespace
        }
      ]
      summary = "Kyuubi Platform deployment failed"
    }
  }
  
  depends_on = [kubernetes_manifest.notification_provider[0]]
} 