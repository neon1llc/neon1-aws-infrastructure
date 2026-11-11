# Changelog

neon1-aws-infrastructure releases use `v0.MINOR.PATCH` until the first complete release, v1.0.0 (see neon1's [versioning standard](https://neon1.tech/knowledge/standards/versioning/)). Each release is tagged on the commit that was applied, once every stack's run has passed.

## v0.2.0 - 2026-11-11

### Added
- The dns stack, applied on each push to main: a dated SOA serial, CAA records that let only Amazon's CA issue certificates for neon1.tech, TLS reporting to dmarc@, and a BIMI record for the neon1 logo.
- The apex mail records (Google Workspace MX, SPF, DKIM, and DMARC), created by hand when Workspace went live, are now managed in that stack.

### Changed
- DMARC for neon1.tech and its subdomains moves from monitoring (`p=none`) to `p=quarantine`, so mail that fails authentication goes to spam instead of the inbox.
- The Terraform role may change the dns stack's record names and types, and its state.

### Removed
- The `autodiscover` record left from an Amazon WorkMail setup that was never used; mail is on Google Workspace.

## v0.1.0 - 2026-11-10

The first tagged release. These stacks had been applied from main without version numbers; this entry records what that release holds.

### Added
- The site stack: neon1.tech on S3 and CloudFront with its certificate, DNS in Route 53, the www redirect, the knowledge center's routes, and the /faqs redirect.
- The github stack: GitHub OIDC roles for each repository, and the permission boundaries that limit the roles 1NEON and neon1-chat create, including Bedrock model access for Neo and the portal.
- Checks before any change: formatting, validation, lint, misconfiguration, secret scanning, and a refusal to plan or apply against any account but the expected one.

## Before v0.1.0

These stacks were applied from main for about a week before releases were tagged. These pre-releases mark the points in that history where a meaningful piece landed, on the commits as they are on main. They were tagged on 2026-11-10; the dates below are when each one was applied.

### v0.1.0-alpha.9 - 2026-11-10
- 1NEON's functions may call Neo's model on Bedrock.

### v0.1.0-alpha.8 - 2026-11-09
- The knowledge center's folder pages and the /faqs redirect, and the chat may call Qwen3 Next.

### v0.1.0-alpha.7 - 2026-11-09
- A refusal to plan or apply against any other account, model and service access scoped to each stack, pinned check images, and branch rules on main.

### v0.1.0-alpha.6 - 2026-11-08
- Permission boundaries for the roles 1NEON and neon1-chat create, and 1NEON's toll-free number and texting.

### v0.1.0-alpha.5 - 2026-11-08
- neon1.tech/chat/api routed to the assistant, and a Terraform role for neon1-chat.

### v0.1.0-alpha.4 - 2026-11-07
- A real 404 page, a strict CSP and shared headers, and www redirected to the apex.

### v0.1.0-alpha.3 - 2026-11-06
- The 1NEON portal at /1NEON with edge routing, and its Terraform role scoped to what it needs.

### v0.1.0-alpha.2 - 2026-11-05
- GitHub OIDC roles, checks, and the Terraform pipeline.

### v0.1.0-alpha.1 - 2026-11-05
- The Terraform stack for the neon1.tech static site.
