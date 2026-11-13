# site-dev: dev.neon1.tech

A private copy of neon1.tech for looking at changes before they ship. It has its own bucket (`neon1-site-dev`), CloudFront distribution, and release store (`neon1-site-dev`). The live site shares only its certificate, its hosted zone, and, read-only, the assistant's API.

## How it stays private

Every behavior runs one CloudFront Function, `site/functions/dev-router.js`. `make dev-router` builds it from the live `site-router.js` and `portal-router.js` with `dev-gate.js` in front, so dev routes exactly like production. The gate works like this:

- `https://dev.neon1.tech/__signin?k=<key>` sets a signed, HttpOnly cookie that lasts 30 days. The key lives only in the store's `gate` key. `make dev-gate` in neon1-site sets a new one and prints the link once, which signs every device out.
- Without a valid cookie, every path returns a bare 404. Every response is also `noindex`.
- `/__preview?b=<branch>` shows a branch preview, `/__preview` goes back to the dev release, and `/__signout` signs this device out.

## Store keys

| Key | Set by | Meaning |
|---|---|---|
| `release` | neon1-site dev workflow on the `dev` branch, or `make dev-push` on `dev` | The dev release folder |
| `history` | the same | The last 3 dev releases, for `make dev-rollback` |
| `branch:<name>` | any other branch, or a corpus branch run | A preview folder |
| `gate` | `make dev-gate`, by hand | The sign-in key; it never passes through Terraform or CI |

## First-time apply (by hand, `AWS_PROFILE=neon1`)

1. `make apply STACK=site-dev` with `-var portal=false`, or `terraform -chdir=site-dev apply -var portal=false -var expected_account_id=<id>`.
2. `make apply STACK=github`, which creates the dev deploy roles and `neon1-boundary-1neon-dev`. Set the role ARNs as the repository variable `AWS_DEV_DEPLOY_ROLE_ARN` in neon1-site and neon1-1NEON.
3. Apply neon1-1NEON `infra/envs/dev`.
4. `make apply STACK=site-dev` (portal on), which wires `/1NEON` to the dev backend.
5. In neon1-site, run `make dev-gate`, then `make dev-push` on the `dev` branch.
6. To make the $5 dev budget count, activate `Environment` as a cost allocation tag (Billing, then Cost allocation tags).

CI never applies this stack. The Terraform role has no access to its state.
