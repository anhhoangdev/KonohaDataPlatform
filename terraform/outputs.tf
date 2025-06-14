output "vault_namespace" {
  description = "Namespace where Vault is deployed"
  value       = kubernetes_namespace.vault.metadata[0].name
}

output "vault_service_name" {
  description = "Vault service name"
  value       = "vault"
}

output "vault_ui_url" {
  description = "Vault UI URL (requires port-forward)"
  value       = "http://localhost:8200"
}

output "vault_address" {
  description = "Vault server address"
  value       = var.vault_address
}

output "vault_dev_mode" {
  description = "Whether Vault is running in development mode"
  value       = var.vault_dev_mode
}

output "vault_root_token" {
  description = "Vault root token (dev mode only)"
  value       = var.vault_dev_mode ? "root" : "Check Kubernetes secret 'vault-keys' in vault-system namespace"
  sensitive   = true
}

output "kyuubi_namespace" {
  description = "Namespace where Kyuubi applications are deployed"
  value       = kubernetes_namespace.kyuubi.metadata[0].name
}

output "vault_auth_method" {
  description = "Vault authentication method for Kubernetes"
  value       = vault_auth_backend.kubernetes.path
}

output "vault_kyuubi_role" {
  description = "Vault role for Kyuubi applications"
  value       = vault_kubernetes_auth_backend_role.kyuubi.role_name
}

output "vault_secrets_mount" {
  description = "Vault secrets mount path"
  value       = vault_mount.kyuubi_kv.path
}

output "created_secrets" {
  description = "List of secrets created in Vault"
  value       = var.create_vault_secrets ? [for k, v in var.kyuubi_secrets : v.path] : []
  sensitive   = true
}

output "service_accounts" {
  description = "Service accounts created for Vault authentication"
  value = [
    kubernetes_service_account.kyuubi.metadata[0].name,
    kubernetes_service_account.kyuubi_dbt.metadata[0].name,
    kubernetes_service_account.kyuubi_dbt_shared.metadata[0].name
  ]
}

output "port_forward_commands" {
  description = "Commands to set up port forwarding"
  value = {
    vault_ui = "kubectl port-forward -n ${kubernetes_namespace.vault.metadata[0].name} svc/vault 8200:8200"
    vault_api = "kubectl port-forward -n ${kubernetes_namespace.vault.metadata[0].name} svc/vault 8200:8200"
  }
}

output "useful_commands" {
  description = "Useful commands for managing Vault"
  value = {
    vault_status     = "vault status"
    vault_auth_list  = "vault auth list"
    vault_policy_list = "vault policy list"
    vault_secrets_list = "vault kv list kyuubi/"
    get_vault_logs   = "kubectl logs -n ${kubernetes_namespace.vault.metadata[0].name} -l app.kubernetes.io/name=vault"
    get_vault_pods   = "kubectl get pods -n ${kubernetes_namespace.vault.metadata[0].name}"
  }
}

output "environment_setup" {
  description = "Environment variables to set for Vault CLI"
  value = {
    VAULT_ADDR  = var.vault_address
    VAULT_TOKEN = var.vault_dev_mode ? "root" : "export VAULT_TOKEN=$(kubectl get secret vault-keys -n ${kubernetes_namespace.vault.metadata[0].name} -o jsonpath='{.data.root-token}' | base64 -d)"
  }
} 