# site-dev: dev.neon1.tech

A private copy of neon1.tech for checking changes before they ship. It has its own bucket (`neon1-site-dev`), CloudFront distribution, and release store (`neon1-site-dev`). It shares only the live site's certificate and hosted zone, and, read-only, the assistant's API.

## How it stays private

Every behavior runs one CloudFront Function, `site/functions/dev-router.js`. `make dev-router` builds it from the live `site-router.js` and `portal-router.js` with `dev-gate.js` in front, so dev routes exactly like production. Without a valid `n1dev` cookie, every path returns a bare 404, and every response is `noindex`.

Sign-in takes two steps, so a leaked link alone gets nobody in:

1. The secret link, `https://dev.neon1.tech/__signin?k=<link key>`, sends the browser to the 1NEON dev sign-in on `auth-dev.neon1.tech`. A wrong key gets the same 404 as anything else.
2. A passkey or email code there. Only members of the pool's `dev-access` group get the 30-day cookie. Everyone else gets the 404.

Sign-in runs in `site/functions/dev-auth.mjs`, a Lambda@Edge function on `/__signin` and `/__auth` only (`sign-in.tf`). The CloudFront Function alone checks every other request.

| Key | Where | Changed by (neon1-site) | Effect of changing it |
|---|---|---|---|
| Link key | SSM `/neon1-site/dev/link_key` | `make dev-gate` | The old link stops working; signed-in devices stay signed in |
| Session key | SSM `/neon1-site/dev/session_key` and store key `session` | `make dev-signout` | Every device is signed out |

Access is the `dev-access` group. `make dev-allow EMAIL=...` in neon1-site adds someone, creating their dev account if needed. They then add a passkey at the link it prints. Removing someone from the group stops new sign-ins. Run `make dev-signout` too to sign out their devices at once.

`/__preview?b=<branch>` shows a branch preview, `/__preview` goes back to the dev release, and `/__signout` signs this device out.

## Store keys

| Key | Set by | Meaning |
|---|---|---|
| `release` | neon1-site dev workflow on the `dev` branch, or `make dev-push` on `dev` | The dev release folder |
| `history` | the same | The last 3 dev releases, for `make dev-rollback` |
| `branch:<name>` | any other branch, or a corpus branch run | A preview folder |
| `session` | `make dev-signout`, by hand | The cookie key, which never passes through Terraform or CI |

## First-time apply (by hand, `AWS_PROFILE=neon1`)

1. `make apply STACK=site-dev` with `-var portal=false`, or `terraform -chdir=site-dev apply -var portal=false -var expected_account_id=<id>`.
2. `make apply STACK=github`, which creates the dev deploy roles and `neon1-boundary-1neon-dev`. Set the role ARNs as the repository variable `AWS_DEV_DEPLOY_ROLE_ARN` in neon1-site and neon1-1NEON.
3. Apply neon1-1NEON `infra/envs/dev`.
4. `make apply STACK=site-dev` (portal on), which wires `/1NEON` to the dev backend.
5. In neon1-site, run `make dev-signout`, `make dev-gate`, and `make dev-allow EMAIL=<you>`, then `make dev-push` on the `dev` branch.
6. To make the $5 dev budget count, activate `Environment` as a cost allocation tag (Billing, then Cost allocation tags).

CI never applies this stack. The Terraform role has no access to its state.
