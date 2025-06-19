"""
Pipeline Configuration Management
=================================

Centralized configuration management for data platform pipelines.
Supports environment-specific configurations and external configuration sources.
"""

import os
from dataclasses import dataclass, field
from enum import Enum
from typing import Dict, Any, Optional, List
from pathlib import Path

from airflow.configuration import conf


class EnvironmentType(Enum):
    """Environment types for pipeline execution"""
    DEVELOPMENT = "dev"
    STAGING = "staging" 
    PRODUCTION = "prod"


@dataclass
class PipelineConfig:
    """
    Centralized configuration for data platform pipelines
    
    This class manages all configuration aspects including:
    - Environment-specific settings
    - DBT configuration
    - Kubernetes configuration  
    - Scheduling and retry policies
    """
    
    # Environment settings
    environment: EnvironmentType = EnvironmentType.DEVELOPMENT
    
    # DBT Configuration
    dbt_project_name: str = "analytics"
    dbt_target: str = "dev"
    dbt_threads: int = 4
    dbt_vars: Dict[str, Any] = field(default_factory=dict)
    
    # Kubernetes Configuration
    k8s_namespace: str = "airflow"
    dbt_image: str = "dbt-spark:latest"
    dbt_image_pull_policy: str = "IfNotPresent"
    
    # Volume Configuration
    dbt_volume_path: str = "/opt/dbt"
    dag_volume_path: str = "/opt/airflow/dags"
    
    # Resource Configuration
    default_cpu_request: str = "250m"
    default_cpu_limit: str = "1000m"
    default_memory_request: str = "512Mi"
    default_memory_limit: str = "2Gi"
    
    # Spark/Kyuubi Configuration
    spark_host: str = "kyuubi-dbt.kyuubi.svc.cluster.local"
    spark_port: int = 10009
    spark_schema: str = "default"
    
    # Pipeline Scheduling
    default_retries: int = 2
    default_retry_delay_minutes: int = 5
    max_active_runs: int = 1
    
    # Data Storage
    warehouse_base_path: str = "s3a://warehouse"
    
    # Monitoring and Alerting
    enable_slack_alerts: bool = False
    slack_webhook_url: Optional[str] = None
    
    # Additional Environment Variables
    extra_env_vars: Dict[str, str] = field(default_factory=dict)

    def get_dbt_vars_for_environment(self) -> Dict[str, Any]:
        """Get environment-specific DBT variables"""
        base_vars = {
            'environment': self.environment.value,
            'warehouse_path': f"{self.warehouse_base_path}/{self.environment.value}",
            **self.dbt_vars
        }
        
        # Add environment-specific variables
        if self.environment == EnvironmentType.PRODUCTION:
            base_vars.update({
                'enable_profiling': False,
                'sample_size': None,
                'enable_data_quality_checks': True
            })
        elif self.environment == EnvironmentType.STAGING:
            base_vars.update({
                'enable_profiling': True,
                'sample_size': 10000,
                'enable_data_quality_checks': True
            })
        else:  # Development
            base_vars.update({
                'enable_profiling': True,
                'sample_size': 1000,
                'enable_data_quality_checks': False
            })
        
        return base_vars

    def get_resource_requirements(self, task_type: str = "default") -> Dict[str, str]:
        """Get resource requirements based on task type"""
        resource_configs = {
            "default": {
                "cpu_request": self.default_cpu_request,
                "cpu_limit": self.default_cpu_limit,
                "memory_request": self.default_memory_request,
                "memory_limit": self.default_memory_limit
            },
            "heavy": {
                "cpu_request": "500m",
                "cpu_limit": "2000m", 
                "memory_request": "1Gi",
                "memory_limit": "4Gi"
            },
            "light": {
                "cpu_request": "100m",
                "cpu_limit": "500m",
                "memory_request": "256Mi", 
                "memory_limit": "1Gi"
            }
        }
        
        return resource_configs.get(task_type, resource_configs["default"])

    def get_schedule_interval(self, pipeline_type: str = "default") -> str:
        """Get schedule interval based on pipeline type and environment"""
        schedules = {
            EnvironmentType.PRODUCTION: {
                "default": "0 6 * * *",  # Daily at 6 AM
                "hourly": "0 * * * *",   # Every hour
                "critical": "*/30 * * * *"  # Every 30 minutes
            },
            EnvironmentType.STAGING: {
                "default": "0 8 * * *",  # Daily at 8 AM
                "hourly": "0 */2 * * *", # Every 2 hours
                "critical": "0 */6 * * *"  # Every 6 hours
            },
            EnvironmentType.DEVELOPMENT: {
                "default": None,  # Manual trigger only
                "hourly": None,
                "critical": None
            }
        }
        
        return schedules[self.environment].get(pipeline_type, schedules[self.environment]["default"])

    @classmethod
    def from_environment(cls, env_override: Optional[str] = None) -> 'PipelineConfig':
        """Create configuration from environment variables and Airflow config"""
        
        # Determine environment
        env_str = env_override or os.getenv('DATA_PLATFORM_ENV', 'dev')
        try:
            environment = EnvironmentType(env_str)
        except ValueError:
            environment = EnvironmentType.DEVELOPMENT
        
        # Build configuration
        config = cls(
            environment=environment,
            
            # DBT settings from environment or Airflow config
            dbt_project_name=os.getenv('DBT_PROJECT_NAME', 'analytics'),
            dbt_target=os.getenv('DBT_TARGET', environment.value),
            dbt_threads=int(os.getenv('DBT_THREADS', '4')),
            
            # Kubernetes settings
            k8s_namespace=conf.get('kubernetes', 'namespace', fallback='airflow'),
            dbt_image=os.getenv('DBT_IMAGE', 'dbt-spark:latest'),
            
            # Volume paths
            dbt_volume_path=os.getenv('DBT_VOLUME_PATH', '/opt/dbt'),
            dag_volume_path=os.getenv('DAG_VOLUME_PATH', '/opt/airflow/dags'),
            
            # Spark/Kyuubi settings
            spark_host=os.getenv('SPARK_HOST', 'kyuubi-dbt.kyuubi.svc.cluster.local'),
            spark_port=int(os.getenv('SPARK_PORT', '10009')),
            spark_schema=os.getenv('SPARK_SCHEMA', 'default'),
            
            # Storage settings
            warehouse_base_path=os.getenv('WAREHOUSE_BASE_PATH', 's3a://warehouse'),
            
            # Monitoring settings
            enable_slack_alerts=os.getenv('ENABLE_SLACK_ALERTS', 'false').lower() == 'true',
            slack_webhook_url=os.getenv('SLACK_WEBHOOK_URL'),
        )
        
        # Add extra environment variables
        config.extra_env_vars = {
            k: v for k, v in os.environ.items() 
            if k.startswith('DBT_') or k.startswith('SPARK_') or k.startswith('WAREHOUSE_')
        }
        
        return config


def get_pipeline_config(environment: Optional[str] = None) -> PipelineConfig:
    """
    Get pipeline configuration for the specified environment
    
    Args:
        environment: Optional environment override
        
    Returns:
        PipelineConfig instance
    """
    return PipelineConfig.from_environment(environment)


# Pre-configured instances for common environments
DEV_CONFIG = PipelineConfig.from_environment('dev')
STAGING_CONFIG = PipelineConfig.from_environment('staging') 
PROD_CONFIG = PipelineConfig.from_environment('prod') 