{{
  config(
    materialized='table',
    file_format='iceberg',
    location_root=var('warehouse_path') ~ '/staging',
    tags=['staging', 'users'],
    on_schema_change='fail'
  )
}}

-- Staging table for users with dummy data
-- This demonstrates CTE functionality with clean data transformations

WITH raw_users AS (
    SELECT 1 as user_id, 'Alice Johnson' as full_name, 'alice@example.com' as email, 25 as age, 'Engineering' as department
    UNION ALL
    SELECT 2, 'Bob Smith', 'bob@example.com', 30, 'Marketing'
    UNION ALL  
    SELECT 3, 'Charlie Brown', 'charlie@example.com', 35, 'Sales'
    UNION ALL
    SELECT 4, 'Diana Prince', 'diana@example.com', 28, 'Engineering'
    UNION ALL
    SELECT 5, 'Eve Wilson', 'eve@example.com', 32, 'Marketing'
),

cleaned_users AS (
    SELECT 
        user_id,
        TRIM(full_name) as full_name,
        LOWER(TRIM(email)) as email,
        age,
        UPPER(TRIM(department)) as department,
        SPLIT(full_name, ' ')[0] as first_name,
        SPLIT(full_name, ' ')[1] as last_name,
        current_timestamp() as created_at,
        CASE 
            WHEN age < 30 THEN 'Young Professional'
            WHEN age >= 30 AND age < 40 THEN 'Mid-Career'
            ELSE 'Senior Professional'
        END as career_stage
    FROM raw_users
)

SELECT * FROM cleaned_users 