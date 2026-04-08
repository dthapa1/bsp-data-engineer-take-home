-- Migration 0003: Create gold foundation objects
-- Shared dimensions and fact tables for requirements 1 to 4

CREATE SCHEMA IF NOT EXISTS gold;

CREATE TABLE IF NOT EXISTS gold.dim_core_clinic (
    clinic_sk UUID,
    clinic_id INTEGER,
    clinic_name VARCHAR,
    clinic_city VARCHAR,
    clinic_state VARCHAR,
    clinic_area VARCHAR,
    clinic_opened_date DATE,
    clinic_closed_date DATE,
    is_active BOOLEAN
);

CREATE TABLE IF NOT EXISTS gold.dim_clin_patient (
    patient_sk UUID,
    patient_id INTEGER,
    owner_id INTEGER,
    clinic_sk UUID,
    clinic_id INTEGER,
    patient_name VARCHAR,
    patient_species VARCHAR,
    patient_breed VARCHAR,
    patient_birth_date DATE,
    patient_sex VARCHAR,
    patient_weight_lbs DOUBLE,
    insurance_provider VARCHAR,
    registration_confirmed_date DATE,
    is_active BOOLEAN,
    effective_start TIMESTAMP,
    effective_end TIMESTAMP,
    is_current BOOLEAN,
    row_hash VARCHAR
);

CREATE TABLE IF NOT EXISTS gold.fact_clin_appointment (
    appointment_sk UUID,
    appointment_id INTEGER,
    patient_sk UUID,
    patient_id INTEGER,
    clinic_sk UUID,
    clinic_id INTEGER,
    provider_clinic_id VARCHAR,
    provider_id INTEGER,
    service_code VARCHAR,
    service_name VARCHAR,
    service_fee_amount DOUBLE,
    appointment_scheduled_date DATE,
    appointment_week_start_date DATE,
    appointment_scheduled_at TIMESTAMP,
    appointment_status VARCHAR,
    appointment_duration_minutes INTEGER,
    is_completed BOOLEAN,
    is_cancelled BOOLEAN,
    is_no_show BOOLEAN,
    has_provider_assigned BOOLEAN,
    is_created_after_schedule BOOLEAN,
    record_created_at TIMESTAMP,
    record_updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS gold.fact_fin_invoice (
    invoice_sk UUID,
    invoice_id INTEGER,
    appointment_id INTEGER,
    patient_sk UUID,
    patient_id INTEGER,
    clinic_sk UUID,
    clinic_id INTEGER,
    payment_type VARCHAR,
    invoice_status VARCHAR,
    amount_total DOUBLE,
    amount_insurance_paid DOUBLE,
    amount_patient_paid DOUBLE,
    invoice_documented_date DATE,
    invoice_month_start_date DATE,
    paid_documented_date DATE,
    is_paid_in_full BOOLEAN,
    is_partial_payment BOOLEAN,
    is_outstanding BOOLEAN,
    record_created_at TIMESTAMP,
    record_updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS gold.fact_pipe_referral_stage (
    referral_stage_sk UUID,
    referral_id INTEGER,
    patient_sk UUID,
    patient_id INTEGER,
    clinic_sk UUID,
    clinic_id INTEGER,
    referral_source VARCHAR,
    referral_stage VARCHAR,
    referral_stage_rank INTEGER,
    referral_stage_entered_at TIMESTAMP,
    referral_stage_exited_at TIMESTAMP,
    referral_stage_month_start_date DATE,
    days_in_stage INTEGER,
    record_created_at TIMESTAMP,
    record_updated_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS gold.ref_core_budget_target (
    budget_target_sk UUID,
    clinic_sk UUID,
    clinic_id INTEGER,
    budget_month_start_date DATE,
    target_revenue_amount DOUBLE,
    target_appointments_count INTEGER,
    target_new_patients_count INTEGER
);

-- PHASE_BREAK

DELETE FROM gold.fact_pipe_referral_stage;
DELETE FROM gold.fact_fin_invoice;
DELETE FROM gold.fact_clin_appointment;
DELETE FROM gold.ref_core_budget_target;
DELETE FROM gold.dim_clin_patient;
DELETE FROM gold.dim_core_clinic;

INSERT INTO gold.dim_core_clinic
SELECT
    uuid() AS clinic_sk,
    clinic.clinic_id,
    clinic.clinic_name,
    clinic.city AS clinic_city,
    clinic.state AS clinic_state,
    clinic.area AS clinic_area,
    clinic.opened_date AS clinic_opened_date,
    clinic.closed_date AS clinic_closed_date,
    clinic.closed_date IS NULL AS is_active
FROM silver.stg_vet_clinic AS clinic
WHERE clinic.is_current = TRUE
  AND clinic.clinic_id = clinic.reporting_clinic_id;

INSERT INTO gold.dim_clin_patient
SELECT
    uuid() AS patient_sk,
    patient.patient_id,
    patient.owner_id,
    clinic.clinic_sk,
    patient.clinic_id,
    patient.patient_name,
    patient.species AS patient_species,
    patient.breed AS patient_breed,
    patient.date_of_birth AS patient_birth_date,
    patient.sex AS patient_sex,
    patient.weight_lbs AS patient_weight_lbs,
    patient.insurance_provider,
    patient.registration_date AS registration_confirmed_date,
    patient.is_active,
    CURRENT_TIMESTAMP AS effective_start,
    NULL AS effective_end,
    TRUE AS is_current,
    md5(
        COALESCE(CAST(patient.owner_id AS VARCHAR), '')
        || '|' || COALESCE(CAST(patient.clinic_id AS VARCHAR), '')
        || '|' || COALESCE(patient.patient_name, '')
        || '|' || COALESCE(patient.species, '')
        || '|' || COALESCE(patient.breed, '')
        || '|' || COALESCE(CAST(patient.date_of_birth AS VARCHAR), '')
        || '|' || COALESCE(patient.sex, '')
        || '|' || COALESCE(CAST(patient.weight_lbs AS VARCHAR), '')
        || '|' || COALESCE(patient.insurance_provider, '')
        || '|' || COALESCE(CAST(patient.registration_date AS VARCHAR), '')
        || '|' || COALESCE(CAST(patient.is_active AS VARCHAR), '')
    ) AS row_hash
FROM silver.stg_vet_patient AS patient
LEFT JOIN gold.dim_core_clinic AS clinic
    ON patient.clinic_id = clinic.clinic_id;

INSERT INTO gold.fact_clin_appointment
SELECT
    uuid() AS appointment_sk,
    appointment.appointment_id,
    patient.patient_sk,
    appointment.patient_id,
    clinic.clinic_sk,
    appointment.clinic_id,
    provider.provider_clinic_id,
    appointment.provider_id,
    appointment.service_code,
    appointment.service_name,
    appointment.service_fee AS service_fee_amount,
    appointment.appointment_date AS appointment_scheduled_date,
    appointment.appointment_week_start AS appointment_week_start_date,
    appointment.scheduled_at AS appointment_scheduled_at,
    appointment.status AS appointment_status,
    appointment.duration_minutes AS appointment_duration_minutes,
    appointment.is_completed,
    appointment.is_cancelled,
    appointment.is_no_show,
    appointment.has_provider_assigned,
    appointment.is_created_after_schedule,
    appointment.created_at AS record_created_at,
    appointment.updated_at AS record_updated_at
FROM silver.stg_vet_appointment AS appointment
LEFT JOIN gold.dim_clin_patient AS patient
    ON appointment.patient_id = patient.patient_id
   AND patient.is_current = TRUE
LEFT JOIN gold.dim_core_clinic AS clinic
    ON appointment.clinic_id = clinic.clinic_id
LEFT JOIN silver.stg_vet_provider AS provider
    ON appointment.provider_id = provider.provider_id
   AND appointment.clinic_id = provider.clinic_id;

INSERT INTO gold.fact_fin_invoice
SELECT
    uuid() AS invoice_sk,
    invoice.invoice_id,
    invoice.appointment_id,
    patient.patient_sk,
    invoice.patient_id,
    clinic.clinic_sk,
    invoice.clinic_id,
    invoice.payment_type,
    invoice.status AS invoice_status,
    invoice.amount AS amount_total,
    invoice.insurance_paid AS amount_insurance_paid,
    invoice.patient_paid AS amount_patient_paid,
    invoice.invoice_date AS invoice_documented_date,
    invoice.invoice_month_start AS invoice_month_start_date,
    invoice.paid_date AS paid_documented_date,
    invoice.is_paid_in_full,
    invoice.is_partial_payment,
    invoice.is_outstanding,
    invoice.created_at AS record_created_at,
    invoice.updated_at AS record_updated_at
FROM silver.stg_vet_invoice AS invoice
LEFT JOIN gold.dim_clin_patient AS patient
    ON invoice.patient_id = patient.patient_id
   AND patient.is_current = TRUE
LEFT JOIN gold.dim_core_clinic AS clinic
    ON invoice.clinic_id = clinic.clinic_id;

INSERT INTO gold.fact_pipe_referral_stage
SELECT
    uuid() AS referral_stage_sk,
    referral.referral_id,
    patient.patient_sk,
    referral.patient_id,
    clinic.clinic_sk,
    referral.clinic_id,
    referral.referral_source,
    referral.stage AS referral_stage,
    referral.stage_rank AS referral_stage_rank,
    referral.stage_entered_at AS referral_stage_entered_at,
    referral.stage_exited_at AS referral_stage_exited_at,
    DATE_TRUNC('month', CAST(referral.stage_entered_at AS DATE)) AS referral_stage_month_start_date,
    referral.days_in_stage,
    referral.created_at AS record_created_at,
    referral.updated_at AS record_updated_at
FROM silver.stg_vet_referral AS referral
LEFT JOIN gold.dim_clin_patient AS patient
    ON referral.patient_id = patient.patient_id
   AND patient.is_current = TRUE
LEFT JOIN gold.dim_core_clinic AS clinic
    ON referral.clinic_id = clinic.clinic_id;

INSERT INTO gold.ref_core_budget_target
SELECT
    uuid() AS budget_target_sk,
    clinic.clinic_sk,
    budget.clinic_id,
    budget.budget_month_start AS budget_month_start_date,
    budget.target_revenue AS target_revenue_amount,
    budget.target_appointments AS target_appointments_count,
    budget.target_new_patients AS target_new_patients_count
FROM silver.stg_vet_budget_target AS budget
LEFT JOIN gold.dim_core_clinic AS clinic
    ON budget.clinic_id = clinic.clinic_id;
