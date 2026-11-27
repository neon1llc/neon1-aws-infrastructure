# Account stack

The `account/` stack owns account-wide guardrails: the CloudTrail audit trail and protected log bucket, recurring and one-time spend budgets, cost anomaly notifications, and shared security controls defined in this directory. It does not own application resources or the Route 53 zone.

This stack is applied manually and is excluded from CI apply. Use the approved `neon1` profile, review the plan, and apply only after an owner approves the exact plan:

```sh
export AWS_PROFILE=neon1
make check
make plan STACK=account
make apply STACK=account
```

`make apply` applies the saved plan after checking the expected account. Do not remove the CloudTrail bucket's protections or weaken account guardrails to clear a failed plan. Confirm alarm email subscriptions from the intended inbox. For cost alerts, follow [the cost alarm runbook](../docs/runbooks/respond-cost-alarm.md).
