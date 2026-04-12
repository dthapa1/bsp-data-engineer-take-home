-- Migration 0005: Requirement 2 - Referral Funnel Analysis
-- Tracks patient journey through referral pipeline: inquiry → consultation → registration → active
-- Includes conversion rates at each stage and median time spent in each stage

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
    referral_rollup.clinic_area,
    referral_rollup.referral_source,
    referral_rollup.referral_month_start_date,
    days.median_days_inquiry_stage,
    days.median_days_consultation_stage,
    days.median_days_registration_stage,
    days.median_days_active_stage;
