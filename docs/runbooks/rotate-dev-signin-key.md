# Replace the dev sign-in link key

This runbook is intentionally gated. The current `neon1-site` `make dev-gate` command generates a new key, overwrites the active SSM parameter, and prints a private sign-in URL. Do not run it in a terminal, CI log, or shared session. The current stack contract has one active parameter (`/neon1-site/dev/signin_key`) and no supported staged-key consumer, so a no-overwrite rotation is not yet available.

1. Confirm the active key is suspected exposed and identify the owner of the `neon1-site` and `site-dev` changes. **Check:** Incident record contains exposure scope and authorized responders. **Undo:** No change.
2. Check whether the approved site release includes a staged-key reader and clipboard-only link command:
   ```sh
   rg -n 'dev-relink|dev-link|signin_key|next_signin_key' Makefile scripts
   ```
   **Check:** Proceed only when code and stack configuration support a second parameter and cutover without printing the link. Current source has no such staged-key contract. **Undo:** No change.
3. If staging support is absent, stop and implement/review it through the normal code path before rotating. Do not run `make dev-gate`, `make dev-relink`, or direct `aws ssm put-parameter` against the active name. **Check:** A plan and reviewed deployment show the new reader and parameter before cutover. **Undo:** Revert the code/configuration change before activation; do not overwrite the active key.
4. After the staged path is implemented and approved, follow that version's reviewed cutover instructions; verify old link rejection and existing signed-in session behavior without copying the link into logs. **Check:** A fresh private-browser test reaches the sign-in card and only authorized dev users can complete authentication. **Undo:** Restore the prior active parameter version and code pointer only if the exposure owner confirms it is safe; otherwise complete rotation and use `make dev-signout` to revoke sessions.

No key, token, or sign-in URL belongs in incident notes or shell history.
