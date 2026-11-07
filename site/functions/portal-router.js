// site/functions/portal-router.js - CloudFront Function for /1NEON requests: www redirects to the
// apex, the bare path redirects to /1NEON/, and app routes (no file extension) get the app shell.


// A sign-in on www would set cookies the apex can't use, so www goes to the same path on the apex
function toApex(request) {
  var qs = request.querystring, parts = [];
  for (var k in qs) {
    var vals = qs[k].multiValue ? qs[k].multiValue : [qs[k]];
    for (var i = 0; i < vals.length; i++) parts.push(vals[i].value === "" ? k : k + "=" + vals[i].value);
  }
  var location = "https://neon1.tech" + request.uri + (parts.length ? "?" + parts.join("&") : "");
  return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: location } } };
}


// Files pass through; anything else is a client-side route the app handles
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (request.headers.host && request.headers.host.value === "www.neon1.tech") return toApex(request);
  // The app lives under /1NEON/, so the bare path redirects there
  if (uri === "/1NEON") {
    return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: "/1NEON/" } } };
  }
  if (uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/1NEON/index.html";
  return request;
}
