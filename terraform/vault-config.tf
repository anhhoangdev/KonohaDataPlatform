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
  depends_on = [
    helm_release.vault,
    time_sleep.wait_for_vault,
    helm_release.vault_secrets_operator,
    time_sleep.wait_for_vault_secrets_operator
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for Vault API to be accessible..."
      
      # Start port forwarding in background
      kubectl port-forward -n ${var.vault_namespace} svc/vault 8200:8200 > /dev/null 2>&1 &
      PORT_FORWARD_PID=$!
      
      # Wait for Vault to be ready
      for i in {1..60}; do
        if curl -s http://localhost:8200/v1/sys/health > /dev/null 2>&1; then
          echo "Vault API is accessible"
          break
        fi
        echo "Waiting for Vault API... ($i/60)"
        sleep 5
      done
      
      # Test with vault CLI
      export VAULT_ADDR=http://localhost:8200
      export VAULT_TOKEN=root
      
      if vault status > /dev/null 2>&1; then
        echo "Vault is ready for configuration"
      else
        echo "Vault is not ready, but continuing..."
      fi
      
      # Wait for Vault Secrets Operator to be ready
      if [ "${var.enable_vault_secrets_operator}" = "true" ]; then
        echo "Waiting for Vault Secrets Operator to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault-secrets-operator \
          -n vault-secrets-operator-system --timeout=30 || echo "VSO not ready yet"
        echo "Vault Secrets Operator is ready"
      fi
    EOT
  }
}

# Vault KV mount for Kyuubi secrets
resource "vault_mount" "kyuubi_kv" {
  depends_on = [null_resource.wait_for_vault_api]
  
  path        = "kyuubi"
  type        = "kv-v2"
  description = "KV store for Kyuubi application secrets"
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

# Create secrets in Vault
resource "vault_kv_secret_v2" "kyuubi_secrets" {
  depends_on = [vault_mount.kyuubi_kv]
  
  for_each = local.kyuubi_secrets_map
  
  mount = vault_mount.kyuubi_kv.path
  name  = each.value.path
  
  data_json = jsonencode(each.value.data)
} 