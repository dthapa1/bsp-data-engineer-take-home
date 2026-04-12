-- Migration 0006: Requirement 3 - Revenue vs Budget
-- Monthly clinic revenue with insurance/self-pay breakdown, targets, variance, and collection rates

CREATE OR REPLACE VIEW gold.v_fin_revenue_budget_monthly AS
WITH monthly_revenue AS (
    SELECT
        clinic.clinic_id,
        clinic.clinic_name,
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
