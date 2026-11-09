# github

Lets GitHub Actions reach AWS without stored keys. It holds the account's GitHub OIDC provider, five roles (each trusted only for pushes to `main` of one repository, matched by owner and repository ID as well as name), and the permission boundaries those roles must put on any function role they create.

| Role | Repository | What it can do |
|---|---|---|
| `github-neon1-site-deploy` | neon1llc/neon1-site | List and write the site bucket, and invalidate the site distribution. |
| `github-neon1-infra-terraform` | neon1llc/neon1-aws-infrastructure | Manage the `site` stack, read and write its state, and read this stack so CI can plan it. |
| `github-1neon-deploy` | neon1llc/neon1-1NEON | Write the app's files under `1NEON/`, upload code to the two `1neon-prod-*` functions, and invalidate the CDN. |
| `github-1neon-terraform` | neon1llc/neon1-1NEON | Apply 1NEON's `infra/envs/prod`: its buckets, table, functions, user pool, HTTP API, schedule, alarms, texting number, and mail identity, each scoped to 1NEON's names or IDs. |
| `github-neon1-chat-terraform` | neon1llc/neon1-chat | Apply the assistant's `infra/`, which also ships its code: table, function, HTTP API, alarms, and budget. |

Roles that create function roles may only do so with their boundary attached (`boundaries.tf`), and can never remove it. The IDs that scope the user pool, the HTTP APIs, and the assistant's model are variables with today's values (`portal_user_pool_id`, `portal_api_id`, `chat_api_id`, `chat_model_id`). If one of those resources is ever replaced, put its new ID there and apply this stack before the other stack touches it.

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
  arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

After applying, store the role ARNs as repository variables:

```bash
gh variable set AWS_DEPLOY_ROLE_ARN --repo neon1llc/neon1-site \
  --body "$(terraform -chdir=github output -raw site_deploy_role_arn)"
gh variable set AWS_TERRAFORM_ROLE_ARN --repo neon1llc/neon1-aws-infrastructure \
  --body "$(terraform -chdir=github output -raw terraform_role_arn)"
```

The bucket and distribution IDs default to the `site` stack's current values. Update them here if either one is replaced.
