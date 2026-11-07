# site

Static hosting for **neon1.tech**: private S3 origin, CloudFront with Origin Access Control, an ACM certificate for `neon1.tech` + `*.neon1.tech`, and Route 53 A/AAAA aliases for the apex and `www`.

The hosted zone itself and mail records are outside this stack.

```bash
export AWS_PROFILE=neon1
terraform init
terraform plan
terraform apply
```

State is stored in `s3://neon1-tfstate/site/terraform.tfstate` (versioned bucket, S3-native lock file). The state bucket was created once with the AWS CLI before the first `init`.

Content is deployed by syncing the site build into the `bucket` output and invalidating the `distribution_id` output.

## 1NEON at /1NEON

The distribution also serves the 1NEON portal (neon1llc/1NEON):

- `/1NEON/api/*` goes to the portal's HTTP API, uncached, with cookies and query strings forwarded.
- `/1NEON*` goes to the portal's private bucket. `functions/portal-router.js` serves the app shell for app routes.
- Both routers send `www.neon1.tech` to the same path and query on the apex with a 301, so neon1.tech is the one canonical host.
- The default behavior uses `functions/site-router.js` for page paths. This replaces the old distribution-wide 403/404 → `/index.html` error pages, which would have turned portal API errors into the marketing page.

The portal's origin domains come from SSM parameters `/1neon/prod/app_bucket_domain` and `/1neon/prod/api_domain`, which the 1NEON stack publishes. Apply that stack before this one.

## Response headers

The site (`neon1-site-headers`) and the portal (`neon1-1neon-headers`) each send a Content Security Policy, two-year HSTS with subdomains, `nosniff`, `DENY` framing, a strict referrer policy, and a Permissions-Policy that turns off device and payment access. The HSTS and Permissions-Policy values are shared locals, because HSTS applies to the whole host. The site's policy allows only same-origin scripts, styles, fonts, and connections, and `data:` images, so neon1-site keeps no inline scripts or styles.

The bucket policy also lets CloudFront list the bucket, so a missing file comes back as 404 rather than 403. Query strings aren't forwarded to S3, so a listing can't be requested through the CDN.
