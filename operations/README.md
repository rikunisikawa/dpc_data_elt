# Operations Runbook (Minimal)

This runbook describes the first-response flow when the DPC learning pipeline raises an alert via the `dpc-learning-alerts` SNS topic. It focuses on quickly restoring the daily ELT batch while capturing enough context for downstream review.

## 1. Initial triage

1. Review the CloudWatch alarm notification to confirm the alarm name, environment, and triggering metric.
2. Inspect the Step Functions execution history for the `dpc-pipeline` state machine and pinpoint the failed step.
3. For data movement issues, open the latest Lambda logs (especially `dpc-validate-manifest` and `dpc-copy-raw`).
4. For transformation failures, review the ECS task logs emitted by the dbt runner.

## 2. Recovery actions

- **Step Functions failure**: Re-run the most recent execution from the Step Functions console after correcting the root cause. Use the same input payload when possible.
- **Corrupted S3 source object**: Replace or delete the problematic file under the `raw/` prefix, then re-trigger the pipeline.
- **dbt model failure**: Inspect the dbt logs under the ECS task output or `target/run_results.json`. Patch the SQL model locally, push a fix if required, and re-run the affected selector before re-running the full pipeline.
- **Redshift capacity pressure**: Check the Redshift Serverless workgroup activity. Abort runaway queries if necessary, temporarily raise the RPU limit, and schedule a follow-up optimization.

## 3. Post-incident follow-up

1. Document the event summary, owner, and resolution steps in the shared incident log.
2. Attach relevant CloudWatch log excerpts or dbt artifacts for later analysis.
3. Evaluate whether new tests, monitoring rules, or automation are needed.

## 4. Knowledge base ownership

We will decide between Confluence and Notion as the long-term runbook repository after the learning phase completes. Until then, keep this Markdown file updated alongside infrastructure changes so that operators have an up-to-date quick-reference.

## 5. Useful commands

- Re-run pipeline: `aws stepfunctions start-execution --state-machine-arn <arn> --input file://payload.json`
- Download latest dbt logs: `aws logs tail /aws/ecs/dpc-dbt-runner --since 1h`
- Replace S3 object: `aws s3 cp path/to/fix.csv s3://dpc-learning-data-<env>/raw/`
