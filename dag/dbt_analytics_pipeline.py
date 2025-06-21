"""
DBT Analytics Pipeline - Clean Architecture
==========================================

This DAG demonstrates the clean, modular architecture for data platform pipelines:
- It uses the custom DbtSparkOperator for a clean interface.
- Configuration-driven approach.
- Environment-aware execution.
- Proper resource management via the custom operator.
"""

from datetime import datetime, timedelta

from airflow.models.dag import DAG
from airflow.operators.dummy_operator import DummyOperator

# Import our clean operators
from operators.dbt_spark_operator import (
    DbtSparkRunOperator,
    DbtSparkTestOperator,
    DbtSparkDebugOperator,
    DbtSparkDepsOperator,
    DbtSparkDocsOperator,
    DbtSparkSeedOperator,
    DbtSparkConfig,
)

# Define the configuration for our DBT operator
# This points the operator to the dbt project on the host machine.
dbt_spark_config = DbtSparkConfig(
    host_dbt_path="/home/anhhoangdev/Documents/LocalDataPlatform/dbt"
)

# Define DAG default arguments
default_args = {
    'owner': 'data-platform-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
    # Pass the config to all DbtSparkOperator tasks
    'config': dbt_spark_config,
}

# Create the DAG
with DAG(
    dag_id='dbt_analytics_pipeline_v2',
    default_args=default_args,
    description='Clean DBT Analytics Pipeline using DbtSparkOperator',
    schedule_interval=timedelta(days=1),
    catchup=False,
    max_active_runs=1,
    tags=['dbt', 'spark', 'k8s', 'kyuubi', 'clean-architecture'],
) as dag:
    
    # ------------------------------------------------------------------
    # TASK DEFINITIONS
    # ------------------------------------------------------------------
    start_pipeline = DummyOperator(task_id='start_pipeline')

    # 1. Infrastructure Validation
    validate_dbt_connection = DbtSparkDebugOperator(
        task_id='validate_dbt_connection',
        target="dev"
    )

    install_dbt_deps = DbtSparkDepsOperator(
        task_id='install_dbt_deps',
        target="dev"
    )

    # 2. Data Seeding (example, can be conditional)
    seed_reference_data = DbtSparkSeedOperator(
        task_id='seed_reference_data',
        target="dev"
    )

    # 3. Data Transformation - Staging Models (run individually)
    run_stg_users = DbtSparkRunOperator(
        task_id='run_stg_users',
        models='stg_users',
        target="dev",
        num_executors=2
    )

    run_stg_orders = DbtSparkRunOperator(
        task_id='run_stg_orders',
        models='stg_orders',
        target="dev",
        num_executors=2
    )

    # 4. Data Transformation - Marts Layer
    run_simple_pipeline = DbtSparkRunOperator(
        task_id='run_simple_pipeline',
        models='simple_pipeline',
        target="dev",
        num_executors=4
    )

    # 5. Documentation
    generate_documentation = DbtSparkDocsOperator(
        task_id='generate_documentation',
        target="dev"
    )

    end_pipeline = DummyOperator(task_id='end_pipeline')

    # ------------------------------------------------------------------
    # TASK DEPENDENCIES
    # ------------------------------------------------------------------
    start_pipeline >> validate_dbt_connection >> install_dbt_deps

    install_dbt_deps >> seed_reference_data

    seed_reference_data >> run_stg_users >> run_stg_orders >> run_simple_pipeline >> generate_documentation >> end_pipeline 