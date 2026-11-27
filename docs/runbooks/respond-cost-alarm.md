# Respond to a cost alarm

1. Read the notification and identify the affected budget or anomaly window. Open the billing and cost console under the approved account/profile; do not change a budget threshold during triage. **Check:** Confirm period, service grouping, and whether the amount is forecast or incurred. **Undo:** No change.
2. Compare the affected period with the prior period and inspect usage by service, region, and tag. **Check:** Capture the likely source and any expected release or one-time charge. **Undo:** No change.
3. If spend appears unexpected, page the service owner and apply an already-approved workload stop or scaling control. For Terraform-managed resources, prepare a plan and obtain owner review before any apply. **Check:** Usage trend or resource state reflects the approved mitigation. **Undo:** Restore the documented prior setting after the owner confirms it is safe.
4. Record notification time, verified spend, likely cause, mitigation, and follow-up owner. **Check:** The incident entry links to evidence without credentials or customer data. **Undo:** Amend incorrect notes; do not delete the audit record.
