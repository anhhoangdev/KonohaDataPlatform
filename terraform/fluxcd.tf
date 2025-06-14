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
      # Check if FluxCD is already installed
      if ! kubectl get ns flux-system &>/dev/null; then
        echo "Installing FluxCD..."
        flux install \
          --namespace=flux-system \
          --network-policy=false \
          --components-extra=image-reflector-controller,image-automation-controller \
          --force
      else
        echo "FluxCD is already installed"
      fi
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
  create_duration = "120s"  # Increased wait time for CRDs
}

# Verify FluxCD CRDs are available with better error handling
resource "null_resource" "verify_flux_crds" {
  count = var.enable_fluxcd ? 1 : 0
  
  depends_on = [time_sleep.wait_for_flux]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for FluxCD CRDs to be available
      echo "Waiting for FluxCD CRDs to be available..."
      
      # Check each required CRD
      for crd in "gitrepositories.source.toolkit.fluxcd.io" "kustomizations.kustomize.toolkit.fluxcd.io" "helmrepositories.source.toolkit.fluxcd.io" "helmreleases.helm.toolkit.fluxcd.io"; do
        echo "Checking CRD: $crd"
        for i in $(seq 1 60); do
          if kubectl get crd "$crd" >/dev/null 2>&1; then
            echo "CRD $crd is available"
            break
          fi
          if [ $i -eq 60 ]; then
            echo "Timeout waiting for CRD $crd"
            exit 1
          fi
          echo "Waiting for CRD $crd... ($i/60)"
          sleep 5
        done
      done
      
      echo "All FluxCD CRDs are available"
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
        kubectl apply -k infrastructure/apps/flux-system/base/ --timeout=300s || {
          echo "FluxCD system config failed, retrying..."
          sleep 30
          kubectl apply -k infrastructure/apps/flux-system/base/ --timeout=300s
        }
      fi
      
      # Wait for FluxCD controllers to be ready
      echo "Waiting for FluxCD controllers to be ready..."
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=flux -n flux-system --timeout=300s || true
      
      # Apply main applications configuration with proper error handling
      echo "Applying main applications configuration..."
      kubectl apply -k infrastructure/apps/ --timeout=600s || {
        echo "Applications config failed, attempting to resolve conflicts..."
        
        # First try to delete conflicting deployments
        kubectl delete deployment hive-metastore -n kyuubi --ignore-not-found=true
        sleep 10
        
        # Then reapply
        kubectl apply -k infrastructure/apps/ --timeout=600s
      }
      
      echo "GitOps configurations applied successfully"
    EOT
    
    working_dir = ".."  # Go up one level to access infrastructure/apps/
  }

  provisioner "local-exec" {
    when = destroy
    command = <<-EOT
      echo "Cleaning up GitOps configurations..."
      kubectl delete -k infrastructure/apps/ --ignore-not-found=true --timeout=300s || true
      kubectl delete -k infrastructure/apps/flux-system/base/ --ignore-not-found=true --timeout=300s || true
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
  create_duration = "180s"  # Wait for applications to deploy
} 