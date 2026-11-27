# Respond to an uptime alert

1. Confirm the alert is current by requesting the affected public endpoint from an independent network and checking the alert's region and timestamp. **Check:** Record HTTP status, latency, and whether the symptom is global or regional. **Undo:** No change.
2. Inspect the latest deployment and service health for the affected surface. For `neon1.tech`, compare the live release with the release history; for an API, use that service's health dashboard and owner runbook. **Check:** Identify a recent change or dependency failure. **Undo:** No change.
3. Mitigate using the owning service's rollback procedure. For the public site, use [rollback-site-release.md](rollback-site-release.md); do not edit DNS or security policy as a first response. **Check:** Repeat the independent request and verify recovery across affected paths. **Undo:** Reapply the prior release only after the incident owner confirms it is safe.
4. Keep the incident owner updated with impact, mitigation, and next update time. **Check:** Alert clears and the service owner confirms recovery. **Undo:** Correct the incident timeline if a report was inaccurate.
