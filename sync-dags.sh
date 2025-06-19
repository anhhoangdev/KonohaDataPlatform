#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

HOST_DAGS_PATH="/mnt/dag"
LOCAL_DAG_PATH="./dag"

echo -e "${YELLOW}🔄 Syncing DAGs to HostPath Volume...${NC}"

# This command must be run on the Minikube host machine
# You can use 'minikube ssh' to get into the machine if needed.
echo -e "${YELLOW}  Creating directory on Minikube host: ${HOST_DAGS_PATH}${NC}"
minikube ssh -- "sudo mkdir -p ${HOST_DAGS_PATH} && sudo chmod -R 777 ${HOST_DAGS_PATH}"

echo -e "${YELLOW}  Copying local DAGs from ${LOCAL_DAG_PATH} to Minikube at ${HOST_DAGS_PATH}${NC}"
minikube cp "${LOCAL_DAG_PATH}" "/mnt/"

echo -e "${GREEN}✅ DAGs synced successfully to the persistent volume!${NC}"
echo -e "${YELLOW}  The Airflow scheduler should pick up the changes automatically.${NC}"
