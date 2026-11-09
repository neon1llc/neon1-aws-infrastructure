// site/functions/portal-router.js - CloudFront Function for /1NEON requests: www redirects to the
// apex, the bare path redirects to /1NEON/, and app routes (no file extension) get the app shell.
// The portal is exactly /1NEON and /1NEON/*; the behavior's /1NEON* pattern also catches paths like
// /1NEONx, which are not the portal and get a plain not-found page.


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
  // A sign-in on www would set cookies the apex can't use, so www goes to the same path on the apex
  if (request.headers.host && request.headers.host.value === "www.neon1.tech") return redirect("https://neon1.tech" + uri + query(request));
  // The app lives under /1NEON/, so the bare path redirects there, query and all
  if (uri === "/1NEON") return redirect("/1NEON/" + query(request));
  if (uri.indexOf("/1NEON/") !== 0) {
    return {
      statusCode: 404,
      statusDescription: "Not Found",
      headers: { "content-type": { value: "text/html; charset=utf-8" }, "cache-control": { value: "no-store" } },
      body: { encoding: "text", data: '<!doctype html><html lang="en"><meta charset="utf-8"><title>neon1 · not found</title><meta name="robots" content="noindex"><p>There\'s nothing at this address. <a href="/1NEON/">Go to 1NEON</a></p></html>' },
    };
  }
  if (uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/1NEON/index.html";
  return request;
}
