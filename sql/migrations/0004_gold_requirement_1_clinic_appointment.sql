-- Migration 0004: Requirement 1 - Clinic Appointment Volume
-- Weekly clinic appointment metrics with completion rates, cancellation rates, no-show rates
-- Includes network benchmarking and underperformance detection

CREATE OR REPLACE VIEW gold.v_ops_clinic_appointment_weekly AS
WITH weekly_clinic AS (
    SELECT
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area,
        clinic.clinic_state,
        appointment.appointment_week_start_date,
        COUNT(*) AS total_appointments,
        SUM(CASE WHEN appointment.is_completed THEN 1 ELSE 0 END) AS completed_appointments,
        SUM(CASE WHEN appointment.is_cancelled THEN 1 ELSE 0 END) AS cancelled_appointments,
        SUM(CASE WHEN appointment.is_no_show THEN 1 ELSE 0 END) AS no_show_appointments
    FROM gold.fact_clin_appointment AS appointment
    INNER JOIN gold.dim_core_clinic AS clinic
        ON appointment.clinic_sk = clinic.clinic_sk
    GROUP BY
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area,
        clinic.clinic_state,
        appointment.appointment_week_start_date
),
network_benchmark AS (
    SELECT
        appointment_week_start_date,
        AVG(
            CASE
                WHEN total_appointments > 0
                THEN CAST(completed_appointments AS DOUBLE) / total_appointments
                ELSE NULL
            END
        ) AS network_completion_rate
    FROM weekly_clinic
    GROUP BY appointment_week_start_date
)
SELECT
    weekly_clinic.clinic_id,
    weekly_clinic.clinic_name,
    weekly_clinic.clinic_area,
    weekly_clinic.clinic_state,
    weekly_clinic.appointment_week_start_date,
    weekly_clinic.total_appointments,
    weekly_clinic.completed_appointments,
    weekly_clinic.cancelled_appointments,
    weekly_clinic.no_show_appointments,
    CASE
        WHEN weekly_clinic.total_appointments > 0
        THEN CAST(weekly_clinic.completed_appointments AS DOUBLE) / weekly_clinic.total_appointments
        ELSE NULL
    END AS completion_rate,
    CASE
        WHEN weekly_clinic.total_appointments > 0
        THEN CAST(weekly_clinic.cancelled_appointments AS DOUBLE) / weekly_clinic.total_appointments
        ELSE NULL
    END AS cancellation_rate,
    CASE
        WHEN weekly_clinic.total_appointments > 0
        THEN CAST(weekly_clinic.no_show_appointments AS DOUBLE) / weekly_clinic.total_appointments
        ELSE NULL
    END AS no_show_rate,
    network_benchmark.network_completion_rate,
    CASE
        WHEN weekly_clinic.total_appointments = 0 THEN FALSE
        WHEN CAST(weekly_clinic.completed_appointments AS DOUBLE) / weekly_clinic.total_appointments
             < network_benchmark.network_completion_rate
        THEN TRUE
        ELSE FALSE
    END AS is_underperforming
FROM weekly_clinic
LEFT JOIN network_benchmark
    ON weekly_clinic.appointment_week_start_date = network_benchmark.appointment_week_start_date;
