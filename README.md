# neon1 AWS Infrastructure — 1NEON / Org Baseline (Terraform, AWS Provider v6)

This repository holds the **AWS infrastructure as code** for the neon1 organization and the 1NEON portal.  
It’s designed to be **SSO-first**, **provider v6-ready**, and **state-safe** using an S3 backend.

---

## TL;DR — Daily Flow

```bash
# 0) Authenticate (SSO) and set env
aws sso login --profile default
export AWS_PROFILE=default
export AWS_SDK_LOAD_CONFIG=1

# 1) Go to the stack you want (example: org/)
cd neon1-aws-infrastructure/org

# 2) Terraform lifecycle
terraform init -upgrade -reconfigure
terraform plan
terraform apply

# 3) If state is out of sync with reality (imports)
#    Use the import mappings in this README (S3, Route53, KMS, CloudTrail, Config)
```

> **Important**  
> - We use the **AWS provider `~> 6.0`** (v6 API).  
> - Hosted zones are **read-only** (we use **data sources** with explicit `zone_id` to avoid ambiguity).  
> - Public website S3 follows v6 split resources: **bucket**, **ownership_controls**, **public_access_block**,
>   **versioning**, **server_side_encryption_configuration**.

---

## Repository Structure (high level)

```
neon1-aws-infrastructure/
├── org/                  # Org-level baseline: S3 audit, KMS, CloudTrail, Config, DNS (data only)
│   ├── backend.tf        # S3 remote state (one key per env)
│   ├── providers.tf      # AWS provider (~> 6.0), default + us_east_1 alias, SSO-safe
│   ├── dns.tf            # Route53 hosted zone data sources (zone_id-based)
│   ├── website.tf        # Public website S3 & DNS records (managed here)
│   ├── main.tf           # KMS, Config, etc.
│   ├── variables.tf      # zone_id vars, region, etc.
│   └── outputs.tf
└── projects/
    └── 1NEON/            # 1NEON portal: dev / staging / prod envs
        ├── dev/
        ├── staging/
        └── prod/
```

---

## Providers & Auth

- **Provider**: `hashicorp/aws ~> 6.0`
- **SSO-first**: no `profile =` in provider blocks; creds come from env/config (SSO + `credential_process` if used).
- If you need the `aws-sso-util` helper for stubborn shells, use:
  ```bash
  aws sso login --profile default
  export AWS_PROFILE=default
  export AWS_SDK_LOAD_CONFIG=1
  ```

**us-east-1 alias** is used for ACM/CloudFront: `provider "aws" { alias = "us_east_1" ... }`

---

## Remote State (S3) & Workspaces

`org/backend.tf` points to S3 (e.g., `neon1-tfstate`, key `org/dev/terraform.tfstate`).

**Migrate local → S3** if ever needed:
```bash
terraform init -migrate-state        # use ONLY this (not with -reconfigure)
# When prompted, answer: yes
```

**Reconfigure only** (already remote, changed config):
```bash
terraform init -reconfigure
```

---

## Route53 (Read-only, no more “multiple zones matched”)

We **do not** manage hosted zones as resources. We use **data sources** keyed by **zone_id**:

```hcl
data "aws_route53_zone" "tech"      { zone_id = var.zone_id_tech }
data "aws_route53_zone" "co"        { zone_id = var.zone_id_co }
data "aws_route53_zone" "dev"       { zone_id = var.zone_id_dev }
data "aws_route53_zone" "solutions" { zone_id = var.zone_id_solutions }
```

Outputs/locals use `data.aws_route53_zone.*` (not `aws_route53_zone.*`).

**If you must locate by name**, add a trailing dot and `private_zone=false`:
```hcl
data "aws_route53_zone" "tech" { name = "neon1.tech."; private_zone = false }
```

---

## Public Website (S3 v6 split resources)

With provider v6, S3 sub-resources are separate. We declare all of them:

```hcl
resource "aws_s3_bucket" "website" { bucket = var.website_bucket_name }

resource "aws_s3_bucket_public_access_block" "website" {
  bucket                  = aws_s3_bucket.website.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
    bucket_key_enabled = true
  }
}
```

### Import IDs for S3 sub-resources (all = bucket name)
```bash
terraform import aws_s3_bucket.website                                   neon1-public-website
terraform import aws_s3_bucket_public_access_block.website                neon1-public-website
terraform import aws_s3_bucket_ownership_controls.website                 neon1-public-website
terraform import aws_s3_bucket_versioning.website                         neon1-public-website
terraform import aws_s3_bucket_server_side_encryption_configuration.website neon1-public-website
```

---

## Common Imports (one-liners)

### Route53 **records** (format: `ZONEID_NAME_TYPE`)
```bash
terraform import 'aws_route53_record.apex_a["neon1.tech"]'         Z009089523ACQHD83TGQI_neon1.tech_A
terraform import 'aws_route53_record.apex_aaaa["neon1.tech"]'      Z009089523ACQHD83TGQI_neon1.tech_AAAA
terraform import 'aws_route53_record.www_cnames["www.neon1.tech"]' Z009089523ACQHD83TGQI_www.neon1.tech_CNAME
# repeat for co/dev/solutions using their zone ids
```

### KMS (audit)
```bash
terraform import aws_kms_key.audit  arn:aws:kms:us-east-1:353036311148:key/<KEY-ID>
terraform import aws_kms_alias.audit alias/neon1-audit-kms
```

### CloudTrail (org)
```bash
terraform import 'module.cloudtrail.aws_cloudtrail.this' org-trail-2025
```

### AWS Config
```bash
terraform import aws_config_configuration_recorder.main default
terraform import aws_config_delivery_channel.main         default
```

### CloudFront OAC
```bash
terraform import aws_cloudfront_origin_access_control.oac <OAC_ID>
```

### ACM (us-east-1)
```bash
terraform import aws_acm_certificate.site arn:aws:acm:us-east-1:353036311148:certificate/<CERT-UUID>
# validation is usually recreated; import not required
```

---

## Troubleshooting Cheatsheet

### 1) `InvalidClientTokenId` (SSO)
Cause: Terraform not using your SSO credentials.

**Fix**
```bash
aws sso login --profile default
export AWS_PROFILE=default
export AWS_SDK_LOAD_CONFIG=1
terraform init -reconfigure
terraform plan
```
Avoid `profile = "default"` **inside provider blocks**; rely on env/config.

### 2) Local state → S3 remote (Plan wants to create everything)
Cause: TF lost state (running local).

**Fix**
```bash
# ensure backend.tf exists with s3 bucket/key
terraform init -migrate-state
```

### 3) Provider decode errors (`unsupported attribute "account_id"/"region"/"arn"`)
Cause: Mixed provider versions wrote different identity blobs.

**Fastest Fix (what worked here)**  
Upgraded to **AWS provider v6** and refactored state/HCL to v6 schema.

### 4) `-migrate-state` vs `-reconfigure`
They are **mutually exclusive**. Use **one** at a time.

### 5) “Multiple Route53 hosted zones matched”
Use `zone_id` in `data.aws_route53_zone.*` **or** `name="neon1.tech."` with `private_zone=false`.

### 6) `Invalid target address` during import
The **resource must exist in HCL** with that address. Declare the resource (names must match), then import.

### 7) Outputs became `null` after refresh-only
State no longer had those resources or outputs referenced resource types not in code.  
Re-import TF-owned resources, and convert hosted zones to **data** sources.

### 8) Serial conflict on `terraform state push`
Re-pull, bump `.serial += 1`, push again (or `-force` if you’re sure):
```bash
terraform state pull > s.json
# edit s.json (if needed), bump serial, then:
terraform state push s.json
```

### 9) Bash / macOS oddities
- Use **Homebrew Bash** shebang for scripts using associative arrays:
  ```bash
  #!/usr/local/bin/bash
  ```

---

## Deploy Script (infra-only)

In `scripts/deploy.sh` (infra-only deploy, SSO-safe, multi-project aware):
```bash
#!/usr/local/bin/bash
set -euo pipefail

ENVIRONMENT="${1:-dev}"
PROJECT="${2:-org}"
PROFILE="${AWS_PROFILE:-default}"
export AWS_PROFILE="$PROFILE"
export AWS_SDK_LOAD_CONFIG=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../ && pwd)"
INFRA_DIR="$ROOT_DIR/neon1-aws-infrastructure"
TARGET_DIR="$INFRA_DIR/${PROJECT == "org" ? "org" : "projects/$PROJECT/$ENVIRONMENT"}"

log(){ printf "\033[1;32m%s\033[0m\n" "$*"; }

# Ensure SSO
if ! aws sts get-caller-identity --profile "$PROFILE" >/dev/null 2>&1; then
  log "🔐 Logging in AWS SSO…"
  aws sso login --profile "$PROFILE"
fi

log "⚙️  Terraform: $PROJECT ($ENVIRONMENT)"
cd "$TARGET_DIR"
terraform init -reconfigure
terraform workspace select "$ENVIRONMENT" 2>/dev/null || terraform workspace new "$ENVIRONMENT"
terraform apply -auto-approve
```

> **Note**: Site deploy is handled in the **neon1-site** repos; this script is infra-only.

---

## Case Studies (What broke + How we fixed it)

### CS1 — `InvalidClientTokenId` (Terraform + SSO)
- **Symptom**: `GetCallerIdentity` 403, TF not using SSO tokens.
- **Fix**: `aws sso login --profile default`, export `AWS_PROFILE=default`, `AWS_SDK_LOAD_CONFIG=1`, remove `profile` from providers.

### CS2 — Associative arrays in scripts on macOS
- **Symptom**: `declare: -A: invalid option`.
- **Fix**: Use `#!/usr/local/bin/bash` (Homebrew Bash ≥ 5).

### CS3 — Local state accidentally used (plan wants to create 60+ resources)
- **Symptom**: `Plan: 67 to add…`.
- **Fix**: Add `backend "s3" { … }`, run `terraform init -migrate-state`.

### CS4 — Provider decode identity errors (`account_id`, `region`, `arn`, etc.)
- **Symptom**: `failed to decode identity: unsupported attribute …`.
- **Fix**: Upgraded to **AWS provider v6**, refactored S3 sub-resources, rebuilt state via imports where needed.

### CS5 — `-migrate-state` vs `-reconfigure`
- **Symptom**: “Invalid init options” when used together.
- **Fix**: Use **one** flag at a time.

### CS6 — Route53 “multiple hosted zones matched”
- **Cause**: Name-only data lookup with multiple public+private zones.
- **Fix**: Use **zone_id** in `data.aws_route53_zone.*` (most reliable), or `name = "neon1.tech."` + `private_zone = false`.

### CS7 — Outputs/locals referenced `resource` instead of `data`
- **Symptom**: “Reference to undeclared resource… Did you mean data…?”
- **Fix**: Convert to `data.aws_route53_zone.*` everywhere.

### CS8 — S3 imports: “Invalid target address”
- **Cause**: Resource block didn’t exist in HCL yet.
- **Fix**: Declare resource with matching address (v6 split sub-resources), then `terraform import …`.

### CS9 — State serial conflict during `state push`
- **Fix**: Re-pull → bump `.serial += 1` → push (or `-force` if sure).

### CS10 — ACM/CloudFront/KMS/Config rehydration
- **Symptom**: Missing in state or changed out of band.
- **Fix**: `terraform state rm <addr>` → `terraform import <addr> <real-id>`, or remove from code if no longer managed.

### CS11 — Site deploy pushed `node_modules` to S3
- **Fix**: Deploy from **build output** only (`out/`, `.next/`, `dist/`, `build`), exclude `node_modules` and `src/app/client/*`.

### CS12 — “Unknown provider function”, `provider::aws::caller_identity()` in console
- **Cause**: TF console doesn’t provide that helper.
- **Fix**: Use CLI: `aws sts get-caller-identity`.

---

## Keep it Future‑Proof
- Commit `.terraform.lock.hcl` to pin **provider v6** across machines.
- Always keep `backend.tf` and S3 state keys per env (`org/dev`, `org/prod`, etc.).
- Prefer **data** for pre-existing infra (hosted zones), and only `resource` for what we truly own.
- For SSO environments, don’t set `profile` in providers — use the env: `AWS_PROFILE` + `AWS_SDK_LOAD_CONFIG=1`.

---

## Need exact import lines?
Ping the exact **resource address** (left side in TF, e.g., `module.audit_bucket.aws_s3_bucket_versioning.this`), and the real AWS ID/ARN/name. Use the mapping above, and I can give you the precise two commands (`state rm` + `import`) to fix it in one shot.