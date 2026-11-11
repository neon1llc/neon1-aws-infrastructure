# dns/outputs.tf - The DMARC and BIMI values as published, for checking against live DNS.


output "dmarc" {
  value = local.dmarc_value
}


output "bimi" {
  value = one(aws_route53_record.bimi[*].records)
}
