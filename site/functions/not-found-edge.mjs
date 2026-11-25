// site/functions/not-found-edge.mjs - Lambda@Edge origin-response function on the S3 behaviors only
// (site/main.tf, site-dev/not-found.tf). CloudFront Functions never run when an origin answers 400
// or above, and a distribution-wide error page would also replace the APIs' own errors, so S3's
// answers are replaced here: any client error becomes the site's not-found page with a real 404, and
// nothing S3 said (its XML, bucket keys, request IDs, headers) reaches a visitor.

// The not-found page; must match NOT_FOUND in site-router.js (a test checks)
const NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas>' +
  '<main class="nf glass glass-pane"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="https://neon1.tech/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';


// The same page for a server error
const UNAVAILABLE = NOT_FOUND.replace("neon1 · not found", "neon1 · unavailable")
  .replace('data-text="404">404', 'data-text="503">503')
  .replace("There's nothing at this address.", "This page can't load right now. Try again shortly.");


// Headers CloudFront forbids an origin-response function to drop (Transfer-Encoding, Via); it rejects the reply with a 502 if they go
const KEEP = ["transfer-encoding", "via"];


/** A response with only the headers given plus the two CloudFront requires, so none of S3's others carry over */
function reply(original, status, description, type, body) {
  const headers = {
    "content-type": [{ key: "Content-Type", value: type }],
    "cache-control": [{ key: "Cache-Control", value: "no-store" }],
  };
  for (const name of KEEP) if (original.headers && original.headers[name]) headers[name] = original.headers[name];
  return { status, statusDescription: description, headers, bodyEncoding: "text", body };
}


/** S3's errors become the not-found page (client errors) or the same page as a 503 (server errors); the rest pass through */
export const handler = async (event) => {
  const response = event.Records[0].cf.response;
  const status = Number(response.status);
  if (status < 400) return response;
  if (status >= 500) return reply(response, "503", "Service Unavailable", "text/html; charset=utf-8", UNAVAILABLE);
  return reply(response, "404", "Not Found", "text/html; charset=utf-8", NOT_FOUND);
};
