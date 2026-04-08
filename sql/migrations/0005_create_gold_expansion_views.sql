-- Migration 0005: Create gold expansion views
-- Additional business-facing views for requirements 5 and 6

CREATE SCHEMA IF NOT EXISTS gold;

CREATE OR REPLACE VIEW gold.v_clin_duplicate_patients_exceptions AS
WITH patient_owner AS (
    SELECT
        patient.patient_id,
        patient.patient_name,
        patient.species,
        patient.date_of_birth,
        patient.clinic_id,
        patient.clinic_name,
        patient.owner_id,
        owner.first_name AS owner_first_name,
        owner.last_name AS owner_last_name,
        owner.phone_normalized
    FROM silver.stg_vet_patient AS patient
    LEFT JOIN silver.stg_vet_owner AS owner
        ON patient.owner_id = owner.owner_id
),
exact_match_signal AS (
    SELECT
        LEAST(left_side.patient_id, right_side.patient_id) AS patient_id_left,
        GREATEST(left_side.patient_id, right_side.patient_id) AS patient_id_right,
        'same_patient_name_species_birth_date' AS match_reason
    FROM patient_owner AS left_side
    INNER JOIN patient_owner AS right_side
        ON left_side.patient_id < right_side.patient_id
       AND left_side.patient_name = right_side.patient_name
       AND left_side.species = right_side.species
       AND left_side.date_of_birth = right_side.date_of_birth
),
shared_phone_signal AS (
    SELECT
        LEAST(left_side.patient_id, right_side.patient_id) AS patient_id_left,
        GREATEST(left_side.patient_id, right_side.patient_id) AS patient_id_right,
        'same_owner_phone_different_owner_records' AS match_reason
    FROM patient_owner AS left_side
    INNER JOIN patient_owner AS right_side
        ON left_side.patient_id < right_side.patient_id
       AND left_side.owner_id <> right_side.owner_id
       AND left_side.phone_normalized <> ''
       AND left_side.phone_normalized = right_side.phone_normalized
       AND left_side.patient_name = right_side.patient_name
       AND left_side.species = right_side.species
),
fuzzy_owner_last_name_signal AS (
    SELECT
        LEAST(left_side.patient_id, right_side.patient_id) AS patient_id_left,
        GREATEST(left_side.patient_id, right_side.patient_id) AS patient_id_right,
        'same_patient_name_similar_owner_last_name' AS match_reason
    FROM patient_owner AS left_side
    INNER JOIN patient_owner AS right_side
        ON left_side.patient_id < right_side.patient_id
       AND left_side.owner_id <> right_side.owner_id
       AND left_side.patient_name = right_side.patient_name
       AND left_side.species = right_side.species
       AND left_side.owner_last_name IS NOT NULL
       AND right_side.owner_last_name IS NOT NULL
       AND levenshtein(LOWER(left_side.owner_last_name), LOWER(right_side.owner_last_name)) <= 1
),
all_signals AS (
    SELECT * FROM exact_match_signal
    UNION ALL
    SELECT * FROM shared_phone_signal
    UNION ALL
    SELECT * FROM fuzzy_owner_last_name_signal
)
SELECT
    signals.patient_id_left,
    left_side.patient_name AS patient_name_left,
    left_side.species AS patient_species_left,
    left_side.date_of_birth AS patient_birth_date_left,
    left_side.clinic_id AS clinic_id_left,
    left_side.clinic_name AS clinic_name_left,
    left_side.owner_id AS owner_id_left,
    left_side.owner_last_name AS owner_last_name_left,
    signals.patient_id_right,
    right_side.patient_name AS patient_name_right,
    right_side.species AS patient_species_right,
    right_side.date_of_birth AS patient_birth_date_right,
    right_side.clinic_id AS clinic_id_right,
    right_side.clinic_name AS clinic_name_right,
    right_side.owner_id AS owner_id_right,
    right_side.owner_last_name AS owner_last_name_right,
    STRING_AGG(DISTINCT signals.match_reason, ' | ' ORDER BY signals.match_reason) AS match_reasons,
    COUNT(DISTINCT signals.match_reason) AS match_reason_count
FROM all_signals AS signals
INNER JOIN patient_owner AS left_side
    ON signals.patient_id_left = left_side.patient_id
INNER JOIN patient_owner AS right_side
    ON signals.patient_id_right = right_side.patient_id
GROUP BY
    signals.patient_id_left,
    left_side.patient_name,
    left_side.species,
    left_side.date_of_birth,
    left_side.clinic_id,
    left_side.clinic_name,
    left_side.owner_id,
    left_side.owner_last_name,
    signals.patient_id_right,
    right_side.patient_name,
    right_side.species,
    right_side.date_of_birth,
    right_side.clinic_id,
    right_side.clinic_name,
    right_side.owner_id,
    right_side.owner_last_name;

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
    clinic.clinic_area AS clinic_region,
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
