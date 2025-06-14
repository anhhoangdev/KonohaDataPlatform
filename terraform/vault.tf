# Create Vault namespace
resource "kubernetes_namespace" "vault" {
  metadata {
    name = local.vault_namespace
    labels = merge(local.common_labels, {
      "name" = local.vault_namespace
    })
  }
}

# Deploy Vault using Helm
resource "helm_release" "vault" {
  name       = local.vault_release
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = "0.25.0"
  namespace  = kubernetes_namespace.vault.metadata[0].name

  values = [
    yamlencode({
      global = {
        enabled = true
      }
      
      server = {
        dev = {
          enabled = var.vault_dev_mode
        }
        
        standalone = {
          enabled = !var.vault_dev_mode
          config = <<-EOT
            ui = true
            
            listener "tcp" {
              tls_disable = 1
              address = "[::]:8200"
              cluster_address = "[::]:8201"
            }
            
            storage "file" {
              path = "/vault/data"
            }
          EOT
        }
        
        service = {
          enabled = true
          type = "ClusterIP"
          port = 8200
        }
        
        resources = {
          requests = {
            memory = "256Mi"
            cpu = "250m"
          }
          limits = {
            memory = "512Mi"
            cpu = "500m"
          }
        }
        
        extraEnvironmentVars = {
          VAULT_CACERT = "/vault/userconfig/vault-tls/ca.crt"
        }
      }
      
      ui = {
        enabled = var.enable_vault_ui
        serviceType = "ClusterIP"
      }
      
      injector = {
        enabled = true
        resources = {
          requests = {
            memory = "50Mi"
            cpu = "50m"
          }
          limits = {
            memory = "256Mi"
            cpu = "250m"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.vault]
}

# Wait for Vault to be ready
resource "kubernetes_job" "vault_init" {
  count = var.vault_dev_mode ? 0 : 1
  
  metadata {
    name      = "vault-init"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
  
  spec {
    template {
      metadata {}
      spec {
        restart_policy = "Never"
        
        container {
          name  = "vault-init"
          image = "vault:1.15.0"
          
          command = ["/bin/sh"]
          args = [
            "-c",
            <<-EOT
              # Wait for Vault to be ready
              until vault status; do
                echo "Waiting for Vault to be ready..."
                sleep 5
              done
              
              # Initialize Vault if not already initialized
              if ! vault status | grep -q "Initialized.*true"; then
                vault operator init -key-shares=1 -key-threshold=1 -format=json > /tmp/vault-keys.json
                UNSEAL_KEY=$(cat /tmp/vault-keys.json | jq -r '.unseal_keys_b64[0]')
                ROOT_TOKEN=$(cat /tmp/vault-keys.json | jq -r '.root_token')
                
                # Unseal Vault
                vault operator unseal $UNSEAL_KEY
                
                # Store keys in Kubernetes secrets
                kubectl create secret generic vault-keys \
                  --from-literal=unseal-key=$UNSEAL_KEY \
                  --from-literal=root-token=$ROOT_TOKEN \
                  -n ${kubernetes_namespace.vault.metadata[0].name}
              fi
            EOT
          ]
          
          env {
            name  = "VAULT_ADDR"
            value = "http://vault:8200"
          }
        }
        
        service_account_name = kubernetes_service_account.vault_init.metadata[0].name
      }
    }
  }
  
  depends_on = [helm_release.vault]
}

# Service account for Vault initialization
resource "kubernetes_service_account" "vault_init" {
  metadata {
    name      = "vault-init"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
}

# ClusterRole for Vault initialization
resource "kubernetes_cluster_role" "vault_init" {
  metadata {
    name = "vault-init"
  }
  
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "get", "list", "update", "patch"]
  }
}

# ClusterRoleBinding for Vault initialization
resource "kubernetes_cluster_role_binding" "vault_init" {
  metadata {
    name = "vault-init"
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.vault_init.metadata[0].name
  }
  
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_init.metadata[0].name
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
}

# Vault port forwarding service (for local access)
resource "kubernetes_service" "vault_external" {
  metadata {
    name      = "vault-external"
    namespace = kubernetes_namespace.vault.metadata[0].name
  }
  
  spec {
    selector = {
      "app.kubernetes.io/name"     = "vault"
      "app.kubernetes.io/instance" = local.vault_release
    }
    
    port {
      name        = "http"
      port        = 8200
      target_port = 8200
      protocol    = "TCP"
    }
    
    type = "NodePort"
  }
  
  depends_on = [helm_release.vault]
} 