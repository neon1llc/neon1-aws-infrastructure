// site/functions/site-router.js - CloudFront Function for the site: www redirects to the apex,
// the home page and real files pass through, and any other path gets a not-found page with a 404.


// The not-found page: its design and rain come from the site's shared files
var NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas>' +
  '<main class="nf glass glass-pane"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';


// The same path and query on the apex, so www links and bookmarks land on the one canonical host
function toApex(request) {
  var qs = request.querystring, parts = [];
  for (var k in qs) {
    var vals = qs[k].multiValue ? qs[k].multiValue : [qs[k]];
    for (var i = 0; i < vals.length; i++) parts.push(vals[i].value === "" ? k : k + "=" + vals[i].value);
  }
  var location = "https://neon1.tech" + request.uri + (parts.length ? "?" + parts.join("&") : "");
  return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: location } } };
}


// www goes to the apex; "/" and anything with a file extension go to S3; every other path is not found
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (request.headers.host && request.headers.host.value === "www.neon1.tech") return toApex(request);
  if (uri === "/" || uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  return {
    statusCode: 404,
    statusDescription: "Not Found",
    headers: {
      "content-type": { value: "text/html; charset=utf-8" },
      "cache-control": { value: "no-store" },
    },
    body: { encoding: "text", data: NOT_FOUND },
  };
}
