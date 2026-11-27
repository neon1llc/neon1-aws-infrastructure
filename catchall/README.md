# Catchall stack

The `catchall/` stack serves the not-found page for other `neon1.tech` hostnames through a wildcard record and its own small CloudFront distribution. It owns only those catchall resources; the shared Route 53 zone is referenced, not managed wholesale.

This stack is applied manually. CI may plan it, but must not apply it:

```sh
export AWS_PROFILE=neon1
make check
make plan STACK=catchall
make apply STACK=catchall
```

Review the saved plan for wildcard DNS or distribution changes before applying. Verify an unknown hostname reaches the not-found page after propagation. For site-hostname DNS or certificate incidents, see [the DNS and certificate runbook](../docs/runbooks/recover-dns-certificate.md).
