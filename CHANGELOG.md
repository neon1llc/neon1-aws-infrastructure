# Changelog

neon1-aws-infrastructure releases use `v0.MINOR.PATCH` until the first complete release, v1.0.0 (see neon1's [versioning standard](https://neon1.tech/knowledge/standards/versioning/)). Each release is tagged on the commit that was applied, once every stack's run has passed.

## v0.1.0 - 2026-11-10

The first tagged release. These stacks had been applied from main without version numbers; this entry records what that release holds.

### Added
- The site stack: neon1.tech on S3 and CloudFront with its certificate, DNS in Route 53, the www redirect, the knowledge center's routes, and the /faqs redirect.
- The github stack: GitHub OIDC roles for each repository, and the permission boundaries that limit the roles 1NEON and neon1-chat create, including Bedrock model access for Neo and the portal.
- Checks before any change: formatting, validation, lint, misconfiguration, secret scanning, and a refusal to plan or apply against any account but the expected one.
