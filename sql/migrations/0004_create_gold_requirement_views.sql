-- Migration 0004: Create gold analytical views
-- Business-facing views for all 6 stakeholder requirements

CREATE SCHEMA IF NOT EXISTS gold;

CREATE OR REPLACE VIEW gold.v_ops_clinic_appointment_weekly AS
WITH weekly_clinic AS (
    SELECT
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area AS clinic_region,
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
    weekly_clinic.clinic_region,
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

CREATE OR REPLACE VIEW gold.v_pipe_referral_funnel_monthly AS
WITH referral_anchor AS (
    SELECT
        referral_id,
        DATE_TRUNC(
            'month',
            MIN(CASE WHEN referral_stage_rank = 1 THEN CAST(referral_stage_entered_at AS DATE) END)
        ) AS referral_month_start_date
    FROM gold.fact_pipe_referral_stage
    GROUP BY referral_id
),
referral_rollup AS (
    SELECT
        referral.referral_id,
        referral.patient_id,
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area AS clinic_region,
        clinic.clinic_area,
        referral.referral_source,
        anchor.referral_month_start_date,
        MAX(CASE WHEN referral.referral_stage = 'inquiry' THEN 1 ELSE 0 END) AS reached_inquiry,
        MAX(CASE WHEN referral.referral_stage = 'consultation' THEN 1 ELSE 0 END) AS reached_consultation,
        MAX(CASE WHEN referral.referral_stage = 'registered' THEN 1 ELSE 0 END) AS reached_registered,
        MAX(CASE WHEN referral.referral_stage = 'active' THEN 1 ELSE 0 END) AS reached_active,
        MAX(CASE WHEN referral.referral_stage = 'churned' THEN 1 ELSE 0 END) AS reached_churned
    FROM gold.fact_pipe_referral_stage AS referral
    INNER JOIN gold.dim_core_clinic AS clinic
        ON referral.clinic_sk = clinic.clinic_sk
    INNER JOIN referral_anchor AS anchor
        ON referral.referral_id = anchor.referral_id
    GROUP BY
        referral.referral_id,
        referral.patient_id,
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area,
        referral.referral_source,
        anchor.referral_month_start_date
),
referral_stage_days AS (
    SELECT
        clinic.clinic_id,
        referral.referral_source,
        anchor.referral_month_start_date,
        MEDIAN(CASE WHEN referral.referral_stage = 'inquiry' THEN referral.days_in_stage END) AS median_days_inquiry_stage,
        MEDIAN(CASE WHEN referral.referral_stage = 'consultation' THEN referral.days_in_stage END) AS median_days_consultation_stage,
        MEDIAN(CASE WHEN referral.referral_stage = 'registered' THEN referral.days_in_stage END) AS median_days_registration_stage,
        MEDIAN(CASE WHEN referral.referral_stage = 'active' THEN referral.days_in_stage END) AS median_days_active_stage
    FROM gold.fact_pipe_referral_stage AS referral
    INNER JOIN gold.dim_core_clinic AS clinic
        ON referral.clinic_sk = clinic.clinic_sk
    INNER JOIN referral_anchor AS anchor
        ON referral.referral_id = anchor.referral_id
    GROUP BY
        clinic.clinic_id,
        referral.referral_source,
        anchor.referral_month_start_date,
        referral.referral_id
),
referral_stage_days_grouped AS (
    SELECT
        clinic_id,
        referral_source,
        referral_month_start_date,
        MEDIAN(median_days_inquiry_stage) AS median_days_inquiry_stage,
        MEDIAN(median_days_consultation_stage) AS median_days_consultation_stage,
        MEDIAN(median_days_registration_stage) AS median_days_registration_stage,
        MEDIAN(median_days_active_stage) AS median_days_active_stage
    FROM referral_stage_days
    GROUP BY clinic_id, referral_source, referral_month_start_date
)
SELECT
    referral_rollup.clinic_id,
    referral_rollup.clinic_name,
    referral_rollup.clinic_region,
    referral_rollup.clinic_area,
    referral_rollup.referral_source,
    referral_rollup.referral_month_start_date,
    SUM(referral_rollup.reached_inquiry) AS inquiries_count,
    SUM(
        CASE
            WHEN referral_rollup.reached_inquiry = 1
             AND referral_rollup.reached_consultation = 1
            THEN 1
            ELSE 0
        END
    ) AS consultations_count,
    SUM(
        CASE
            WHEN referral_rollup.reached_inquiry = 1
             AND referral_rollup.reached_consultation = 1
             AND referral_rollup.reached_registered = 1
            THEN 1
            ELSE 0
        END
    ) AS registrations_count,
    SUM(
        CASE
            WHEN referral_rollup.reached_inquiry = 1
             AND referral_rollup.reached_consultation = 1
             AND referral_rollup.reached_registered = 1
             AND referral_rollup.reached_active = 1
            THEN 1
            ELSE 0
        END
    ) AS active_patients_count,
    SUM(referral_rollup.reached_churned) AS churned_patients_count,
    CASE
        WHEN SUM(referral_rollup.reached_inquiry) > 0
        THEN CAST(SUM(referral_rollup.reached_consultation) AS DOUBLE) / SUM(referral_rollup.reached_inquiry)
        ELSE NULL
    END AS inquiry_to_consultation_rate,
    CASE
        WHEN SUM(referral_rollup.reached_consultation) > 0
        THEN CAST(SUM(referral_rollup.reached_registered) AS DOUBLE) / SUM(referral_rollup.reached_consultation)
        ELSE NULL
    END AS consultation_to_registration_rate,
    CASE
        WHEN SUM(referral_rollup.reached_registered) > 0
        THEN CAST(SUM(referral_rollup.reached_active) AS DOUBLE) / SUM(referral_rollup.reached_registered)
        ELSE NULL
    END AS registration_to_active_rate,
    days.median_days_inquiry_stage,
    days.median_days_consultation_stage,
    days.median_days_registration_stage,
    days.median_days_active_stage
FROM referral_rollup
LEFT JOIN referral_stage_days_grouped AS days
    ON referral_rollup.clinic_id = days.clinic_id
   AND referral_rollup.referral_source = days.referral_source
   AND referral_rollup.referral_month_start_date = days.referral_month_start_date
WHERE referral_rollup.referral_month_start_date IS NOT NULL
GROUP BY
    referral_rollup.clinic_id,
    referral_rollup.clinic_name,
    referral_rollup.clinic_region,
    referral_rollup.clinic_area,
    referral_rollup.referral_source,
    referral_rollup.referral_month_start_date,
    days.median_days_inquiry_stage,
    days.median_days_consultation_stage,
    days.median_days_registration_stage,
    days.median_days_active_stage;

CREATE OR REPLACE VIEW gold.v_fin_revenue_budget_monthly AS
WITH monthly_revenue AS (
    SELECT
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area AS clinic_region,
        clinic.clinic_area,
        clinic.clinic_state,
        invoice.invoice_month_start_date,
        SUM(invoice.amount_total) AS total_revenue_amount,
        SUM(CASE WHEN invoice.payment_type = 'insurance' THEN invoice.amount_total ELSE 0 END) AS insurance_revenue_amount,
        SUM(CASE WHEN invoice.payment_type = 'self_pay' THEN invoice.amount_total ELSE 0 END) AS self_pay_revenue_amount,
        SUM(invoice.amount_insurance_paid + invoice.amount_patient_paid) AS total_paid_amount,
        COUNT(*) AS invoice_count
    FROM gold.fact_fin_invoice AS invoice
    INNER JOIN gold.dim_core_clinic AS clinic
        ON invoice.clinic_sk = clinic.clinic_sk
    GROUP BY
        clinic.clinic_id,
        clinic.clinic_name,
        clinic.clinic_area,
        clinic.clinic_state,
        invoice.invoice_month_start_date
)
SELECT
    monthly_revenue.clinic_id,
    monthly_revenue.clinic_name,
    monthly_revenue.clinic_region,
    monthly_revenue.clinic_area,
    monthly_revenue.clinic_state,
    monthly_revenue.invoice_month_start_date,
    monthly_revenue.invoice_count,
    monthly_revenue.total_revenue_amount,
    monthly_revenue.insurance_revenue_amount,
    monthly_revenue.self_pay_revenue_amount,
    budget.target_revenue_amount,
    monthly_revenue.total_revenue_amount - budget.target_revenue_amount AS revenue_variance_amount,
    CASE
        WHEN budget.target_revenue_amount <> 0
        THEN monthly_revenue.total_revenue_amount / budget.target_revenue_amount
        ELSE NULL
    END AS revenue_to_target_ratio,
    CASE
        WHEN monthly_revenue.total_revenue_amount <> 0
        THEN monthly_revenue.total_paid_amount / monthly_revenue.total_revenue_amount
        ELSE NULL
    END AS collection_rate
FROM monthly_revenue
LEFT JOIN gold.ref_core_budget_target AS budget
    ON monthly_revenue.clinic_id = budget.clinic_id
   AND monthly_revenue.invoice_month_start_date = budget.budget_month_start_date;

CREATE OR REPLACE VIEW gold.v_ops_provider_utilization_weekly AS
SELECT
    provider.provider_clinic_id,
    provider.provider_id,
    provider.full_name AS provider_name,
    provider.specialty AS provider_specialty,
    clinic.clinic_id,
    clinic.clinic_name,
    clinic.clinic_area AS clinic_region,
    clinic.clinic_area,
    clinic.clinic_state,
    appointment.appointment_week_start_date,
    appointment.service_code,
    appointment.service_name,
    COUNT(*) AS appointments_count,
    SUM(CASE WHEN appointment.is_completed THEN appointment.appointment_duration_minutes ELSE 0 END) AS completed_minutes,
    SUM(CASE WHEN appointment.is_completed THEN 1 ELSE 0 END) AS completed_appointments,
    COUNT(*) < 15 AS is_below_minimum_threshold
FROM gold.fact_clin_appointment AS appointment
INNER JOIN silver.stg_vet_provider AS provider
    ON appointment.provider_clinic_id = provider.provider_clinic_id
INNER JOIN gold.dim_core_clinic AS clinic
    ON appointment.clinic_sk = clinic.clinic_sk
WHERE appointment.has_provider_assigned = TRUE
  AND appointment.is_cancelled = FALSE
GROUP BY
    provider.provider_clinic_id,
    provider.provider_id,
    provider.full_name,
    provider.specialty,
    clinic.clinic_id,
    clinic.clinic_name,
    clinic.clinic_area,
    clinic.clinic_state,
    appointment.appointment_week_start_date,
    appointment.service_code,
    appointment.service_name;

-- Requirements 5 and 6: Duplicate patient detection and patient retention cohort

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
