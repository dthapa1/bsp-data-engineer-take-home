# Effort Map

This is a relative-effort view so we can sequence the work before implementation.

## Progress Snapshot

Completed:

- understanding requirements and repo
- selecting final scope
- fixing silver defects
- adding missing silver staging objects
- designing shared gold dimensions and facts
- implementing the shared gold migration and build flow
- building the requirement-specific analytical views
- adding iteration validators for Iteration 1, Iteration 2, and Iteration 3
- adding Soda contracts and a contract validator for Iteration 4
- adding AI guidance, submission notes, and final validation in Iteration 5
- expanding the warehouse to requirements 5 and 6 in Iteration 6
- adding a terminal dashboard and final documentation alignment in Iteration 7

Current highest-effort remaining work:

- final review only

## Chosen Scope

Selected requirements:

- 1. Clinic Appointment Volume
- 2. Referral Funnel Analysis
- 3. Revenue vs Budget
- 4. Provider Utilization
- 5. Duplicate Patient Detection
- 6. Patient Retention Cohort

## Flow

```text
Understand requirements and repo
  -> fix silver defects
  -> add missing silver staging objects
  -> design shared gold dimensions/facts
  -> implement gold migrations for requirements 1 to 4
  -> wire repeatable build flow
  -> add Soda contracts
  -> add AI/project documentation
  -> final validation and PR notes
```

## Current Position In Flow

```text
Understand requirements and repo [done]
  -> fix silver defects [done]
  -> add missing silver staging objects [done]
  -> design shared gold dimensions/facts [done]
  -> implement gold migrations for requirements 1 to 4 [done]
  -> wire repeatable build flow [done]
  -> add Soda contracts [done]
  -> add AI/project documentation [done]
  -> final validation and PR notes [done]
```

## Effort By Step

| Step | Why it matters | Effort | Risk |
|---|---|---:|---:|
| Understand requirements and repo | Prevents shallow or mis-scoped work | Low | Low |
| Fix silver defects | Gold quality depends on this | High | High |
| Add missing silver staging objects | Needed to support selected facts/views | Medium | Medium |
| Design shared gold dimensions/facts | Sets grain and joins correctly | High | High |
| Implement gold migrations | Converts design into durable warehouse objects | High | Medium |
| Wire repeatable build flow | Makes implementation usable and testable | Medium | Medium |
| Add Soda contracts | Demonstrates quality engineering | Medium | Low |
| Add AI/project documentation | Completes explicit deliverables | Low | Low |
| Final validation and PR notes | Makes the submission understandable | Medium | Low |

## Suggested Effort Labels

- Low: quick repo-local change, low ambiguity
- Medium: moderate modeling or testing work
- High: substantial design/debugging work or many downstream dependencies

## Dependency Notes

- Silver fixes should come before gold implementation.
- Shared dimensions/facts should come before analytical views.
- Contracts should follow object creation so they validate the final shape.
- Iteration documentation should be updated after every implementation step.

## Suggested Implementation Chunks

1. Silver stabilization
   Effort: High
   Status: Completed
   Summary: patient-clinic fix, referral cleanup approach, and missing silver objects.

2. Shared gold foundation
   Effort: High
   Status: Completed
   Summary: clinic dimension, patient SCD2 dimension, and core facts.

3. Requirement views
   Effort: High
   Status: Completed
   Includes:
   - clinic weekly operations
   - referral funnel monthly summary
   - revenue vs budget monthly
   - provider utilization weekly
   - duplicate patient exceptions
   - patient retention cohorts

4. Quality and documentation
   Effort: Medium
   Status: Completed
   Includes AI config, iteration notes, final validation, dashboard walkthrough, and submission steps.
