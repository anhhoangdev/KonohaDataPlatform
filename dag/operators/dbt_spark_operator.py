"""
DBT Spark Operator for Airflow - Clean Architecture
=============================

This module provides a clean, configurable DBT Spark operator that:
- Uses KubernetesPodOperator for execution
- Integrates with Kyuubi lightweight Spark execution
- Supports dynamic configuration via ConfigMaps/environment variables
- Follows infrastructure-as-code principles
- Provides proper error handling and logging
"""

import logging
from typing import Any, Dict, List, Optional, Union
from dataclasses import dataclass, field
from datetime import datetime

from airflow.models import BaseOperator
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from airflow.utils.context import Context
from airflow.utils.decorators import apply_defaults
from airflow.configuration import conf

# Import Kubernetes client objects
from kubernetes.client import models as k8s

logger = logging.getLogger(__name__)


@dataclass
class DbtSparkConfig:
    """Configuration class for DBT Spark execution"""
    
    # Core DBT settings
    dbt_project_dir: str = "/dbt"
    dbt_profiles_dir: str = "/dbt/profiles"
    
    # Kubernetes settings
    namespace: str = "airflow"
    image: str = "dbt-spark:latest"
    image_pull_policy: str = "IfNotPresent"
    
    # Spark/Kyuubi connection
    spark_host: str = "kyuubi-dbt.kyuubi.svc.cluster.local"
    spark_port: int = 10009
    spark_schema: str = "default"
    
    # DBT Pod resource requirements (for DBT execution, NOT Spark pods)
    cpu_request: str = "250m"
    cpu_limit: str = "500m"  # DBT command execution only
    memory_request: str = "512Mi" 
    memory_limit: str = "1Gi"   # DBT command execution only
    
    # Volume mounting
    dbt_volume_name: str = "dbt-volume"
    dbt_mount_path: str = "/dbt"
    host_dbt_path: str = "/opt/dbt"
    
    # Kyuubi-specific settings
    kyuubi_session_timeout: int = 300  # 5 minutes
    
    # Note: Spark resource configuration removed - managed by Kyuubi pod templates
    # Pod templates define: Driver + 2 Executors, each with 0.5 CPU, 1GB RAM
    
    # Environment variables
    extra_env_vars: Dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_airflow_config(cls) -> 'DbtSparkConfig':
        """Create configuration from Airflow configuration"""
        return cls(
            namespace=conf.get('kubernetes', 'namespace', fallback='airflow'),
            image=conf.get('dbt_spark', 'image', fallback='dbt-spark:latest'),
            spark_host=conf.get('dbt_spark', 'spark_host', fallback='kyuubi-dbt.kyuubi.svc.cluster.local'),
            spark_port=conf.getint('dbt_spark', 'spark_port', fallback=10009),
            dbt_project_dir=conf.get('dbt_spark', 'project_dir', fallback='/dbt'),
            host_dbt_path=conf.get('dbt_spark', 'host_dbt_path', fallback='/opt/dbt')
        )


class DbtSparkOperator(BaseOperator):
    """
    Clean DBT Spark Operator using Kubernetes Pods with Kyuubi Integration
    
    This operator provides a clean abstraction for running DBT commands
    against Spark via Kyuubi in Kubernetes environments with lightweight
    pod templates for optimal resource utilization.
    
    Features:
    - Dynamic configuration via dataclass
    - Proper volume mounting for DBT projects  
    - Resource management and limits
    - Comprehensive error handling
    - Support for all DBT commands and options
    - Kyuubi lightweight Spark execution integration
    """
    
    template_fields = ('command', 'select', 'exclude', 'vars', 'target')
    template_ext = ()
    ui_color = '#FF6B35'
    ui_fgcolor = '#FFFFFF'

    @apply_defaults
    def __init__(
        self,
        command: str,
        select: Optional[str] = None,
        exclude: Optional[str] = None,
        vars: Optional[Dict[str, Any]] = None,
        target: str = "dev",
        full_refresh: bool = False,
        threads: int = 1,
        num_executors: Optional[int] = None,
        config: Optional[DbtSparkConfig] = None,
        pod_override: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> None:
        super().__init__(**kwargs)
        self.command = command
        self.select = select
        self.exclude = exclude
        self.vars = vars or {}
        self.target = target
        self.full_refresh = full_refresh
        self.threads = threads
        self.num_executors = num_executors
        self.config = config or DbtSparkConfig.from_airflow_config()
        self.pod_override = pod_override or {}

    def _build_dbt_command(self) -> List[str]:
        """Build the complete DBT command with all parameters"""
        cmd = ['dbt', self.command]
        
        # Add target and profiles directory
        cmd.extend(['--target', self.target])
        cmd.extend(['--profiles-dir', self.config.dbt_profiles_dir])
        
        # Add selection criteria
        if self.select:
            cmd.extend(['--select', self.select])
        if self.exclude:
            cmd.extend(['--exclude', self.exclude])
            
        # Add variables for supported commands
        if self.vars and self._command_supports_vars():
            vars_str = ' '.join(f'{k}:{v}' for k, v in self.vars.items())
            cmd.extend(['--vars', f'{{{vars_str}}}'])
        
        # Add flags
        if self.full_refresh and self._command_supports_full_refresh():
            cmd.append('--full-refresh')
            
        # Add threading for supported commands
        if self._command_supports_threads():
            cmd.extend(['--threads', str(self.threads)])
        
        return cmd

    def _command_supports_vars(self) -> bool:
        """Check if command supports --vars parameter"""
        return self.command in ['run', 'test', 'compile', 'seed', 'snapshot']

    def _command_supports_full_refresh(self) -> bool:
        """Check if command supports --full-refresh parameter"""
        return self.command in ['run', 'seed']

    def _command_supports_threads(self) -> bool:
        """Check if command supports --threads parameter"""
        return self.command in ['run', 'test', 'compile', 'seed', 'snapshot']

    def _create_profiles_yaml(self) -> str:
        """Generate DBT profiles.yml content with Kyuubi integration"""
        spark_config_lines = [
            f'spark.kubernetes.executor.podNamePrefix: "dbt-spark-{{{{dag_id}}}}"',
            f'spark.app.name: "${{{{dag_id}}}}-${{{{task_id}}}}"'
        ]
        if self.num_executors:
            spark_config_lines.append(f'spark.executor.instances: "{self.num_executors}"')

        spark_config_str = '\n        '.join([f'"{key}": {value}' for conf in spark_config_lines for key, value in [conf.split(': ', 1)]])
        
        return f"""
analytics:
  target: {self.target}
  outputs:
    {self.target}:
      type: spark
      method: thrift
      host: {self.config.spark_host}
      port: {self.config.spark_port}
      user: admin
      schema: {self.config.spark_schema}
      connect_retries: 5
      connect_timeout: 60
      retry_all: true
      # Kyuubi session management
      session_timeout: {self.config.kyuubi_session_timeout}
      # Custom pod naming for Spark executors (controlled by Kyuubi pod templates)
      # Pod names will be: dbt-spark-{{{{ dag_id }}}}-{{{{ model_name }}}}-exec-{{{{ id }}}}
      spark_config:
        {spark_config_str}
      # Note: Resource configuration managed by Kyuubi pod templates (0.5 CPU, 1GB RAM per pod)
"""

    def _create_volumes_and_mounts(self) -> tuple:
        """Create Kubernetes volume and volume mount objects for the dbt project."""
        # Define how the volume is mounted in the container
        volume_mount = k8s.V1VolumeMount(
            name="dbt-projects-storage",  # A consistent name for the volume mount
            mount_path=self.config.dbt_mount_path,  # /dbt
            read_only=False
        )
        
        # Define the volume itself, referencing the PVC
        volume = k8s.V1Volume(
            name="dbt-projects-storage",  # This must match the volume_mount's name
            persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
                claim_name='dbt-projects-pvc'
            )
        )
        
        return volume, volume_mount

    def _create_resource_requirements(self) -> k8s.V1ResourceRequirements:
        """Create Kubernetes resource requirements"""
        return k8s.V1ResourceRequirements(
            requests={
                'memory': self.config.memory_request,
                'cpu': self.config.cpu_request
            },
            limits={
                'memory': self.config.memory_limit,
                'cpu': self.config.cpu_limit
            }
        )

    def _prepare_environment(self, context: Context) -> Dict[str, str]:
        """Prepare environment variables for the pod"""
        base_env = {
            # DBT Configuration
            'DBT_PROJECT_DIR': self.config.dbt_project_dir,
            'DBT_PROFILES_DIR': self.config.dbt_profiles_dir,
            'DBT_TARGET': self.target,
            
            # Airflow Context (useful for DBT macros and logging)
            'AIRFLOW_TASK_ID': self.task_id,
            'AIRFLOW_DAG_ID': context['dag'].dag_id,
            'AIRFLOW_RUN_ID': context['run_id'],
            'AIRFLOW_EXECUTION_DATE': context['ds'],
            'AIRFLOW_LOGICAL_DATE': context['logical_date'].isoformat(),
            
            # Kyuubi connection details
            'KYUUBI_HOST': self.config.spark_host,
            'KYUUBI_PORT': str(self.config.spark_port),
            'KYUUBI_SCHEMA': self.config.spark_schema,
            
            # DBT execution metadata (useful for custom macros)
            'DBT_COMMAND': self.command,
            'DBT_SELECT': self.select or '',
            'DBT_EXCLUDE': self.exclude or '',
            'DBT_FULL_REFRESH': str(self.full_refresh).lower(),
            'DBT_THREADS': str(self.threads),
            
            # Kubernetes context
            'K8S_NAMESPACE': self.config.namespace,
            'K8S_POD_NAME': '${HOSTNAME}',  # Will be resolved at runtime
            
            # Note: Spark resource configuration managed by Kyuubi pod templates
        }
        
        # Add extra environment variables
        base_env.update(self.config.extra_env_vars)
        
        return base_env

    def execute(self, context: Context) -> Any:
        """Execute the DBT command using KubernetesPodOperator"""
        
        # Build the DBT command
        dbt_cmd = self._build_dbt_command()
        profiles_content = self._create_profiles_yaml()
        
        # Create the execution script with Kyuubi integration
        execution_script = f'''
set -e

echo "🚀 Starting DBT Spark execution with Kyuubi..."
echo "================================================"
echo "Task: $AIRFLOW_TASK_ID"
echo "DAG: $AIRFLOW_DAG_ID"
echo "Run ID: $AIRFLOW_RUN_ID"
echo "Command: {' '.join(dbt_cmd)}"
echo "Target: $DBT_TARGET"
echo "Project Dir: $DBT_PROJECT_DIR"
echo "Kyuubi Host: $KYUUBI_HOST:$KYUUBI_PORT"
echo "Spark Resources: Managed by Kyuubi pod templates (0.5 CPU, 1GB RAM per pod)"
echo "================================================"

# Setup profiles with Kyuubi configuration
echo "📝 Creating DBT profiles with Kyuubi integration..."
mkdir -p $DBT_PROFILES_DIR
cat > $DBT_PROFILES_DIR/profiles.yml << 'EOF'
{profiles_content}
EOF

echo "✅ Profiles created successfully"

# Test Kyuubi connectivity using environment variables
echo "🔌 Testing Kyuubi connectivity..."
timeout 30s bash -c 'while ! nc -z $KYUUBI_HOST $KYUUBI_PORT; do sleep 1; done' || (echo "❌ Failed to connect to Kyuubi" && exit 1)
echo "✅ Kyuubi connection successful"

# Change to project directory using environment variable
echo "📂 Changing to DBT project directory..."
cd $DBT_PROJECT_DIR

# Show DBT version and configuration
echo "📋 DBT Configuration:"
dbt --version

# Execute DBT command
echo "⚡ Executing DBT command against Kyuubi..."
echo "   Expected Spark pods: dbt-spark-*-driver, dbt-spark-*-exec-1, dbt-spark-*-exec-2"
{' '.join(dbt_cmd)}

echo "🎉 DBT execution completed successfully!"
echo "🔍 Spark pods should have been cleaned up automatically"
'''
        
        # Create volumes and mounts
        volume, volume_mount = self._create_volumes_and_mounts()
        
        # Create resource requirements
        resources = self._create_resource_requirements()
        
        # Prepare environment
        env_vars = self._prepare_environment(context)
        
        # Create pod name with model context
        model_name = "unknown"
        if self.select:
            model_name = self.select.replace('tag:', '').replace(' ', '-')
        elif hasattr(self, 'models') and self.models:
            if isinstance(self.models, list):
                model_name = '-'.join(self.models[:2])  # Limit to 2 models for name length
            else:
                model_name = str(self.models)
        
        pod_name = f"dbt-{model_name}-{context['ts_nodash'].lower()}"
        
        logger.info(f"Executing DBT command in pod: {pod_name}")
        logger.info(f"Command: {' '.join(dbt_cmd)}")
        logger.info(f"Expected Spark pods: dbt-spark-*-driver, dbt-spark-*-exec-1, dbt-spark-*-exec-2")
        
        # Create and execute the pod
        pod_operator = KubernetesPodOperator(
            task_id=f"{self.task_id}_pod",
            name=pod_name,
            namespace=self.config.namespace,
            image=self.config.image,
            image_pull_policy=self.config.image_pull_policy,
            cmds=['bash', '-c'],
            arguments=[execution_script],
            env_vars=env_vars,
            volume_mounts=[volume_mount],
            volumes=[volume],
            container_resources=resources,
            is_delete_operator_pod=True,
            get_logs=True,
            log_events_on_failure=True,
            do_xcom_push=True,
            startup_timeout_seconds=300,
            **self.pod_override
        )
        
        return pod_operator.execute(context)


# Specialized operators for common DBT commands
class DbtSparkRunOperator(DbtSparkOperator):
    """DBT Run operator with additional model selection support"""
    
    @apply_defaults
    def __init__(self, models: Optional[Union[str, List[str]]] = None, **kwargs):
        if models:
            if isinstance(models, list):
                kwargs['select'] = ' '.join(models)
            else:
                kwargs['select'] = models
        super().__init__(command='run', **kwargs)


class DbtSparkTestOperator(DbtSparkOperator):
    """DBT Test operator"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='test', **kwargs)


class DbtSparkDebugOperator(DbtSparkOperator):
    """DBT Debug operator for connection testing"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='debug', **kwargs)


class DbtSparkDepsOperator(DbtSparkOperator):
    """DBT Deps operator for dependency installation"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='deps', **kwargs)


class DbtSparkDocsOperator(DbtSparkOperator):
    """DBT Docs operator for documentation generation"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='docs generate', **kwargs)


class DbtSparkSeedOperator(DbtSparkOperator):
    """DBT Seed operator"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='seed', **kwargs)


class DbtSparkSnapshotOperator(DbtSparkOperator):
    """DBT Snapshot operator"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='snapshot', **kwargs)


class DbtSparkCompileOperator(DbtSparkOperator):
    """DBT Compile operator"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='compile', **kwargs)


class DbtSparkFreshnessOperator(DbtSparkOperator):
    """DBT Source freshness operator"""
    
    @apply_defaults
    def __init__(self, **kwargs):
        super().__init__(command='source freshness', **kwargs) 