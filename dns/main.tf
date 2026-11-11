# dns/main.tf - Zone-wide settings no app stack owns: DNSSEC signing and its alarms, the SOA serial,
# CAA, and the apex mail records (Google Workspace MX, SPF, DKIM, DMARC, MTA-STS, TLS reporting, and BIMI). The mail records were created by
# hand when Workspace went live; allow_overwrite takes them over in place. 1NEON's own sending
# subdomain (notify.neon1.tech) is managed in neon1-1NEON, and the site's aliases in site/.


# The account this runs in, for the alerts topic's ARN
data "aws_caller_identity" "current" {}

locals {
  alerts_topic_arn = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:${var.alerts_topic_name}"
}


# --- SOA: Route 53's own record, with a dated serial ---
# Route 53 starts every zone at serial 1 and never changes it. Checkers expect YYYYMMDDnn, so this
# sets one; bump it when the zone changes in a way worth marking. Refresh and retry follow RFC 1912
# (Route 53 has no secondaries, so they only quiet checkers), and failed lookups are cached an hour
# rather than Route 53's default day, so a newly added record shows up sooner


resource "aws_route53_record" "soa" {
  zone_id         = var.zone_id
  name            = var.domain
  type            = "SOA"
  ttl             = 900
  records         = ["${var.primary_name_server} awsdns-hostmaster.amazon.com. ${var.soa_serial} 14400 3600 1209600 3600"]
  allow_overwrite = true

  # A zone can't lose its SOA; destroying this stack must leave it behind
  lifecycle {
    prevent_destroy = true
  }
}


# --- CAA: only Amazon's CA may issue certificates for neon1.tech and its subdomains ---
# Every certificate here comes from ACM (CloudFront, the Cognito domain). Misissuance reports go to security@


resource "aws_route53_record" "caa" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "CAA"
  ttl     = 3600
  records = concat(
    [for ca in ["amazon.com", "amazontrust.com", "awstrust.com", "amazonaws.com"] : "0 issue \"${ca}\""],
    ["0 issuewild \"amazon.com\"", "0 iodef \"mailto:security@${var.domain}\""],
  )
  allow_overwrite = true
}


# --- Receiving: Google Workspace ---


resource "aws_route53_record" "mx" {
  zone_id         = var.zone_id
  name            = var.domain
  type            = "MX"
  ttl             = 3600
  records         = ["1 smtp.google.com."]
  allow_overwrite = true
}


# --- Apex TXT: SPF and Google verification share one record set ---
# SPF allows Google Workspace and SES. ~all (softfail) is the usual pairing with an enforcing DMARC,
# which decides the outcome for unaligned mail


resource "aws_route53_record" "apex_txt" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "TXT"
  ttl     = 3600
  records = [
    "v=spf1 include:_spf.google.com include:amazonses.com ~all",
    "google-site-verification=${var.google_site_verification}",
  ]
  allow_overwrite = true
}


# --- DKIM: Google Workspace signs as d=neon1.tech ---
# A 2048-bit key is longer than one 255-character TXT string, so it goes in as two


locals {
  dkim_value = "v=DKIM1;k=rsa;p=${var.google_dkim_public_key}"
}


resource "aws_route53_record" "google_dkim" {
  zone_id         = var.zone_id
  name            = "google._domainkey.${var.domain}"
  type            = "TXT"
  ttl             = 3600
  records         = ["${substr(local.dkim_value, 0, 255)}\"\"${substr(local.dkim_value, 255, -1)}"]
  allow_overwrite = true
}


# --- DMARC: aggregate reports to dmarc@, policy for the apex and every subdomain ---
# Relaxed alignment, because SES mail is signed by notify.neon1.tech, which has its own stricter record


locals {
  dmarc_value = join("; ", [
    "v=DMARC1",
    "p=${var.dmarc_policy}",
    "sp=${var.dmarc_policy}",
    "rua=mailto:dmarc@${var.domain}",
    "adkim=r",
    "aspf=r",
  ])
}


resource "aws_route53_record" "dmarc" {
  zone_id         = var.zone_id
  name            = "_dmarc.${var.domain}"
  type            = "TXT"
  ttl             = 300
  records         = [local.dmarc_value]
  allow_overwrite = true
}


# --- MTA-STS: senders must use verified TLS to our MX (RFC 8461) ---
# The policy file is neon1-site's .well-known/mta-sts.txt, served at mta-sts.neon1.tech by the site
# stack. Change mta_sts_id whenever that file changes, or senders keep the policy they cached


resource "aws_route53_record" "mta_sts" {
  zone_id         = var.zone_id
  name            = "_mta-sts.${var.domain}"
  type            = "TXT"
  ttl             = 3600
  records         = ["v=STSv1; id=${var.mta_sts_id}"]
  allow_overwrite = true
}


# --- TLS reporting: receivers send daily reports of TLS failures delivering to our MX ---


resource "aws_route53_record" "tls_rpt" {
  zone_id         = var.zone_id
  name            = "_smtp._tls.${var.domain}"
  type            = "TXT"
  ttl             = 3600
  records         = ["v=TLSRPTv1; rua=mailto:dmarc@${var.domain}"]
  allow_overwrite = true
}


# --- BIMI: the brand logo some inboxes show beside our mail ---
# Receivers only honor BIMI under an enforcing DMARC. Gmail and Apple Mail also need a mark
# certificate (a=); without one, the logo is self-asserted and only some providers show it


resource "aws_route53_record" "bimi" {
  count = var.bimi_logo_url == "" || var.dmarc_policy == "none" ? 0 : 1

  zone_id         = var.zone_id
  name            = "default._bimi.${var.domain}"
  type            = "TXT"
  ttl             = 3600
  records         = ["v=BIMI1; l=${var.bimi_logo_url}; a=${var.bimi_authority_url}"]
  allow_overwrite = true
}


# --- DNSSEC: Route 53 signs the zone with a key-signing key held in KMS ---
# Turned on by hand on 2026-11-11 and imported here. The KMS key (alias/neon1-tech-dnssec, ECC P-256,
# in us-east-1 as Route 53 requires) stays outside Terraform; its policy lets Route 53's DNSSEC service
# sign with it. Never disable or delete that key, or this signing key, while the registrar holds the
# DS record: validating resolvers would then reject every neon1.tech answer


data "aws_kms_alias" "dnssec" {
  name = "alias/neon1-tech-dnssec"
}


import {
  to = aws_route53_key_signing_key.ksk
  id = "${var.zone_id},neon1_tech_ksk"
}

resource "aws_route53_key_signing_key" "ksk" {
  hosted_zone_id             = var.zone_id
  key_management_service_arn = data.aws_kms_alias.dnssec.target_key_arn
  name                       = "neon1_tech_ksk"

  lifecycle {
    prevent_destroy = true
  }
}


import {
  to = aws_route53_hosted_zone_dnssec.zone
  id = var.zone_id
}

resource "aws_route53_hosted_zone_dnssec" "zone" {
  hosted_zone_id = aws_route53_key_signing_key.ksk.hosted_zone_id

  lifecycle {
    prevent_destroy = true
  }
}


# Two alarms, the ones AWS recommends: signing failed, or the key needs attention (KMS key disabled,
# its policy changed, or similar). Either one, left alone, ends with neon1.tech failing to resolve.
# They go to 1NEON's alerts topic, whose email subscription is already confirmed


locals {
  dnssec_alarms = {
    internal-failure = {
      metric = "DNSSECInternalFailure"
      what   = "Route 53 could not sign neon1.tech. Validating resolvers may stop answering for the domain."
    }
    ksk-needs-action = {
      metric = "DNSSECKeySigningKeysNeedingAction"
      what   = "neon1.tech's DNSSEC signing key needs attention (is its KMS key disabled or its policy changed?)."
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "dnssec" {
  for_each = local.dnssec_alarms

  alarm_name          = "neon1-dns-dnssec-${each.key}"
  alarm_description   = each.value.what
  namespace           = "AWS/Route53"
  metric_name         = each.value.metric
  dimensions          = { HostedZoneId = var.zone_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.alerts_topic_arn]
  ok_actions          = [local.alerts_topic_arn]
}
