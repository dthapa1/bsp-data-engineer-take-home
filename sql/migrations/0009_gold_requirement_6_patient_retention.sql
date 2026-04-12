-- Migration 0009: Requirement 6 - Patient Retention Cohort
-- Monthly patient cohorts with return tracking at 30/60/90-day windows
-- Cohorts defined by first completed appointment; tracks retention rates by referral source

CREATE OR REPLACE VIEW gold.v_clin_patient_retention_monthly AS
WITH completed_appointments AS (
    SELECT
        appointment.appointment_id,
        appointment.patient_id,
        appointment.clinic_id,
        appointment.appointment_scheduled_date
    FROM gold.fact_clin_appointment AS appointment
    WHERE appointment.is_completed = TRUE
),
first_completed_appointment AS (
    SELECT
        appointment_id,
        patient_id,
        clinic_id,
        appointment_scheduled_date AS first_appointment_date,
        DATE_TRUNC('month', appointment_scheduled_date) AS cohort_month_start_date,
        ROW_NUMBER() OVER (
            PARTITION BY patient_id
            ORDER BY appointment_scheduled_date, appointment_id
        ) AS rn
    FROM completed_appointments
),
patient_cohort AS (
    SELECT
        first_appointment.patient_id,
        first_appointment.clinic_id,
        first_appointment.first_appointment_date,
        first_appointment.cohort_month_start_date,
        COALESCE(referral.referral_source, 'unknown') AS referral_source
    FROM first_completed_appointment AS first_appointment
    LEFT JOIN (
        SELECT
            patient_id,
            referral_source,
            ROW_NUMBER() OVER (
                PARTITION BY patient_id
                ORDER BY referral_stage_entered_at
            ) AS rn
        FROM gold.fact_pipe_referral_stage
        WHERE referral_stage_rank = 1
    ) AS referral
        ON first_appointment.patient_id = referral.patient_id
       AND referral.rn = 1
    WHERE first_appointment.rn = 1
),
patient_returns AS (
    SELECT
        cohort.patient_id,
        cohort.clinic_id,
        cohort.referral_source,
        cohort.first_appointment_date,
        cohort.cohort_month_start_date,
        MAX(
            CASE
                WHEN follow_up.appointment_scheduled_date > cohort.first_appointment_date
                 AND follow_up.appointment_scheduled_date <= cohort.first_appointment_date + 30
                THEN 1 ELSE 0
            END
        ) AS returned_within_30_days,
        MAX(
            CASE
                WHEN follow_up.appointment_scheduled_date > cohort.first_appointment_date
                 AND follow_up.appointment_scheduled_date <= cohort.first_appointment_date + 60
                THEN 1 ELSE 0
            END
        ) AS returned_within_60_days,
        MAX(
            CASE
                WHEN follow_up.appointment_scheduled_date > cohort.first_appointment_date
                 AND follow_up.appointment_scheduled_date <= cohort.first_appointment_date + 90
                THEN 1 ELSE 0
            END
        ) AS returned_within_90_days
    FROM patient_cohort AS cohort
    LEFT JOIN completed_appointments AS follow_up
        ON cohort.patient_id = follow_up.patient_id
    GROUP BY
        cohort.patient_id,
        cohort.clinic_id,
        cohort.referral_source,
        cohort.first_appointment_date,
        cohort.cohort_month_start_date
)
SELECT
    clinic.clinic_id,
    clinic.clinic_name,
    clinic.clinic_area,
    clinic.clinic_state,
    returns.referral_source,
    returns.cohort_month_start_date,
    COUNT(*) AS cohort_size,
    SUM(returns.returned_within_30_days) AS returned_within_30_days_count,
    SUM(returns.returned_within_60_days) AS returned_within_60_days_count,
    SUM(returns.returned_within_90_days) AS returned_within_90_days_count,
    CASE
        WHEN COUNT(*) > 0 THEN CAST(SUM(returns.returned_within_30_days) AS DOUBLE) / COUNT(*)
        ELSE NULL
    END AS retention_30_day_rate,
    CASE
        WHEN COUNT(*) > 0 THEN CAST(SUM(returns.returned_within_60_days) AS DOUBLE) / COUNT(*)
        ELSE NULL
    END AS retention_60_day_rate,
    CASE
        WHEN COUNT(*) > 0 THEN CAST(SUM(returns.returned_within_90_days) AS DOUBLE) / COUNT(*)
        ELSE NULL
    END AS retention_90_day_rate
FROM patient_returns AS returns
INNER JOIN gold.dim_core_clinic AS clinic
    ON returns.clinic_id = clinic.clinic_id
GROUP BY
    clinic.clinic_id,
    clinic.clinic_name,
    clinic.clinic_area,
    clinic.clinic_state,
    returns.referral_source,
    returns.cohort_month_start_date;
