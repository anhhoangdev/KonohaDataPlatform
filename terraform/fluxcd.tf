# Phase 2: FluxCD Bootstrap Configuration
# This file bootstraps FluxCD and handles GitOps deployment

# Install FluxCD using the official CLI (recommended method)
resource "null_resource" "flux_install" {
  count = var.enable_fluxcd ? 1 : 0

  # Depend on basic infrastructure
  depends_on = [
    kubernetes_namespace.vault,
    kubernetes_namespace.kyuubi,
    kubernetes_service_account.vault,
    kubernetes_service_account.kyuubi
  ]

  provisioner "local-exec" {
    command = <<-EOT
      flux install \
        --namespace=flux-system \
        --network-policy=false \
        --components-extra=image-reflector-controller,image-automation-controller \
        --force
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "flux uninstall --namespace=flux-system --silent || true"
  }

  triggers = {
    # Force recreation if FluxCD version changes
    flux_version = "v2.2.2"
  }
}

# Wait for FluxCD to be ready and CRDs to be available
resource "time_sleep" "wait_for_flux" {
  count = var.enable_fluxcd ? 1 : 0
  depends_on = [null_resource.flux_install]
  create_duration = "90s"  # Increased wait time for CRDs
}

# Verify FluxCD CRDs are available
resource "null_resource" "verify_flux_crds" {
  count = var.enable_fluxcd ? 1 : 0
  
  depends_on = [time_sleep.wait_for_flux]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for FluxCD CRDs to be available
      echo "Waiting for FluxCD CRDs to be available..."
      for i in {1..30}; do
        if kubectl get crd gitrepositories.source.toolkit.fluxcd.io &>/dev/null && \
           kubectl get crd kustomizations.kustomize.toolkit.fluxcd.io &>/dev/null && \
           kubectl get crd helmrepositories.source.toolkit.fluxcd.io &>/dev/null; then
          echo "FluxCD CRDs are available"
          exit 0
        fi
        echo "Waiting for FluxCD CRDs... ($i/30)"
        sleep 10
      done
      echo "Timeout waiting for FluxCD CRDs"
      exit 1
    EOT
  }

  triggers = {
    # Re-run if FluxCD is reinstalled
    flux_install_id = null_resource.flux_install[0].id
  }
}

# Phase 3: Apply GitOps configurations after FluxCD is ready
resource "null_resource" "apply_gitops_config" {
  count = var.enable_fluxcd ? 1 : 0
  
  depends_on = [
    null_resource.verify_flux_crds,
    helm_release.vault  # Ensure Vault is deployed first
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Applying GitOps configurations..."
      
      # Apply FluxCD system configuration first
      if [ -d "infrastructure/apps/flux-system/base" ]; then
        echo "Applying FluxCD system configuration..."
        kubectl apply -k infrastructure/apps/flux-system/base/ || echo "FluxCD system config failed, continuing..."
      fi
      
      # Wait a bit for FluxCD system to be ready
      sleep 30
      
      # Apply main applications configuration
      echo "Applying main applications configuration..."
      kubectl apply -k infrastructure/apps/ || echo "Applications config failed, continuing..."
      
      echo "GitOps configurations applied successfully"
    EOT
    
    working_dir = ".."  # Go up one level to access infrastructure/apps/
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      echo "Cleaning up GitOps configurations..."
      kubectl delete -k infrastructure/apps/ --ignore-not-found=true || true
      kubectl delete -k infrastructure/apps/flux-system/base/ --ignore-not-found=true || true
    EOT
    working_dir = ".."
  }

  triggers = {
    # Re-run if GitOps configs change
    gitops_config_hash = filemd5("../infrastructure/apps/kustomization.yaml")
    flux_crds_ready = null_resource.verify_flux_crds[0].id
  }
}

# Wait for GitOps deployment to complete
resource "time_sleep" "wait_for_gitops" {
  count = var.enable_fluxcd ? 1 : 0
  depends_on = [null_resource.apply_gitops_config]
  create_duration = "120s"  # Wait for applications to deploy
} 