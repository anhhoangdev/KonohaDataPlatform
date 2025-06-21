#!/bin/bash

set -e

# Configuration
KAFKA_CONNECT_URL="http://localhost:8083"
CONNECTORS_DIR="$(dirname "$0")/../connectors"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Wait for Kafka Connect to be ready
wait_for_kafka_connect() {
    log_info "Waiting for Kafka Connect to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "$KAFKA_CONNECT_URL/connectors" > /dev/null 2>&1; then
            log_info "Kafka Connect is ready!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "Attempt $attempt/$max_attempts - Kafka Connect not ready yet, waiting 10 seconds..."
        sleep 10
    done
    
    log_error "Kafka Connect failed to become ready after $max_attempts attempts"
    return 1
}

# Deploy connector
deploy_connector() {
    local connector_file="$1"
    local connector_name=$(basename "$connector_file" .json)
    
    log_info "Deploying connector: $connector_name"
    
    # Check if connector already exists
    if curl -s -f "$KAFKA_CONNECT_URL/connectors/$connector_name" > /dev/null 2>&1; then
        log_warn "Connector $connector_name already exists, updating..."
        curl -X PUT \
            -H "Content-Type: application/json" \
            -d "@$connector_file" \
            "$KAFKA_CONNECT_URL/connectors/$connector_name/config"
    else
        log_info "Creating new connector $connector_name..."
        curl -X POST \
            -H "Content-Type: application/json" \
            -d "@$connector_file" \
            "$KAFKA_CONNECT_URL/connectors"
    fi
    
    if [ $? -eq 0 ]; then
        log_info "Successfully deployed connector: $connector_name"
    else
        log_error "Failed to deploy connector: $connector_name"
        return 1
    fi
}

# Check connector status
check_connector_status() {
    local connector_name="$1"
    log_info "Checking status of connector: $connector_name"
    
    local status=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector_name/status" | jq -r '.connector.state')
    local tasks=$(curl -s "$KAFKA_CONNECT_URL/connectors/$connector_name/status" | jq -r '.tasks[].state')
    
    echo "Connector State: $status"
    echo "Task States: $tasks"
    
    if [ "$status" = "RUNNING" ]; then
        log_info "Connector $connector_name is running successfully"
    else
        log_error "Connector $connector_name is not running (state: $status)"
    fi
}

# List topics
list_topics() {
    log_info "Listing Kafka topics..."
    kubectl exec -n kafka-platform deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 --list
}

# Show connector logs
show_connector_logs() {
    log_info "Showing Kafka Connect logs..."
    kubectl logs -n kafka-platform deployment/kafka-connect --tail=50
}

# Port forward for local access
setup_port_forwarding() {
    log_info "Setting up port forwarding for local access..."
    
    log_info "Port forwarding Kafka Connect (8083)..."
    kubectl port-forward -n kafka-platform svc/kafka-connect 8083:8083 &
    
    log_info "Port forwarding Schema Registry (8081)..."
    kubectl port-forward -n kafka-platform svc/schema-registry 8081:8081 &
    
    log_info "Port forwarding Kafka (9092)..."
    kubectl port-forward -n kafka-platform svc/kafka 9092:9092 &
    
    log_info "Waiting for port forwarding to be ready..."
    sleep 10
}

# Main execution
main() {
    case "${1:-setup}" in
        "setup")
            setup_port_forwarding
            wait_for_kafka_connect
            
            # Deploy connectors
            deploy_connector "$CONNECTORS_DIR/debezium-postgres-connector.json"
            sleep 5
            # Deploy Avro S3 sink connector
            deploy_connector "$CONNECTORS_DIR/s3-sink-connector.json"
            
            # Remove legacy Iceberg sink connector if present
            if curl -s -f "$KAFKA_CONNECT_URL/connectors/cdc-iceberg-sink" > /dev/null 2>&1; then
                log_warn "Removing legacy cdc-iceberg-sink connector..."
                curl -s -X DELETE "$KAFKA_CONNECT_URL/connectors/cdc-iceberg-sink"
                sleep 3
            fi
            
            # Check status
            sleep 10
            check_connector_status "northwind-postgres-connector"
            check_connector_status "cdc-s3-avro-sink"
            
            list_topics
            ;;
        "status")
            setup_port_forwarding
            wait_for_kafka_connect
            check_connector_status "northwind-postgres-connector"
            check_connector_status "cdc-s3-avro-sink"
            list_topics
            ;;
        "logs")
            show_connector_logs
            ;;
        "port-forward")
            setup_port_forwarding
            log_info "Port forwarding setup complete. Press Ctrl+C to stop."
            wait
            ;;
        *)
            echo "Usage: $0 {setup|status|logs|port-forward}"
            echo "  setup       - Deploy connectors and check status"
            echo "  status      - Check connector status and list topics"
            echo "  logs        - Show Kafka Connect logs"
            echo "  port-forward - Setup port forwarding only"
            exit 1
            ;;
    esac
}

main "$@" 