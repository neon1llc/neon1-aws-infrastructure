// site/functions/catchall.js - CloudFront Function for every neon1.tech name no other distribution
// claims (catchall/main.tf). Every address is the not-found page; only the public files that page
// loads pass through, to neon1.tech.


// The not-found page (the same as site-router.js's; a test checks)
var NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas>' +
  '<main class="nf glass glass-pane"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="https://neon1.tech/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';


// The files the page loads
var PAGE_FILES = /^\/(shared\/(neon1\.css|not-found\.css|not-found\.js|rain\.js)|fonts\/[a-z0-9-]+\.woff2|favicon[a-z0-9.-]*)$/;


function handler(event) {
  var request = event.request;
  if (PAGE_FILES.test(request.uri)) return request;
  return {
    statusCode: 404,
    statusDescription: "Not Found",
    headers: {
      "content-type": { value: "text/html; charset=utf-8" },
      "cache-control": { value: "no-store" },
      "x-robots-tag": { value: "noindex, nofollow" },
    },
    body: { encoding: "text", data: NOT_FOUND },
  };
}
