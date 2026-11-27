# Recover DNS and certificates

1. Identify the failing hostname and inspect DNS answers and certificate dates from outside the AWS account:
   ```sh
   dig +short "$HOSTNAME" A
   dig +short "$HOSTNAME" AAAA
   openssl s_client -connect "$HOSTNAME:443" -servername "$HOSTNAME" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
   ```
   **Check:** Determine whether the fault is DNS resolution, CloudFront routing, or certificate validity. **Undo:** No change.
2. Inspect the owning stack (`dns` for zone-wide records, `site` for apex/`www` and certificate) and create a fresh plan:
   ```sh
   export AWS_PROFILE=neon1
   export EXPECTED_ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
   make plan STACK="$STACK"
   ```
   **Check:** Plan contains only the intended record or certificate change; stop on unexpected replacement or destroy. **Undo:** No change; discard the local plan.
3. Have the stack owner review and apply only the approved plan using the repository's normal release path. The `dns` stack owns shared mail and CAA records; `site` owns its certificate and site records. **Check:** Re-run DNS and TLS probes after propagation. **Undo:** Revert the reviewed source change and follow the normal apply process; DNS rollback may require propagation time.
4. Record resolver results, certificate dates, plan summary, change owner, and recovery time. **Check:** All required hostnames resolve and serve a valid certificate. **Undo:** Correct the record if evidence changes; preserve the audit trail.
