# Roll back the public site release

Use this when a site release is broken and the previous known-good release should serve. Rollback changes the release pointer; it does not rewrite release files.

1. From a clean `neon1-site` checkout, set the production profile and inspect the target release history. Do not run `make rollback` yet:
   ```sh
   export AWS_PROFILE=neon1
   aws cloudfront describe-key-value-store --name neon1-site-release --output json
   ```
   **Check:** Confirm the approved production profile and incident owner; use the release history and incident record to choose target. **Undo:** No change.
2. Confirm the target release folder exists in the production bucket:
   ```sh
   aws s3api list-objects-v2 --bucket neon1-public-website --prefix "releases/$RELEASE/" --max-items 5
   ```
   **Check:** Objects exist for the exact approved release ID. **Undo:** No change; stop if missing or ambiguous.
3. Switch to the previous release, or specify the approved release explicitly:
   ```sh
   make rollback RELEASE="$RELEASE"
   ```
   **Check:** The command reports the selected release; verify the affected pages and `https://neon1.tech/` after propagation. **Undo:** Run `make rollback RELEASE="$PREVIOUS_RELEASE"` with the recorded release ID.
4. Record impact, start/end time, release IDs, and verification in the incident record. **Check:** A second operator can identify the live release and follow-up owner. **Undo:** Correct the record if any value was wrong; do not change AWS state to fix a documentation typo.

The command uses the existing release history and compare-and-swap key-value-store update. Avoid manual pointer edits unless the application owner directs a recovery outside this runbook.
