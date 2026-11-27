#!/usr/bin/env python3

# scripts/test-iam-guards.py - Check Terraform IAM trust and boundary source.

"""Check Terraform IAM trust and permission ceilings without AWS credentials."""

from pathlib import Path
import re
import sys


# Return one policy statement so checks stay scoped to the intended SID.
def statement_block(policy: str, sid: str) -> str:
    match = re.search(
        rf"statement\s*\{{(?:(?!\n\s*statement\s*\{{).)*?sid\s*=\s*\"{re.escape(sid)}\"(?:(?!\n\s*statement\s*\{{).)*",
        policy,
        re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"missing IAM statement {sid}")
    return match.group(0)


# Fail when role trust stops using the configured exact main-branch subject.
def check_trust(source: str) -> None:
    required_roles = {
        "site_deploy": "aws_iam_role.site_deploy",
        "terraform": "aws_iam_role.terraform",
        "portal_deploy": "aws_iam_role.portal_deploy",
        "portal_terraform": "aws_iam_role.portal_terraform",
        "chat_terraform": "aws_iam_role.chat_terraform",
    }
    for key, role in required_roles.items():
        expected = f'assume_role_policy = data.aws_iam_policy_document.trust["{key}"].json'
        if expected not in source:
            raise AssertionError(f"{role} must use its repository trust policy")

    trust = source.split('data "aws_iam_policy_document" "trust"', 1)[1]
    if not re.search(r'actions\s*=\s*\["sts:AssumeRoleWithWebIdentity"\]', trust):
        raise AssertionError("GitHub roles must use web identity trust")
    if not re.search(r'variable\s*=\s*"\$\{local\.oidc_host\}:aud"', trust):
        raise AssertionError("GitHub role trust must constrain the token audience")
    if not re.search(r'variable\s*=\s*"\$\{local\.oidc_host\}:sub"', trust):
        raise AssertionError("GitHub role trust must constrain the subject")
    if not re.search(r'values\s*=\s*\["repo:\$\{each\.value\}:ref:refs/heads/main"\]', trust):
        raise AssertionError("GitHub role trust must match an exact main-branch subject")
    if len(re.findall(r'test\s*=\s*"StringEquals"', trust)) < 2:
        raise AssertionError("GitHub role trust must compare both audience and subject exactly")


# Fail when an app function boundary gains wildcard actions or loses its resource scope.
def check_boundaries(source: str) -> None:
    portal = source.split('data "aws_iam_policy_document" "boundary_portal"', 1)[1]
    chat = source.split('data "aws_iam_policy_document" "boundary_chat"', 1)[1]
    portal_table = statement_block(portal, "Table")
    portal_objects = statement_block(portal, "Objects")
    chat_counters = statement_block(chat, "Counters")

    required = [
        ('actions   = ["dynamodb:GetItem"', portal_table),
        ('resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.portal_prefix}*"]', portal_table),
        ('resources = ["arn:aws:s3:::neon1-1neon-*/*"]', portal_objects),
        ('actions   = ["dynamodb:UpdateItem"]', chat_counters),
        ('resources = ["arn:aws:dynamodb:us-east-1:${local.account}:table/${local.chat_prefix}"]', chat_counters),
    ]
    if any(needle not in block for needle, block in required):
        raise AssertionError("an app permission boundary lost its expected action or resource scope")
    if '"dynamodb:*"' in portal_table or '"dynamodb:*"' in chat_counters:
        raise AssertionError("a function boundary grants wildcard DynamoDB actions")


# Report both source checks only after every guard has passed.
def main() -> int:
    root = Path(__file__).resolve().parents[1]
    source = "\n".join(path.read_text() for path in (root / "github").glob("*.tf"))
    boundaries = (root / "github" / "boundaries.tf").read_text()
    check_trust(source)
    check_boundaries(boundaries)
    print("IAM trust and boundary source checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
