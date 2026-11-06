// neon1.tech: page paths (no file extension) render the single-page site.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri === "/" || uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/index.html";
  return request;
}
