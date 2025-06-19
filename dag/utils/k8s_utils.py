"""
Kubernetes Utilities for Data Platform
======================================

Utility functions for creating and managing Kubernetes resources
in data platform pipelines.
"""

from typing import Dict, List, Optional, Tuple
from kubernetes.client import models as k8s

from config.pipeline_config import PipelineConfig


def get_resource_requirements(
    cpu_request: str = "250m",
    cpu_limit: str = "1000m", 
    memory_request: str = "512Mi",
    memory_limit: str = "2Gi"
) -> k8s.V1ResourceRequirements:
    """
    Create Kubernetes resource requirements
    
    Args:
        cpu_request: CPU request (e.g., "250m")
        cpu_limit: CPU limit (e.g., "1000m")
        memory_request: Memory request (e.g., "512Mi")
        memory_limit: Memory limit (e.g., "2Gi")
        
    Returns:
        V1ResourceRequirements object
    """
    return k8s.V1ResourceRequirements(
        requests={
            'memory': memory_request,
            'cpu': cpu_request
        },
        limits={
            'memory': memory_limit,
            'cpu': cpu_limit
        }
    )


def create_volume_config(
    volume_name: str,
    host_path: str,
    mount_path: str,
    read_only: bool = False,
    path_type: str = "Directory"
) -> Tuple[k8s.V1Volume, k8s.V1VolumeMount]:
    """
    Create Kubernetes volume and volume mount configuration
    
    Args:
        volume_name: Name of the volume
        host_path: Host path to mount
        mount_path: Container mount path
        read_only: Whether mount is read-only
        path_type: Host path type (Directory, File, etc.)
        
    Returns:
        Tuple of (V1Volume, V1VolumeMount)
    """
    volume_mount = k8s.V1VolumeMount(
        name=volume_name,
        mount_path=mount_path,
        read_only=read_only
    )
    
    volume = k8s.V1Volume(
        name=volume_name,
        host_path=k8s.V1HostPathVolumeSource(
            path=host_path,
            type=path_type
        )
    )
    
    return volume, volume_mount


def create_configmap_volume(
    volume_name: str,
    configmap_name: str,
    mount_path: str,
    items: Optional[List[Dict[str, str]]] = None
) -> Tuple[k8s.V1Volume, k8s.V1VolumeMount]:
    """
    Create ConfigMap volume and volume mount
    
    Args:
        volume_name: Name of the volume
        configmap_name: Name of the ConfigMap
        mount_path: Container mount path
        items: Optional list of items to mount from ConfigMap
        
    Returns:
        Tuple of (V1Volume, V1VolumeMount)
    """
    volume_mount = k8s.V1VolumeMount(
        name=volume_name,
        mount_path=mount_path,
        read_only=True
    )
    
    # Create ConfigMap volume source
    configmap_items = None
    if items:
        configmap_items = [
            k8s.V1KeyToPath(key=item['key'], path=item['path'])
            for item in items
        ]
    
    volume = k8s.V1Volume(
        name=volume_name,
        config_map=k8s.V1ConfigMapVolumeSource(
            name=configmap_name,
            items=configmap_items
        )
    )
    
    return volume, volume_mount


def create_secret_volume(
    volume_name: str,
    secret_name: str,
    mount_path: str,
    default_mode: int = 0o600
) -> Tuple[k8s.V1Volume, k8s.V1VolumeMount]:
    """
    Create Secret volume and volume mount
    
    Args:
        volume_name: Name of the volume
        secret_name: Name of the Secret
        mount_path: Container mount path
        default_mode: Default file permissions
        
    Returns:
        Tuple of (V1Volume, V1VolumeMount)
    """
    volume_mount = k8s.V1VolumeMount(
        name=volume_name,
        mount_path=mount_path,
        read_only=True
    )
    
    volume = k8s.V1Volume(
        name=volume_name,
        secret=k8s.V1SecretVolumeSource(
            secret_name=secret_name,
            default_mode=default_mode
        )
    )
    
    return volume, volume_mount


def create_pod_template(
    name: str,
    image: str,
    config: PipelineConfig,
    command: Optional[List[str]] = None,
    args: Optional[List[str]] = None,
    env_vars: Optional[Dict[str, str]] = None,
    volumes: Optional[List[k8s.V1Volume]] = None,
    volume_mounts: Optional[List[k8s.V1VolumeMount]] = None,
    resource_type: str = "default"
) -> Dict:
    """
    Create a standardized pod template for data platform tasks
    
    Args:
        name: Pod name
        image: Container image
        config: Pipeline configuration
        command: Container command
        args: Container arguments
        env_vars: Environment variables
        volumes: Additional volumes
        volume_mounts: Additional volume mounts
        resource_type: Resource requirement type (default, heavy, light)
        
    Returns:
        Dictionary with pod configuration
    """
    # Get resource requirements
    resources = config.get_resource_requirements(resource_type)
    k8s_resources = get_resource_requirements(
        cpu_request=resources['cpu_request'],
        cpu_limit=resources['cpu_limit'],
        memory_request=resources['memory_request'],
        memory_limit=resources['memory_limit']
    )
    
    # Create base volumes for DBT
    dbt_volume, dbt_mount = create_volume_config(
        volume_name="dbt-projects",
        host_path=config.dbt_volume_path,
        mount_path="/dbt",
        read_only=False
    )
    
    # Combine volumes
    all_volumes = [dbt_volume]
    all_mounts = [dbt_mount]
    
    if volumes:
        all_volumes.extend(volumes)
    if volume_mounts:
        all_mounts.extend(volume_mounts)
    
    # Prepare environment variables
    base_env = {
        'ENVIRONMENT': config.environment.value,
        'DBT_PROJECT_NAME': config.dbt_project_name,
        'DBT_TARGET': config.dbt_target,
        'SPARK_HOST': config.spark_host,
        'SPARK_PORT': str(config.spark_port),
        **config.extra_env_vars
    }
    
    if env_vars:
        base_env.update(env_vars)
    
    return {
        'name': name,
        'image': image,
        'image_pull_policy': config.dbt_image_pull_policy,
        'command': command,
        'args': args,
        'env_vars': base_env,
        'volumes': all_volumes,
        'volume_mounts': all_mounts,
        'resources': k8s_resources,
        'namespace': config.k8s_namespace
    }


def create_monitoring_labels(
    dag_id: str,
    task_id: str,
    environment: str,
    pipeline_type: str = "dbt"
) -> Dict[str, str]:
    """
    Create standardized labels for monitoring and observability
    
    Args:
        dag_id: Airflow DAG ID
        task_id: Airflow task ID
        environment: Environment (dev, staging, prod)
        pipeline_type: Type of pipeline (dbt, spark, etc.)
        
    Returns:
        Dictionary of labels
    """
    return {
        'app.kubernetes.io/name': 'data-platform',
        'app.kubernetes.io/component': pipeline_type,
        'app.kubernetes.io/part-of': 'data-platform',
        'data-platform.io/dag-id': dag_id,
        'data-platform.io/task-id': task_id,
        'data-platform.io/environment': environment,
        'data-platform.io/pipeline-type': pipeline_type
    }


def get_node_selector(
    config: PipelineConfig,
    task_type: str = "default"
) -> Optional[Dict[str, str]]:
    """
    Get node selector based on task type and environment
    
    Args:
        config: Pipeline configuration
        task_type: Type of task (default, heavy, light)
        
    Returns:
        Node selector dictionary or None
    """
    if config.environment.value == "prod":
        # Production workloads on dedicated nodes
        if task_type == "heavy":
            return {"workload-type": "compute-intensive"}
        else:
            return {"workload-type": "data-platform"}
    
    # Development and staging can run on any nodes
    return None


def get_tolerations(
    config: PipelineConfig,
    task_type: str = "default"
) -> Optional[List[k8s.V1Toleration]]:
    """
    Get pod tolerations based on task type and environment
    
    Args:
        config: Pipeline configuration
        task_type: Type of task
        
    Returns:
        List of tolerations or None
    """
    if config.environment.value == "prod" and task_type == "heavy":
        return [
            k8s.V1Toleration(
                key="workload-type",
                operator="Equal",
                value="compute-intensive",
                effect="NoSchedule"
            )
        ]
    
    return None 