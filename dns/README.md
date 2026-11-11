# dns

Records for the neon1.tech zone that no app stack owns. The zone itself is created outside Terraform, and other stacks keep their own records: `site/` the apex and `www` aliases, neon1-1NEON the `auth` alias and everything under `notify.neon1.tech`.

| Record | Value | Why |
|---|---|---|
| SOA | A dated serial (`soa_serial`), RFC 1912 refresh and retry, one-hour negative caching | Route 53 leaves the serial at 1 and caches a missing name for a day |
| CAA | `amazon.com`, `amazontrust.com`, `awstrust.com`, `amazonaws.com`; iodef to security@ | Every certificate comes from ACM, so no other CA may issue one |
| MX | `1 smtp.google.com.` | Google Workspace receives mail |
| TXT (apex) | SPF for Google and SES, and Google's verification token | They share one record set |
| `google._domainkey` | Workspace's DKIM public key | Workspace signs as `d=neon1.tech` |
| `_dmarc` | `p=quarantine; sp=quarantine`, reports to dmarc@ | Mail that fails both aligned SPF and DKIM goes to spam |
| `_smtp._tls` | TLS-RPT reports to dmarc@ | Senders report TLS failures delivering to us |
| `default._bimi` | `l=https://neon1.tech/bimi/neon1.svg`, no certificate yet | The brand logo, self-asserted until a VMC or CMC is bought |

## DMARC

Mail from Google Workspace passes DMARC by aligned SPF (and DKIM, once signing is on in the Admin console). 1NEON's mail comes from `notify.neon1.tech`, which has its own stricter record in neon1-1NEON. The next step is `dmarc_policy = "reject"` once a few weeks of reports at dmarc@ show nothing legitimate failing.

## BIMI

Receivers honor BIMI only under an enforcing DMARC. Without `bimi_authority_url`, the logo is self-asserted, which some providers show. Gmail and Apple Mail show it only with a Verified Mark Certificate (needs a registered trademark) or a Common Mark Certificate (needs a year of public use of the logo). Both are bought yearly from DigiCert or Sectigo. Put the certificate's PEM on the site and its URL in `bimi_authority_url`.

The logo is `src/app/public/bimi/neon1.svg` in neon1-site: SVG Tiny PS, square, solid background.

## Changing a record

Every value is a variable. Edit the default (or the record) and push to main; CI plans and applies this stack with the Terraform role, which may change only these names and the SOA, CAA, MX, and TXT types. A name outside that list needs a matching change to the `DnsRecords` statement in `github/main.tf`, applied by hand first.
