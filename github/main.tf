# github/main.tf - GitHub Actions access to AWS through OIDC: no stored keys, and each role
# trusts only one repository's main branch.


# The account ID for ARNs, and the repository each role trusts
data "aws_caller_identity" "current" {}


locals {
  account   = data.aws_caller_identity.current.account_id
  oidc_host = "token.actions.githubusercontent.com"

  repos = {
    site_deploy      = "${var.github_org}/${var.site_repo}"
    terraform        = "${var.github_org}/${var.infra_repo}"
    portal_deploy    = var.portal_subject
    portal_terraform = var.portal_subject
    chat_terraform   = var.chat_subject
  }

  site_bucket_arn = "arn:aws:s3:::${var.site_bucket}"
  state_arn       = "arn:aws:s3:::${var.state_bucket}"
}


# One provider per account. AWS checks GitHub's certificate itself, so no thumbprint
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}


# Pushes to main only. Pull requests, other branches and environments get a
# different subject claim and can't assume any of these roles
data "aws_iam_policy_document" "trust" {
  for_each = local.repos

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${each.value}:ref:refs/heads/main"]
    }
  }
}


# --- Site deploy: sync the bucket, switch the live release, and invalidate the distribution, nothing else ---


resource "aws_iam_role" "site_deploy" {
  name               = "github-neon1-site-deploy"
  description        = "GitHub Actions deploys for ${local.repos.site_deploy}"
  assume_role_policy = data.aws_iam_policy_document.trust["site_deploy"].json
}


# List and write the site bucket, switch the live release, and invalidate the distribution
data "aws_iam_policy_document" "site_deploy" {
  statement {
    sid       = "ListSite"
    actions   = ["s3:ListBucket"]
    resources = [local.site_bucket_arn]
  }

  statement {
    sid       = "WriteSite"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.site_bucket_arn}/*"]
  }

  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
    resources = ["arn:aws:cloudfront::${local.account}:distribution/${var.site_distribution_id}"]
  }

  # Find the release store by name and switch the live release (site stack's neon1-site-release).
  # The store's ID is generated, so the grant names the account's stores; the site's is the only one
  statement {
    sid = "SwitchRelease"
    actions = [
      "cloudfront:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:DescribeKeyValueStore",
      "cloudfront-keyvaluestore:GetKey",
      "cloudfront-keyvaluestore:ListKeys",
      "cloudfront-keyvaluestore:PutKey",
      "cloudfront-keyvaluestore:UpdateKeys",
    ]
    resources = ["arn:aws:cloudfront::${local.account}:key-value-store/*"]
  }
}


# Attach the deploy policy to the site deploy role
resource "aws_iam_role_policy" "site_deploy" {
  name   = "deploy"
  role   = aws_iam_role.site_deploy.id
  policy = data.aws_iam_policy_document.site_deploy.json
}


# --- Terraform: apply the site stack, plan this one ---


# This stack is applied by hand. The role can read IAM but not change it, so a
# compromised workflow can't widen its own access
resource "aws_iam_role" "terraform" {
  name               = "github-neon1-infra-terraform"
  description        = "GitHub Actions Terraform runs for ${local.repos.terraform}"
  assume_role_policy = data.aws_iam_policy_document.trust["terraform"].json
}


# What the site stack manages, plus read access to plan this one
data "aws_iam_policy_document" "terraform" {
  # State and lock files: read and write for site, read and lock only for github
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_arn]
  }

  statement {
    sid       = "StateApplied"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/site/*", "${local.state_arn}/dns/*"]
  }

  statement {
    sid       = "StateGithubRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_arn}/github/*"]
  }

  statement {
    sid       = "StateGithubLock"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_arn}/github/*.tflock"]
  }

  # Bucket settings only. Objects belong to the site deploy role
  statement {
    sid = "SiteBucket"
    actions = [
      "s3:CreateBucket",
      "s3:ListBucket",
      "s3:GetBucket*",
      "s3:PutBucket*",
      "s3:DeleteBucketPolicy",
      "s3:GetAccelerateConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
    ]
    resources = [local.site_bucket_arn]
  }

  # List and Get calls don't support resource scoping in CloudFront
  statement {
    sid       = "CloudFrontRead"
    actions   = ["cloudfront:Get*", "cloudfront:List*"]
    resources = ["*"]
  }

  statement {
    # Distributions, origin access, edge functions, and header policies in this account
    sid = "CloudFrontWrite"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:CreateFunction",
      "cloudfront:DescribeFunction",
      "cloudfront:UpdateFunction",
      "cloudfront:PublishFunction",
      "cloudfront:DeleteFunction",
      "cloudfront:CreateOriginRequestPolicy",
      "cloudfront:UpdateOriginRequestPolicy",
      "cloudfront:DeleteOriginRequestPolicy",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
    ]
    resources = [
      "arn:aws:cloudfront::${local.account}:distribution/*",
      "arn:aws:cloudfront::${local.account}:origin-access-control/*",
      "arn:aws:cloudfront::${local.account}:function/*",
      "arn:aws:cloudfront::${local.account}:response-headers-policy/*",
      "arn:aws:cloudfront::${local.account}:origin-request-policy/*",
    ]
  }

  # The site's release store (the live release's name; the site deploy writes its keys, not Terraform)
  statement {
    sid = "CloudFrontReleaseStore"
    actions = [
      "cloudfront:CreateKeyValueStore",
      "cloudfront:DescribeKeyValueStore",
      "cloudfront:UpdateKeyValueStore",
      "cloudfront:DeleteKeyValueStore",
      # The provider's default tags are written on create
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
    ]
    resources = ["arn:aws:cloudfront::${local.account}:key-value-store/*"]
  }

  # The 1NEON and neon1-chat stacks publish their origins (and the chat's edge secret) here
  statement {
    sid     = "PortalParameters"
    actions = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      "arn:aws:ssm:us-east-1:${local.account}:parameter/1neon/prod/*",
      "arn:aws:ssm:us-east-1:${local.account}:parameter/neon1-chat/prod/*",
    ]
  }

  statement {
    # Certificates: requesting can't be scoped, managing is limited to this account
    sid       = "CertificateRequest"
    actions   = ["acm:RequestCertificate", "acm:ListCertificates"]
    resources = ["*"]
  }

  statement {
    sid = "Certificate"
    actions = [
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:DeleteCertificate",
    ]
    resources = ["arn:aws:acm:us-east-1:${local.account}:certificate/*"]
  }

  statement {
    # Read the hosted zone and follow record changes
    sid       = "ZoneRead"
    actions   = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
  }

  # Site aliases and certificate validation only. The dns stack's records are
  # the DnsRecords statement below
  statement {
    sid       = "ZoneRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["A", "AAAA", "CNAME"]
    }
  }

  # The dns stack: the SOA, CAA, and apex mail records, on these names only
  statement {
    sid       = "DnsRecords"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["SOA", "CAA", "MX", "TXT"]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsNormalizedRecordNames"
      values = [
        "neon1.tech",
        "google._domainkey.neon1.tech",
        "_dmarc.neon1.tech",
        "_mta-sts.neon1.tech",
        "_gh-neon1llc-o.neon1.tech",
        "_smtp._tls.neon1.tech",
        "default._bimi.neon1.tech",
      ]
    }
  }

  # The dns stack reads DNSSEC signing (turned on by hand) and its KMS key, without changing them
  statement {
    sid       = "DnssecRead"
    actions   = ["route53:GetDNSSEC"]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]
  }

  statement {
    sid       = "DnssecKeyRead"
    actions   = ["kms:ListAliases", "kms:DescribeKey"]
    resources = ["*"]
  }

  # The dns stack's DNSSEC alarms
  statement {
    sid       = "DnsAlarms"
    actions   = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource"]
    resources = ["arn:aws:cloudwatch:us-east-1:${local.account}:alarm:neon1-dns-*"]
  }

  statement {
    sid       = "AlarmsRead"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }

  statement {
    sid       = "ZoneChanges"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  # Read this stack's own resources so CI can plan it
  statement {
    sid = "IamRead"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = [
      aws_iam_openid_connect_provider.github.arn,
      "arn:aws:iam::${local.account}:role/github-neon1-*",
      "arn:aws:iam::${local.account}:role/github-1neon-*",
    ]
  }

  # The permission boundaries this stack defines, read-only, so CI can plan them too
  statement {
    sid       = "BoundaryRead"
    actions   = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListPolicyTags"]
    resources = ["arn:aws:iam::${local.account}:policy/neon1-boundary-*"]
  }
}


# Attach the Terraform policy to the infrastructure role
resource "aws_iam_role_policy" "terraform" {
  name   = "terraform"
  role   = aws_iam_role.terraform.id
  policy = data.aws_iam_policy_document.terraform.json
}
