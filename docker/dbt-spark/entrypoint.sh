#!/bin/bash
set -e

# Set default values for environment variables
export AWS_ENDPOINT_URL=${AWS_ENDPOINT_URL:-"http://minio:9000"}
export AWS_S3_ALLOW_UNSAFE_RENAME=${AWS_S3_ALLOW_UNSAFE_RENAME:-"true"}
export DBT_PROFILES_DIR=${DBT_PROFILES_DIR:-"/tmp/dbt_profiles"}

# Ensure profiles directory exists
mkdir -p $DBT_PROFILES_DIR

# If no profiles.yml exists, create a default one
if [ ! -f "$DBT_PROFILES_DIR/profiles.yml" ]; then
    echo "Creating default DBT profiles.yml"
    cat > $DBT_PROFILES_DIR/profiles.yml << EOF
config:
  send_anonymous_usage_stats: false

dbt_spark:
  target: dev
  outputs:
    dev:
      type: spark
      method: thrift
      host: kyuubi-dbt.kyuubi.svc.cluster.local
      port: 10009
      user: dbt
      schema: default
      connect_retries: 3
      connect_timeout: 60
      retry_all: true
      auth: null
      queue: default
EOF
fi

echo "DBT Spark container starting..."
echo "Working directory: $(pwd)"
echo "DBT profiles directory: $DBT_PROFILES_DIR"
echo "Available files:"
ls -la

# Print environment for debugging
echo "Environment variables:"
echo "  JAVA_HOME: $JAVA_HOME"
echo "  SPARK_HOME: $SPARK_HOME"
echo "  AWS_ENDPOINT_URL: $AWS_ENDPOINT_URL"
echo "  DBT_PROFILES_DIR: $DBT_PROFILES_DIR"

# Execute the command passed to the container
if [ "$1" = "dbt" ]; then
    echo "Running DBT command: $@"
    exec "$@"
else
    # If not a dbt command, run it as is
    exec "$@"
fi 