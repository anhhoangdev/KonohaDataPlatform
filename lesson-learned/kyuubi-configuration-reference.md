# Kyuubi Configuration Reference

## Environment Variables

### Core Kyuubi Configuration
```yaml
# CRITICAL: Frontend binding for external connections
- name: KYUUBI_FRONTEND_BIND_HOST
  value: "0.0.0.0"

# Engine sharing level: USER, CONNECTION, SERVER
- name: KYUUBI_ENGINE_SHARE_LEVEL
  value: "USER"  # or "SERVER"

# Session timeout (ISO 8601 duration format)
- name: KYUUBI_SESSION_ENGINE_IDLE_TIMEOUT
  value: "PT30S"  # 30 seconds for USER-level
  # value: "PT15M"  # 15 minutes for SERVER-level

# High availability (disable for single-node)
- name: KYUUBI_HA_ENABLED
  value: "false"

# Main resource JAR location
- name: KYUUBI_SESSION_ENGINE_SPARK_MAIN_RESOURCE
  value: "local:///opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar"
```

### Spark Kubernetes Configuration
```yaml
# Kubernetes master endpoint
- name: SPARK_MASTER
  value: "k8s://https://kubernetes.default.svc:443"

# Container image for Spark executors/drivers
- name: SPARK_KUBERNETES_CONTAINER_IMAGE
  value: "spark-engine-iceberg:1.5.0"

# Image pull policy (Never for local Minikube images)
- name: SPARK_KUBERNETES_CONTAINER_IMAGE_PULLPOLICY
  value: "Never"

# Service account for Spark pods
- name: SPARK_KUBERNETES_AUTHENTICATE_DRIVER_SERVICEACCOUNTNAME
  value: "kyuubi-sa"

# Deployment mode
- name: SPARK_SUBMIT_DEPLOYMODE
  value: "cluster"

# Namespace for Spark pods
- name: SPARK_KUBERNETES_NAMESPACE
  value: "kyuubi"
```

### Spark Resource Configuration
```yaml
# Driver resources
- name: SPARK_DRIVER_MEMORY
  value: "5g"
- name: SPARK_DRIVER_MEMORY_OVERHEAD
  value: "1g"
- name: SPARK_DRIVER_CORES
  value: "1"

# Executor resources
- name: SPARK_EXECUTOR_MEMORY
  value: "12g"
- name: SPARK_EXECUTOR_CORES
  value: "2"
- name: SPARK_EXECUTOR_INSTANCES
  value: "2"  # Initial executors (if not using dynamic allocation)
```

### Dynamic Allocation Configuration
```yaml
# Enable dynamic allocation
- name: SPARK_DYNAMICALLOCATION_ENABLED
  value: "true"

# Executor scaling
- name: SPARK_DYNAMICALLOCATION_MINEXECUTORS
  value: "0"
- name: SPARK_DYNAMICALLOCATION_MAXEXECUTORS
  value: "9"
- name: SPARK_DYNAMICALLOCATION_INITIALEXECUTORS
  value: "1"

# Timeout settings
- name: SPARK_DYNAMICALLOCATION_EXECUTORIDLETIMEOUT
  value: "60s"
- name: SPARK_DYNAMICALLOCATION_CACHEDEXECUTORIDLETIMEOUT
  value: "1800s"  # 30 minutes

# Scaling behavior
- name: SPARK_DYNAMICALLOCATION_SUSTAINEDSCHEDULERBACKLOGTIMEOUT
  value: "1s"
- name: SPARK_DYNAMICALLOCATION_SCHEDULERBACKLOGTIMEOUT
  value: "1s"
```

### Hive Metastore Configuration
```yaml
# Hive Metastore URI
- name: SPARK_HIVE_METASTORE_URIS
  value: "thrift://hive-metastore:9083"

# Hive support
- name: SPARK_SQL_CATALOGIMPLEMENTATION
  value: "hive"
```

### Additional Spark Configuration
```yaml
# Event logging
- name: SPARK_EVENTLOG_ENABLED
  value: "true"
- name: SPARK_EVENTLOG_DIR
  value: "/tmp/spark-events"

# Serialization
- name: SPARK_SERIALIZER
  value: "org.apache.spark.serializer.KryoSerializer"

# Ivy repository for JAR downloads
- name: SPARK_JARS_IVY
  value: "/tmp/.ivy2"

# User for Spark processes
- name: SPARK_USER
  value: "spark"
```

## Kyuubi Server Properties

### Core Properties (kyuubi-defaults.conf)
```properties
# Frontend configuration
kyuubi.frontend.bind.host=0.0.0.0
kyuubi.frontend.bind.port=10009
kyuubi.frontend.rest.bind.port=10099

# Engine configuration
kyuubi.session.engine.type=SPARK_SQL
kyuubi.session.engine.share.level=USER
kyuubi.session.engine.idle.timeout=PT30S

# Spark engine specific
kyuubi.session.engine.spark.main.resource=local:///opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar
kyuubi.engine.spark.application.name=kyuubi-spark-sql-engine

# High availability
kyuubi.ha.enabled=false

# Authentication (disabled for development)
kyuubi.authentication=NONE
```

### Spark Properties via Kyuubi
```properties
# Kubernetes configuration
spark.master=k8s://https://kubernetes.default.svc:443
spark.submit.deployMode=cluster
spark.kubernetes.namespace=kyuubi
spark.kubernetes.authenticate.driver.serviceAccountName=kyuubi-sa
spark.kubernetes.container.image=spark-engine-iceberg:1.5.0
spark.kubernetes.container.image.pullPolicy=Never

# Resource allocation
spark.driver.memory=5g
spark.driver.memoryOverhead=1g
spark.executor.memory=12g
spark.executor.cores=2

# Dynamic allocation
spark.dynamicAllocation.enabled=true
spark.dynamicAllocation.minExecutors=0
spark.dynamicAllocation.maxExecutors=9
spark.dynamicAllocation.executorIdleTimeout=60s
spark.dynamicAllocation.cachedExecutorIdleTimeout=1800s

# Hive integration
spark.sql.catalogImplementation=hive
spark.hive.metastore.uris=thrift://hive-metastore:9083

# Event logging
spark.eventLog.enabled=true
spark.eventLog.dir=/tmp/spark-events

# Serialization
spark.serializer=org.apache.spark.serializer.KryoSerializer

# Ivy configuration
spark.jars.ivy=/tmp/.ivy2
```

## Kubernetes Deployment Configuration

### Resource Limits and Requests
```yaml
resources:
  requests:
    memory: "500Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "500m"
```

### Health Checks
```yaml
livenessProbe:
  tcpSocket:
    port: 10009
  initialDelaySeconds: 60
  periodSeconds: 30
  timeoutSeconds: 10
  failureThreshold: 3

readinessProbe:
  tcpSocket:
    port: 10009
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3
```

### Service Configuration
```yaml
apiVersion: v1
kind: Service
metadata:
  name: kyuubi-dbt
  namespace: kyuubi
spec:
  selector:
    app: kyuubi-dbt
  ports:
  - name: thrift-binary
    port: 10009
    targetPort: 10009
    protocol: TCP
  - name: rest-api
    port: 10099
    targetPort: 10099
    protocol: TCP
  type: ClusterIP
```

## Docker Image Configuration

### Kyuubi Server Dockerfile
```dockerfile
FROM apache/kyuubi:1.10.0

# Create directories
RUN mkdir -p /opt/kyuubi/externals/engines/spark

# Download and install Kyuubi Spark SQL Engine JAR
RUN curl -L https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.12/1.10.0/kyuubi-spark-sql-engine_2.12-1.10.0.jar \
    -o /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar

# Set permissions
RUN chown -R kyuubi:kyuubi /opt/kyuubi/externals && \
    chmod -R 755 /opt/kyuubi/externals

# Expose ports
EXPOSE 10009 10099

# Default command
CMD ["/opt/kyuubi/bin/kyuubi", "run"]
```

### Spark Engine Dockerfile
```dockerfile
FROM apache/spark:3.5.0

# Install Iceberg runtime
RUN curl -L https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.5.0/iceberg-spark-runtime-3.5_2.12-1.5.0.jar \
    -o /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.5.0.jar

# Install AWS SDK (for S3 support)
RUN curl -L https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar \
    -o /opt/spark/jars/hadoop-aws-3.3.4.jar && \
    curl -L https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar \
    -o /opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar

# CRITICAL: Install Kyuubi Spark SQL Engine JAR
RUN curl -L https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.12/1.10.0/kyuubi-spark-sql-engine_2.12-1.10.0.jar \
    -o /opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar

# Create kyuubi directories and copy JAR
RUN mkdir -p /opt/kyuubi/externals/engines/spark && \
    cp /opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar

# Create work directory and set permissions
RUN mkdir -p /opt/spark/work-dir && \
    chown -R 1000:1000 /opt/kyuubi /opt/spark/work-dir && \
    chmod -R 755 /opt/kyuubi /opt/spark/work-dir

# Set environment variables
ENV SPARK_USER=spark
ENV SPARK_WORKDIR=/opt/spark/work-dir

# Expose Spark ports
EXPOSE 4040 7077 8080 8081
```

## RBAC Configuration

### Service Account
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kyuubi-sa
  namespace: kyuubi
automountServiceAccountToken: true
```

### Cluster Role
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kyuubi-spark-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "persistentvolumeclaims"]
  verbs: ["create", "get", "list", "watch", "delete", "update", "patch"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions", "networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "watch"]
```

### Cluster Role Binding
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kyuubi-spark-binding
subjects:
- kind: ServiceAccount
  name: kyuubi-sa
  namespace: kyuubi
roleRef:
  kind: ClusterRole
  name: kyuubi-spark-role
  apiGroup: rbac.authorization.k8s.io
```

## Configuration Validation

### Required JAR Files
Ensure these JARs are present in the Spark image:
- `/opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar`
- `/opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.5.0.jar`
- `/opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar`

### Required Permissions
- `/opt/spark/work-dir/`: `1000:1000` ownership, `755` permissions
- `/opt/kyuubi/`: `1000:1000` ownership, `755` permissions

### Required Environment Variables
- `KYUUBI_FRONTEND_BIND_HOST=0.0.0.0`
- `SPARK_KUBERNETES_CONTAINER_IMAGE=spark-engine-iceberg:1.5.0`
- `SPARK_USER=spark`

## Performance Tuning Guidelines

### Memory Configuration
- **Driver**: 5GB + 1GB overhead for metadata operations
- **Executors**: 12GB for large data processing
- **Total cluster**: Ensure 24GB+ available in Minikube

### CPU Configuration
- **Driver**: 1 core (sufficient for coordination)
- **Executors**: 2 cores each (good balance for parallelism)
- **Total cluster**: 12+ cores recommended

### Timeout Configuration
- **USER-level**: 30s timeout for development/testing
- **SERVER-level**: 15min timeout for production workloads
- **Executor idle**: 60s for quick cleanup
- **Cached executor**: 30min for reuse optimization 