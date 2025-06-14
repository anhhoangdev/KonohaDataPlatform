# Phase 2: Vault Deployment
# This file deploys HashiCorp Vault using Helm

# Deploy Vault using Helm
resource "helm_release" "vault" {
  name       = "vault"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.27.0"
  namespace  = var.vault_namespace

  values = [
    yamlencode({
      global = {
        enabled = true
      }
      
      server = {
        enabled = true
        image = {
          repository = "hashicorp/vault"
          tag        = "1.15.4"
          pullPolicy = "IfNotPresent"
        }
        
        logLevel = var.vault_log_level
        
        resources = {
          requests = {
            memory = "256Mi"
            cpu    = "250m"
          }
          limits = {
            memory = "512Mi"
            cpu    = "500m"
          }
        }
        
        readinessProbe = {
          enabled = true
          path    = "/v1/sys/health?standbyok=true&sealedcode=204&uninitcode=204"
        }
        
        livenessProbe = {
          enabled = true
          path    = "/v1/sys/health?standbyok=true"
        }
        
        # Development mode configuration
        dev = {
          enabled = var.vault_dev_mode
          devRootToken = var.vault_dev_mode ? "root" : null
        }
        
        # High availability configuration (disabled for minikube)
        ha = {
          enabled = false
        }
        
        # Standalone configuration for minikube
        standalone = {
          enabled = !var.vault_dev_mode
          config = var.vault_dev_mode ? null : <<-EOF
            ui = ${var.vault_ui_enabled}
            
            listener "tcp" {
              tls_disable = 1
              address = "[::]:8200"
              cluster_address = "[::]:8201"
            }
            
            storage "file" {
              path = "/vault/data"
            }
            
            # Example configuration for auto-unseal (disabled by default)
            # seal "transit" {
            #   address = "https://vault.example.com:8200"
            #   token = "s.Qf1s5zigZ4OX6akYjQXJC1jY"
            #   disable_renewal = "false"
            #   key_name = "autounseal"
            #   mount_path = "transit/"
            # }
          EOF
        }
        
        # Data storage
        dataStorage = {
          enabled      = !var.vault_dev_mode
          size         = var.vault_storage_size
          mountPath    = "/vault/data"
          storageClass = null
          accessMode   = "ReadWriteOnce"
        }
        
        # Audit storage
        auditStorage = {
          enabled      = !var.vault_dev_mode
          size         = "10Gi"
          mountPath    = "/vault/audit"
          storageClass = null
          accessMode   = "ReadWriteOnce"
        }
        
        # Service account
        serviceAccount = {
          create = false
          name   = "vault"  # Reference the service account created in infrastructure.tf
        }
        
        # Ingress (disabled for minikube, we'll use port-forward)
        ingress = {
          enabled = false
        }
      }
      
      # UI configuration
      ui = {
        enabled         = var.vault_ui_enabled
        serviceType     = "ClusterIP"
        serviceNodePort = null
        externalPort    = 8200
      }
      
      # CSI Provider (disabled for simplicity)
      csi = {
        enabled = false
      }
      
      # Injector (Vault Agent Injector)
      injector = {
        enabled = true
        image = {
          repository = "hashicorp/vault-k8s"
          tag        = "1.4.0"
          pullPolicy = "IfNotPresent"
        }
        
        resources = {
          requests = {
            memory = "256Mi"
            cpu    = "250m"
          }
          limits = {
            memory = "512Mi"
            cpu    = "500m"
          }
        }
        
        # Webhook failure policy
        failurePolicy = "Ignore"
        
        # Service account for injector
        serviceAccount = {
          create = true
          name   = "vault-agent-injector"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.vault,
    kubernetes_service_account.vault
  ]
}

# Wait for Vault to be ready
resource "time_sleep" "wait_for_vault" {
  depends_on = [helm_release.vault]
  create_duration = "60s"
}

# Deploy Vault Secrets Operator using Helm
resource "helm_release" "vault_secrets_operator" {
  count = var.enable_vault_secrets_operator ? 1 : 0
  
  name       = "vault-secrets-operator"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault-secrets-operator"
  version    = "0.4.3"
  namespace  = "vault-secrets-operator-system"
  create_namespace = true

  values = [
    yamlencode({
      defaultVaultConnection = {
        enabled = true
        address = "http://vault.${var.vault_namespace}:8200"
        skipTLSVerify = true
      }
      
      controller = {
        manager = {
          resources = {
            limits = {
              cpu = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu = "100m"
              memory = "128Mi"
            }
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.vault,
    time_sleep.wait_for_vault
  ]
}

# Wait for Vault Secrets Operator to be ready
resource "time_sleep" "wait_for_vault_secrets_operator" {
  count = var.enable_vault_secrets_operator ? 1 : 0
  depends_on = [helm_release.vault_secrets_operator]
  create_duration = "30s"
} 