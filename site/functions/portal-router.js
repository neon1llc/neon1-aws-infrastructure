// site/functions/portal-router.js - CloudFront Function for /1NEON requests: the bare path
// redirects to /1NEON/, and app routes (no file extension) get the app shell.


// Files pass through; anything else is a client-side route the app handles
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  // The app lives under /1NEON/, so the bare path redirects there
  if (uri === "/1NEON") {
    return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: "/1NEON/" } } };
  }
  if (uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/1NEON/index.html";
  return request;
}
