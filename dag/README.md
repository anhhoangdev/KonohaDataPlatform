# Airflow DAG Directory

This directory contains all Airflow DAG definitions that will be mounted into the Airflow deployment.

## Structure

```
dag/
├── operators/          # Custom operators and plugins
│   ├── __init__.py
│   └── dbt_spark_operator.py
├── dags/              # DAG definitions
│   ├── __init__.py
│   └── dbt_analytics_pipeline.py
├── config/            # Configuration files
│   ├── __init__.py
│   └── pipeline_config.py
└── utils/             # Utility functions
    ├── __init__.py
    └── k8s_utils.py
```

## Mounting Strategy

This directory is designed to be mounted at `/opt/airflow/dags` in the Airflow deployment:

```yaml
volumes:
- name: dag-volume
  hostPath:
    path: /path/to/your/project/dag
    type: Directory
```

## Best Practices

1. **Version Control**: All DAG files are version-controlled
2. **Modularity**: Operators are separated from DAG definitions
3. **Configuration**: External configuration management
4. **Testing**: Each DAG includes proper testing capabilities 