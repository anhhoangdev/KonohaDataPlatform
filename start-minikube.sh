#!/bin/bash

# start-minikube.sh — quick helper to spin-up the LocalDataPlatform Minikube cluster
# ----------------------------------------------------------------------------------
# This script ONLY provisions the Minikube cluster with the recommended resources
# and required addons. All application deployment is handled separately by
# deploy-vault.sh (full end-to-end).  
#
# Usage:
#   ./start-minikube.sh          # start (default)
#   ./start-minikube.sh stop     # stop cluster
#   ./start-minikube.sh delete   # delete cluster
#   ./start-minikube.sh status   # show status

set -e

# Config — adjust to your machine
MINIKUBE_CPUS=${MINIKUBE_CPUS:-16}
MINIKUBE_MEMORY=${MINIKUBE_MEMORY:-32768}   # MiB
MINIKUBE_DISK=${MINIKUBE_DISK:-50g}

# Colours
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }

check_prereqs() {
  for t in minikube kubectl docker; do
    command -v "$t" &>/dev/null || { error "$t not installed"; exit 1; }
  done
}

start_cluster() {
  info "Starting Minikube with ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_MEMORY}MB RAM, ${MINIKUBE_DISK} disk…"
  if minikube status &>/dev/null; then
    warning "Minikube already running — skipping start"
  else
    minikube start \
      --cpus=${MINIKUBE_CPUS} \
      --memory=${MINIKUBE_MEMORY} \
      --disk-size=${MINIKUBE_DISK} \
      --driver=docker
    # Enable addons we rely on
    info "Enabling ingress and metrics-server addons…"
    minikube addons enable ingress
    minikube addons enable metrics-server
    success "Minikube cluster is ready"
  fi
}

case "${1:-start}" in
  start)
    check_prereqs
    start_cluster
    ;;
  stop)
    info "Stopping Minikube…"
    minikube stop && success "Stopped"
    ;;
  delete)
    info "Deleting Minikube…"
    minikube delete && success "Deleted"
    ;;
  status)
    minikube status || true
    ;;
  *)
    echo "Usage: $0 [start|stop|delete|status]" ; exit 1 ;;
esac 