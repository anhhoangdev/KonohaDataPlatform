# Kafka Connect with Debezium (Postgres CDC) and Schema Registry

This setup provides a complete CDC (Change Data Capture) pipeline from PostgreSQL to S3 via Kafka Connect, with AVRO schema management through Confluent Schema Registry.

## Architecture

```
PostgreSQL (source) 
    ↓ (CDC via Debezium)
Kafka Topics (with AVRO schemas)
    ↓ (S3 Sink Connector)
MinIO/S3 (raw-zone bucket)
```

## Components

- **Zookeeper**: Kafka cluster coordination
- **Kafka**: Message broker
- **Schema Registry**: AVRO schema management
- **Kafka Connect**: Runtime for connectors
  - Debezium PostgreSQL Connector: CDC from Postgres
  - Confluent S3 Sink Connector: Data to S3/MinIO
- **PostgreSQL**: Source database (with Debezium sample data)
- **MinIO**: S3-compatible storage (target)

## Deployment

### 1. Deploy All Components

```bash
# From the infrastructure directory
kubectl apply -k apps/
```

### 2. Wait for Components to Start

```bash
# Check Kafka platform components
kubectl get pods -n kafka-platform

# Check source database
kubectl get pods -n source-data

# Check MinIO
kubectl get pods -n kyuubi
```

Expected output:
```
NAMESPACE        NAME                               READY   STATUS
kafka-platform   zookeeper-xxx                     1/1     Running
kafka-platform   kafka-xxx                         1/1     Running  
kafka-platform   schema-registry-xxx               1/1     Running
kafka-platform   kafka-connect-xxx                 1/1     Running
source-data      postgres-cdc-xxx                  1/1     Running
kyuubi           minio-xxx                         1/1     Running
```

### 3. Setup Connectors

```bash
# Run the setup script
./infrastructure/apps/kafka/scripts/setup-connectors.sh setup
```

This script will:
- Setup port forwarding
- Wait for Kafka Connect to be ready
- Deploy the Debezium PostgreSQL connector
- Deploy the S3 sink connector
- Check connector status
- List Kafka topics

## Testing the CDC Pipeline

### 1. Check Initial Data Capture

After deployment, check that topics are created:
```bash
# List Kafka topics
kubectl exec -n kafka-platform deployment/kafka -- kafka-topics --bootstrap-server localhost:9092 --list
```

You should see topics like:
- `customers` (from inventory.customers)
- `orders` (from inventory.orders)  
- `products` (from inventory.products)

### 2. View Schema Registry

```bash
# Port forward Schema Registry
kubectl port-forward -n kafka-platform svc/schema-registry 8081:8081 &

# Check registered schemas
curl http://localhost:8081/subjects
```

### 3. Test Real-time CDC

Connect to PostgreSQL and make changes:
```bash
# Connect to Postgres
kubectl exec -it -n source-data deployment/postgres-cdc -- psql -U cdc_user -d inventory

# Make some changes
UPDATE inventory.customers SET contact_name = 'John Doe Updated' WHERE customer_id = 1001;
INSERT INTO inventory.products (product_name, unit_price) VALUES ('New Product', 99.99);
DELETE FROM inventory.orders WHERE order_id = 10001;
```

### 4. Verify Data in S3/MinIO

```bash
# Port forward MinIO console  
kubectl port-forward -n kyuubi svc/minio 9001:9001 &

# Open MinIO console: http://localhost:9001
# Login: minioadmin / minioadmin
# Check the 'raw-zone' bucket for new files
```

Or use MinIO CLI:
```bash
# Install mc (MinIO client)
kubectl exec -it -n kyuubi deployment/minio -- mc ls /data/raw-zone/
```

### 5. Monitor Connector Status

```bash
# Check connector status
./infrastructure/apps/kafka/scripts/setup-connectors.sh status

# View Kafka Connect logs
./infrastructure/apps/kafka/scripts/setup-connectors.sh logs
```

## Configuration Details

### Debezium PostgreSQL Connector

- **Source**: `postgres-cdc.source-data.svc.cluster.local:5432`
- **Database**: `inventory`
- **Tables**: `inventory.customers`, `inventory.orders`, `inventory.products`
- **Output Format**: AVRO with Schema Registry
- **Topic Prefix**: `northwind`

### S3 Sink Connector

- **Target**: MinIO at `minio.kyuubi.svc.cluster.local:9000`
- **Bucket**: `raw-zone`
- **Format**: AVRO files
- **Flush Size**: 10 records
- **Rotation**: Every 10 minutes

## Troubleshooting

### Connector Not Starting

```bash
# Check Kafka Connect logs
kubectl logs -n kafka-platform deployment/kafka-connect

# Check connector status via API
curl http://localhost:8083/connectors/northwind-postgres-connector/status
```

### No Data in Topics

```bash
# Check if PostgreSQL is accessible
kubectl exec -n kafka-platform deployment/kafka-connect -- nc -zv postgres-cdc.source-data.svc.cluster.local 5432

# Verify database permissions
kubectl exec -it -n source-data deployment/postgres-cdc -- psql -U cdc_user -d inventory -c "\dt"
```

### Schema Registry Issues

```bash
# Check schema registry connectivity
kubectl exec -n kafka-platform deployment/kafka-connect -- curl -s http://schema-registry:8081/subjects

# View connector configuration
curl http://localhost:8083/connectors/northwind-postgres-connector/config
```

### MinIO/S3 Connection Issues

```bash
# Test MinIO connectivity from Kafka Connect
kubectl exec -n kafka-platform deployment/kafka-connect -- nc -zv minio.kyuubi.svc.cluster.local 9000

# Check MinIO logs
kubectl logs -n kyuubi deployment/minio
```

## Data Flow Verification

1. **PostgreSQL** → Changes made to `inventory.*` tables
2. **Debezium** → Captures changes via logical replication
3. **Kafka Topics** → Stores change events in AVRO format
4. **Schema Registry** → Manages AVRO schemas
5. **S3 Sink** → Writes AVRO files to MinIO/S3

Each step should show data flowing through the pipeline within seconds of making database changes.

## Cleanup

```bash
# Delete connectors
curl -X DELETE http://localhost:8083/connectors/northwind-postgres-connector
curl -X DELETE http://localhost:8083/connectors/cdc-s3-sink

# Delete Kafka components
kubectl delete -k infrastructure/apps/kafka/
``` 