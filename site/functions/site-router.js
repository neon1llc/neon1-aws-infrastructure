// site/functions/site-router.js - CloudFront Function for the site: the home page and real files
// pass through; any other path gets a small not-found page with a real 404 status.


// The not-found page: its design and rain come from the site's shared files
var NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas>' +
  '<main class="nf"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';


// "/" and anything with a file extension go to S3 as asked; every other path is not found
function handler(event) {
  var request = event.request;
  var uri = request.uri;
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
