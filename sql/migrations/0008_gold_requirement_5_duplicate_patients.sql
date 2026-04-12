-- Migration 0008: Requirement 5 - Duplicate Patient Detection
-- Identifies duplicate patient records across the network using 3 detection signals:
-- 1) Exact match (name + species + birth date)
-- 2) Shared phone (same owner contact across different owner records)
-- 3) Fuzzy owner last name (Levenshtein distance <= 1)

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
