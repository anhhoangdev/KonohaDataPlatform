#!/bin/bash
set -e

echo "🚀 Starting Kyuubi Server..."

# Set default values if not provided
export KYUUBI_HOME=${KYUUBI_HOME:-/opt/kyuubi}
export SPARK_HOME=${SPARK_HOME:-/opt/spark}
export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-8-openjdk-amd64}

# When a full kyuubi-defaults.conf is already mounted (e.g. via ConfigMap),
# honour it and skip the in-container generation step. Avoids read-only mount errors.
CONF_FILE="${KYUUBI_HOME:-/opt/kyuubi}/conf/kyuubi-defaults.conf"

echo "📄 Using pre-mounted kyuubi-defaults.conf (size $(wc -c < "$CONF_FILE") bytes)"
exec ${KYUUBI_HOME}/bin/kyuubi run --conf spark.master=k8s://https://kubernetes.default.svc:443