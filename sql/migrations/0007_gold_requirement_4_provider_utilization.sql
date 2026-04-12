-- Migration 0007: Requirement 4 - Provider Utilization
-- Weekly provider appointments by service with utilization flagging for underutilization

CREATE OR REPLACE VIEW gold.v_ops_provider_utilization_weekly AS
SELECT
    provider.provider_clinic_id,
    provider.provider_id,
    provider.full_name AS provider_name,
    provider.specialty AS provider_specialty,
    clinic.clinic_id,
    clinic.clinic_name,
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
