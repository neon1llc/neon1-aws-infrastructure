// 1NEON: /1NEON redirects to /1NEON/; app routes (no file extension) render the app shell.
function handler(event) {
  var request = event.request;
  var uri = request.uri;
  if (uri === "/1NEON") {
    return { statusCode: 301, statusDescription: "Moved Permanently", headers: { location: { value: "/1NEON/" } } };
  }
  if (uri.lastIndexOf(".") > uri.lastIndexOf("/")) return request;
  request.uri = "/1NEON/index.html";
  return request;
}
