# github

Lets GitHub Actions reach AWS without stored keys. It holds the account's GitHub OIDC provider and two roles, each trusted only for pushes to `main` of one repository:

- `github-neon1-site-deploy` for `neon1llc/neon1-site`. It can list and write objects in the site bucket and create or read invalidations on the site distribution.
- `github-neon1-infra-terraform` for `neon1llc/neon1-aws-infrastructure`. It can manage the `site` stack's resources, read and write that stack's state, and read this stack so CI can plan it.

The Terraform role can't change IAM. That keeps a bad workflow from granting itself more access, and it means this stack is always applied by hand:

```bash
export AWS_PROFILE=neon1
make plan STACK=github
make apply STACK=github
```

An account can have only one provider for `token.actions.githubusercontent.com`. If one already exists, import it before the first apply:

```bash
terraform -chdir=github init
terraform -chdir=github import aws_iam_openid_connect_provider.github \
  arn:aws:iam::353036311148:oidc-provider/token.actions.githubusercontent.com
```

After applying, store the role ARNs as repository variables:

```bash
gh variable set AWS_DEPLOY_ROLE_ARN --repo neon1llc/neon1-site \
  --body "$(terraform -chdir=github output -raw site_deploy_role_arn)"
gh variable set AWS_TERRAFORM_ROLE_ARN --repo neon1llc/neon1-aws-infrastructure \
  --body "$(terraform -chdir=github output -raw terraform_role_arn)"
```

The bucket and distribution IDs default to the `site` stack's current values. Update them here if either one is replaced.
