// site/functions/site-router.js - CloudFront Function for the site: page paths (no file
// extension) get the single-page site, so unknown pages render it instead of an S3 error.


// The root and real files pass through; every other path gets index.html
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri === "/" || uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/index.html";
  return request;
}
