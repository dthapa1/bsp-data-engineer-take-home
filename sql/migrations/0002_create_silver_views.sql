-- Migration 0002: Create silver staging views
-- Cleaned, typed, business-ready views over bronze tables

CREATE SCHEMA IF NOT EXISTS silver;

CREATE OR REPLACE VIEW silver.stg_vet_clinic AS
WITH renamed_clinic_map AS (
    SELECT
        old_clinic.clinic_id AS source_clinic_id,
        COALESCE(new_clinic.clinic_id, old_clinic.clinic_id) AS reporting_clinic_id,
        COALESCE(new_clinic.clinic_name, old_clinic.clinic_name) AS reporting_clinic_name,
        COALESCE(new_clinic.city, old_clinic.city) AS reporting_city,
        COALESCE(new_clinic.state, old_clinic.state) AS reporting_state,
        COALESCE(new_clinic.area, old_clinic.area) AS reporting_area
    FROM bronze.vet_clinic AS old_clinic
    LEFT JOIN bronze.vet_clinic AS new_clinic
        ON old_clinic.renamed_to = new_clinic.clinic_name
)
SELECT
    clinic.clinic_id,
    clinic.clinic_name,
    clinic.city,
    clinic.state,
    clinic.area,
    CAST(clinic.opened_date AS DATE) AS opened_date,
    CAST(clinic.closed_date AS DATE) AS closed_date,
    COALESCE(clinic.is_current, TRUE) AS is_current,
    clinic.renamed_to,
    CAST(clinic.updated_at AS TIMESTAMP) AS updated_at,
    clinic_map.reporting_clinic_id,
    clinic_map.reporting_clinic_name,
    clinic_map.reporting_city,
    clinic_map.reporting_state,
    clinic_map.reporting_area
FROM bronze.vet_clinic AS clinic
INNER JOIN renamed_clinic_map AS clinic_map
    ON clinic.clinic_id = clinic_map.source_clinic_id;

CREATE OR REPLACE VIEW silver.stg_vet_owner AS
WITH latest_owner AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY owner_id
            ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
        ) AS rn
    FROM bronze.vet_owner
)
SELECT
    owner_id,
    first_name,
    last_name,
    email,
    phone,
    REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '', 'g') AS phone_normalized,
    city,
    state,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(updated_at AS TIMESTAMP) AS updated_at
FROM latest_owner
WHERE rn = 1;

CREATE OR REPLACE VIEW silver.stg_vet_patient AS
WITH latest_patient AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY patient_id
            ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
        ) AS rn
    FROM bronze.vet_patient
)
SELECT
    patient.patient_id,
    patient.owner_id,
    patient.patient_name,
    patient.species,
    patient.breed,
    CAST(patient.date_of_birth AS DATE) AS date_of_birth,
    patient.sex,
    patient.weight_lbs,
    patient.clinic_id AS source_clinic_id,
    COALESCE(clinic.reporting_clinic_id, patient.clinic_id) AS clinic_id,
    COALESCE(clinic.reporting_clinic_name, clinic.clinic_name) AS clinic_name,
    COALESCE(clinic.reporting_area, clinic.area) AS clinic_area,
    COALESCE(clinic.reporting_state, clinic.state) AS clinic_state,
    patient.insurance_provider,
    CAST(patient.registration_date AS DATE) AS registration_date,
    COALESCE(patient.is_active, TRUE) AS is_active,
    CAST(patient.created_at AS TIMESTAMP) AS created_at,
    CAST(patient.updated_at AS TIMESTAMP) AS updated_at
FROM latest_patient AS patient
LEFT JOIN silver.stg_vet_clinic AS clinic
    ON patient.clinic_id = clinic.clinic_id
WHERE patient.rn = 1;

CREATE OR REPLACE VIEW silver.stg_vet_provider AS
WITH latest_provider_assignment AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY provider_id, clinic_id
            ORDER BY updated_at DESC NULLS LAST, hire_date DESC NULLS LAST
        ) AS rn
    FROM bronze.vet_provider
)
SELECT
    provider.provider_id,
    provider.provider_id || '-' || COALESCE(CAST(provider.clinic_id AS VARCHAR), 'unknown') AS provider_clinic_id,
    provider.first_name,
    provider.last_name,
    provider.full_name,
    provider.credentials,
    provider.specialty,
    provider.clinic_id AS source_clinic_id,
    COALESCE(clinic.reporting_clinic_id, provider.clinic_id) AS clinic_id,
    COALESCE(clinic.reporting_clinic_name, clinic.clinic_name) AS clinic_name,
    COALESCE(clinic.reporting_area, clinic.area) AS clinic_area,
    COALESCE(clinic.reporting_state, clinic.state) AS clinic_state,
    CAST(provider.hire_date AS DATE) AS hire_date,
    CAST(provider.termination_date AS DATE) AS termination_date,
    COALESCE(provider.is_active, TRUE) AS is_active,
    CAST(provider.updated_at AS TIMESTAMP) AS updated_at
FROM latest_provider_assignment AS provider
LEFT JOIN silver.stg_vet_clinic AS clinic
    ON provider.clinic_id = clinic.clinic_id
WHERE provider.rn = 1;

CREATE OR REPLACE VIEW silver.stg_vet_appointment AS
WITH latest_appointment AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY appointment_id
            ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
        ) AS rn
    FROM bronze.vet_appointment
)
SELECT
    appointment.appointment_id,
    appointment.patient_id,
    appointment.provider_id,
    appointment.clinic_id AS source_clinic_id,
    COALESCE(clinic.reporting_clinic_id, appointment.clinic_id) AS clinic_id,
    COALESCE(clinic.reporting_clinic_name, clinic.clinic_name) AS clinic_name,
    COALESCE(clinic.reporting_area, clinic.area) AS clinic_area,
    COALESCE(clinic.reporting_state, clinic.state) AS clinic_state,
    appointment.service_code,
    appointment.service_name,
    appointment.service_fee,
    CAST(appointment.appointment_date AS DATE) AS appointment_date,
    CAST(DATE_TRUNC('week', CAST(appointment.appointment_date AS DATE)) AS DATE) AS appointment_week_start,
    CAST(appointment.scheduled_at AS TIMESTAMP) AS scheduled_at,
    appointment.status,
    appointment.duration_minutes,
    appointment.status = 'completed' AS is_completed,
    appointment.status = 'cancelled' AS is_cancelled,
    appointment.status = 'no_show' AS is_no_show,
    appointment.provider_id IS NOT NULL AS has_provider_assigned,
    CAST(appointment.created_at AS TIMESTAMP) > CAST(appointment.scheduled_at AS TIMESTAMP) AS is_created_after_schedule,
    CAST(appointment.created_at AS TIMESTAMP) AS created_at,
    CAST(appointment.updated_at AS TIMESTAMP) AS updated_at
FROM latest_appointment AS appointment
LEFT JOIN silver.stg_vet_clinic AS clinic
    ON appointment.clinic_id = clinic.clinic_id
WHERE appointment.rn = 1
  AND CAST(appointment.appointment_date AS DATE) >= COALESCE(clinic.opened_date, CAST(appointment.appointment_date AS DATE));

CREATE OR REPLACE VIEW silver.stg_vet_invoice AS
WITH latest_invoice AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY invoice_id
            ORDER BY updated_at DESC NULLS LAST, created_at DESC NULLS LAST
        ) AS rn
    FROM bronze.vet_invoice
)
SELECT
    invoice.invoice_id,
    invoice.appointment_id,
    invoice.patient_id,
    invoice.clinic_id AS source_clinic_id,
    COALESCE(clinic.reporting_clinic_id, invoice.clinic_id) AS clinic_id,
    COALESCE(clinic.reporting_clinic_name, clinic.clinic_name) AS clinic_name,
    COALESCE(clinic.reporting_area, clinic.area) AS clinic_area,
    COALESCE(clinic.reporting_state, clinic.state) AS clinic_state,
    invoice.service_code,
    invoice.amount,
    invoice.payment_type,
    invoice.insurance_paid,
    invoice.patient_paid,
    CAST(invoice.invoice_date AS DATE) AS invoice_date,
    CAST(DATE_TRUNC('month', CAST(invoice.invoice_date AS DATE)) AS DATE) AS invoice_month_start,
    CAST(invoice.paid_date AS DATE) AS paid_date,
    invoice.status,
    invoice.status = 'paid' AS is_paid_in_full,
    invoice.status = 'partial' AS is_partial_payment,
    invoice.status = 'outstanding' AS is_outstanding,
    CAST(invoice.created_at AS TIMESTAMP) AS created_at,
    CAST(invoice.updated_at AS TIMESTAMP) AS updated_at
FROM latest_invoice AS invoice
LEFT JOIN silver.stg_vet_clinic AS clinic
    ON invoice.clinic_id = clinic.clinic_id
WHERE invoice.rn = 1;

CREATE OR REPLACE VIEW silver.stg_vet_budget_target AS
SELECT
    clinic_id,
    clinic_name,
    year,
    month,
    MAKE_DATE(year, month, 1) AS budget_month_start,
    target_revenue,
    target_appointments,
    target_new_patients
FROM bronze.vet_budget_target;

CREATE OR REPLACE VIEW silver.stg_vet_referral AS
WITH typed_referral AS (
    SELECT
        referral.referral_id,
        referral.patient_id,
        referral.clinic_id AS source_clinic_id,
        COALESCE(clinic.reporting_clinic_id, referral.clinic_id) AS clinic_id,
        COALESCE(clinic.reporting_clinic_name, clinic.clinic_name) AS clinic_name,
        referral.referral_source,
        referral.stage,
        CASE referral.stage
            WHEN 'inquiry' THEN 1
            WHEN 'consultation' THEN 2
            WHEN 'registered' THEN 3
            WHEN 'active' THEN 4
            WHEN 'churned' THEN 5
            ELSE NULL
        END AS stage_rank,
        CAST(referral.stage_entered_at AS TIMESTAMP) AS stage_entered_at,
        CAST(referral.stage_exited_at AS TIMESTAMP) AS stage_exited_at,
        CAST(referral.created_at AS TIMESTAMP) AS created_at,
        CAST(referral.updated_at AS TIMESTAMP) AS updated_at
    FROM bronze.vet_referral AS referral
    LEFT JOIN silver.stg_vet_clinic AS clinic
        ON referral.clinic_id = clinic.clinic_id
),
valid_referral_window AS (
    SELECT
        referral_id,
        patient_id,
        source_clinic_id,
        clinic_id,
        clinic_name,
        referral_source,
        stage,
        stage_rank,
        stage_entered_at,
        stage_exited_at,
        created_at,
        updated_at
    FROM typed_referral
    WHERE stage_rank IS NOT NULL
      AND (
          stage_exited_at IS NULL
          OR stage_exited_at >= stage_entered_at
      )
),
collapsed_stage AS (
    SELECT
        referral_id,
        patient_id,
        source_clinic_id,
        clinic_id,
        clinic_name,
        referral_source,
        stage,
        stage_rank,
        MIN(stage_entered_at) AS stage_entered_at,
        MAX(stage_exited_at) AS stage_exited_at,
        MIN(created_at) AS created_at,
        MAX(updated_at) AS updated_at
    FROM valid_referral_window
    GROUP BY
        referral_id,
        patient_id,
        source_clinic_id,
        clinic_id,
        clinic_name,
        referral_source,
        stage,
        stage_rank
),
sequenced_referral AS (
    SELECT
        *,
        LAG(stage_entered_at) OVER (
            PARTITION BY referral_id
            ORDER BY stage_rank
        ) AS previous_stage_entered_at
    FROM collapsed_stage
)
SELECT
    referral_id,
    patient_id,
    source_clinic_id,
    clinic_id,
    clinic_name,
    referral_source,
    stage,
    stage_rank,
    stage_entered_at,
    stage_exited_at,
    CASE
        WHEN stage_exited_at IS NOT NULL
        THEN DATEDIFF('day', stage_entered_at, stage_exited_at)
        ELSE NULL
    END AS days_in_stage,
    created_at,
    updated_at
FROM sequenced_referral
WHERE previous_stage_entered_at IS NULL
   OR stage_entered_at >= previous_stage_entered_at;
