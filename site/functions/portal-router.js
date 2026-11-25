// site/functions/portal-router.js - CloudFront Function for /1NEON requests: www redirects to the
// apex, the bare path redirects to /1NEON/, and app routes (no file extension) get the app shell.
// The portal is exactly /1NEON and /1NEON/*; the behavior's /1NEON* pattern also catches paths like
// /1NEONx, which are not the portal and get the not-found page.


// The site's not-found page (the same as site-router.js's; a test checks)
var NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas>' +
  '<main class="nf glass glass-pane"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="https://neon1.tech/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';


// The request's query string, rebuilt; every redirect keeps it so sign-in links and invites survive
function query(request) {
  var qs = request.querystring, parts = [];
  for (var k in qs) {
    var vals = qs[k].multiValue ? qs[k].multiValue : [qs[k]];
    for (var i = 0; i < vals.length; i++) parts.push(vals[i].value === "" ? k : k + "=" + vals[i].value);
  }
  return parts.length ? "?" + parts.join("&") : "";
}


// A permanent redirect to a location that already carries its query
function redirect(location) {
  return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: location } } };
}


// Files pass through; anything else under /1NEON/ is a client-side route the app handles
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  // A sign-in on www would set cookies the apex can't use, so www (and the mail-only mta-sts host)
  // goes to the same path on the apex
  var host = request.headers.host ? request.headers.host.value : "";
  if (host === "www.neon1.tech" || host === "mta-sts.neon1.tech") return redirect("https://neon1.tech" + uri + query(request));
  // The app lives under /1NEON/, so the bare path redirects there, query and all
  if (uri === "/1NEON") return redirect("/1NEON/" + query(request));
  if (uri.indexOf("/1NEON/") !== 0) {
    return {
      statusCode: 404,
      statusDescription: "Not Found",
      headers: { "content-type": { value: "text/html; charset=utf-8" }, "cache-control": { value: "no-store" } },
      body: { encoding: "text", data: NOT_FOUND },
    };
  }
  if (uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/1NEON/index.html";
  return request;
}
