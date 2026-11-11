// site/functions/site-router.js - CloudFront Function for the site: www redirects to the apex,
// mta-sts serves only its policy file, the home page and real files pass through, and any other
// path gets a not-found page with a 404. Pages, scripts, and styles are served from the live
// release's folder, named in the key value store, so a deploy switches every file at once.

import cf from 'cloudfront';


// The not-found page: its design and rain come from the site's shared files
var NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas>' +
  '<main class="nf glass glass-pane"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';


// The request's query string, as it arrived, with its leading "?" (or nothing)
function query(request) {
  var qs = request.querystring, parts = [];
  for (var k in qs) {
    var vals = qs[k].multiValue ? qs[k].multiValue : [qs[k]];
    for (var i = 0; i < vals.length; i++) parts.push(vals[i].value === "" ? k : k + "=" + vals[i].value);
  }
  return parts.length ? "?" + parts.join("&") : "";
}

// The live release: the store's "release" key names a folder under releases/ in the bucket
var kvs = cf.kvs();
var RELEASE = /^[0-9a-f]{12}$/;

// Shared at the bucket's top, not per release: fonts and media never change at a path (neon1-site's
// manifest check), and .well-known is read by mail servers and scanners
function shared(uri) {
  return uri.indexOf("/fonts/") === 0 || uri.indexOf("/media/") === 0 || uri.indexOf("/.well-known/") === 0;
}

// The release folder's copy of a page or file. Without a valid release (none set yet, or the store
// can't answer) the bucket's top level serves it, as it did before releases
async function inRelease(request) {
  if (shared(request.uri)) return request;
  var id = "";
  try { id = await kvs.get("release"); } catch (e) { id = ""; }
  if (!RELEASE.test(id)) return request;
  request.uri = "/releases/" + id + (request.uri === "/" ? "/index.html" : request.uri);
  return request;
}

function redirect(location) {
  return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: location } } };
}

// The same path and query on the apex, so www links and bookmarks land on the one canonical host
function toApex(request) {
  return redirect("https://neon1.tech" + request.uri + query(request));
}


// www (and mta-sts, beyond its policy) goes to the apex; "/" and anything with a file extension go to S3; /faqs redirects; every other path is not found
async function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var host = request.headers.host ? request.headers.host.value : "";
  if (host === "www.neon1.tech") return toApex(request);
  // mta-sts.neon1.tech exists only for mail servers fetching the MTA-STS policy (RFC 8461)
  if (host === "mta-sts.neon1.tech") return uri === "/.well-known/mta-sts.txt" ? request : toApex(request);
  if (uri === "/" || uri.lastIndexOf(".") > uri.lastIndexOf("/")) return inRelease(request);
  // neon1.tech/faqs, like neon1.tech/1NEON/faqs: the full questions live in the knowledge center
  if (uri === "/faqs" || uri === "/faqs/") return redirect("/knowledge/faq/working-with-neon1/");
  // The knowledge center (written by neon1-site's scripts/knowledge.mjs) is folders of index.html pages:
  // a folder path serves its index.html, and the same path without its final slash gets one
  if (uri === "/knowledge" || uri.indexOf("/knowledge/") === 0) {
    if (uri.charAt(uri.length - 1) !== "/") return redirect(uri + "/" + query(request));
    request.uri = uri + "index.html";
    return inRelease(request);
  }
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
