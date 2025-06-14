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
    time_sleep.wait_for_vault
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
  kubernetes_ca_cert   = <<-EOT
    -----BEGIN CERTIFICATE-----
    MIIDBjCCAe6gAwIBAgIBATANBgkqhkiG9w0BAQsFADAVMRMwEQYDVQQDEwptaW5p
    a3ViZUNBMB4XDTI1MDMyODA3MjQ0OVoXDTM1MDMyNzA3MjQ0OVowFTETMBEGA1UE
    AxMKbWluaWt1YmVDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMZx
    1rTY5FUSu/VbLTychy0jOoACetNKlKQCfa706TWDH5uSZh73yiLLjQPvTQJLuMA6
    LUVlFPPag1Tv54hFAlHg5E2PgYETsP2qA3KyB0DXiaL+/GHKMw0t0z6XByZAjS+1
    fv/7lx45uU/1k4Sq532fxptwp0nHhKZJU++IqADCZfnpv3FwVFZudKmSKhLht6ZK
    WSxkWEUKe02u5QAB7hEGBbCSL70BnQMN75dyAz/cDBsQF3pss3SB1JasXEpUM2cZ
    15cojfv5nw9m6JaEfPAj4kCAByc3ezr5vzqZZN6PNAJ26OIaP38mLuQ3Y3o26qkb
    1CNid84AeHf6Q4anjNcCAwEAAaNhMF8wDgYDVR0PAQH/BAQDAgKkMB0GA1UdJQQW
    MBQGCCsGAQUFBwMCBggrBgEFBQcDATAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQW
    BBQcscw2ypwP6BfkHAinWN48y79BtTANBgkqhkiG9w0BAQsFAAOCAQEAgucu69qG
    /RvApj329k4svpgDcVKymsUQiNWuZU3HsYC7DCn4Q8OpSsjvWVqCNvLdCUzXvCcr
    jG51msHWddrNCiBZ1LJsVrbjeExQWzpFHeDic3z7S1ZNZ/CbmgFFJZZwRSjwrFWa
    z8xlUda/fi0Xqnhhup9RHYog6hW9ZEW935ta8PACEoNN0YNQOgsTdYAVSOGKkSkY
    gzESFiLRjoQurqqhvRbVUXx7S9TOB2z7iWRMTdQAlNdQnBnomc2QUIAuUx5o2DcG
    scS0tvDzi7BBUdmqvv7b9BgWm9JbCtcfHm077e26W7+07VcOWUgFt8/2goc7sVJm
    DI8CMvYs4R3meg==
    -----END CERTIFICATE-----
  EOT
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

# Create secrets in Vault
resource "vault_kv_secret_v2" "kyuubi_secrets" {
  depends_on = [vault_mount.kyuubi_kv]
  
  for_each = local.kyuubi_secrets_map
  
  mount = vault_mount.kyuubi_kv.path
  name  = each.value.path
  
  data_json = jsonencode(each.value.data)
} 