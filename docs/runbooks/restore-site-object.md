# Restore a versioned site object

Use this when one shared object at the site root is damaged or missing. For a whole release, use [roll back a site release](rollback-site-release.md). Requires the approved `neon1` profile and the exact object key and version from incident evidence.

1. Confirm the affected URL and object key from the response and the current site manifest. Set the key without a leading slash:
   ```sh
   export AWS_PROFILE=neon1
   KEY='path/to/object'
   aws s3api head-object --bucket neon1-public-website --key "$KEY"
   ```
   **Check:** The key is in the shared root, not under `releases/`, and the failure is reproducible. **Undo:** No change; unset with `unset KEY`.
2. List available object versions and choose the known-good version from before the incident:
   ```sh
   aws s3api list-object-versions --bucket neon1-public-website --prefix "$KEY" --query "Versions[?Key=='$KEY'].[VersionId,LastModified,IsLatest]" --output table
   ```
   **Check:** A version matches the expected key and timestamp. **Undo:** No change; stop if no verified version exists.
3. Copy that version onto the current key, preserving the prior current version in the versioned bucket:
   ```sh
   VERSION_ID='verified-version-id'
   aws s3api copy-object --bucket neon1-public-website --key "$KEY" --copy-source "neon1-public-website/$KEY?versionId=$VERSION_ID" --metadata-directive COPY
   ```
   **Check:** `head-object` shows the restored content metadata; fetch the public URL and verify status and content. **Undo:** Copy the previously current version back using the same command and its recorded version ID.
4. Invalidate the exact public path if CloudFront still serves the old object:
   ```sh
   aws cloudfront create-invalidation --distribution-id "$SITE_DISTRIBUTION_ID" --paths "/$KEY"
   ```
   **Check:** Wait for invalidation completion and request the URL again. **Undo:** Invalidation cannot be recalled; restore the prior object version if needed and issue a new invalidation.

Do not use this procedure for immutable `releases/<id>/` objects; those are retained for the release rollback procedure.
