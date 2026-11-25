// site/functions/dev-gate.js - The front of dev.neon1.tech's CloudFront Function. build-dev.mjs
// joins it after site-router.js and portal-router.js (their handlers renamed siteHandler and
// portalHandler) into dev-router.js, the one function every dev behavior runs.
//
// Nothing is served without a signed cookie. The sign-in function (dev-auth.mjs, Lambda@Edge on
// /__signin and /__auth) sets it for 30 days after the secret link and a dev-access sign-in; it is
// signed with the store's "session" key, so changing that key signs every device out. Anyone
// without the cookie gets neon1.tech's own not-found page with a 404, the same as any unknown
// address, so nothing says what's here. Only that page's public files pass without a cookie.

import crypto from 'crypto';


// Cookie names and lifetime
var GATE = "n1dev";
var PREVIEW = "n1preview";
// The files the not-found page loads, all public on neon1.tech
var PAGE_FILES = /^\/(shared\/(neon1\.css|not-found\.css|not-found\.js|rain\.js)|fonts\/[a-z0-9-]+\.woff2|favicon[a-z0-9.-]*)$/;
// Branch preview names, as the dev deploy writes them (lowercase, digits, and dashes)
var BRANCH = /^[a-z0-9][a-z0-9-]{0,39}$/;


// The cookie-signing key from the store, or "" (which keeps everything closed)
async function sessionKey() {
  try { return await kvs.get("session"); } catch (e) { return ""; }
}


// A cookie value: expiry seconds and an HMAC over them with the session key (dev-auth.mjs signs alike)
function sign(key, exp) {
  return exp + "." + crypto.createHmac("sha256", key).update("n1dev|" + exp).digest("hex");
}


// True when the request carries an unexpired cookie signed with the current key
function signedIn(request, key, now) {
  var c = request.cookies && request.cookies[GATE] ? request.cookies[GATE].value : "";
  var exp = parseInt(c.split(".")[0], 10);
  return exp > now && c === sign(key, exp);
}


// One query value, or ""
function param(request, name) {
  return request.querystring[name] ? request.querystring[name].value : "";
}


// The not-found page with a 404, never cached and never indexed
function closed() {
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


// A redirect home that sets (or, with an empty value, clears) one cookie
function home(name, value, attributes) {
  var cookies = {};
  cookies[name] = { value: value, attributes: (value ? attributes : "Max-Age=0; ") + "Path=/; Secure; SameSite=Lax" };
  return {
    statusCode: 302,
    statusDescription: "Found",
    headers: { location: { value: "/" }, "cache-control": { value: "no-store" } },
    cookies: cookies,
  };
}


// The store key for this request's release: a branch preview when the preview cookie names one
// that exists, otherwise the dev branch's "release"
async function releaseKey(request) {
  var b = request.cookies && request.cookies[PREVIEW] ? request.cookies[PREVIEW].value : "";
  if (!BRANCH.test(b)) return "release";
  try { await kvs.get("branch:" + b); return "branch:" + b; } catch (e) { return "release"; }
}


// Gate first (sign-in itself never reaches here: /__signin and /__auth run dev-auth.mjs), then the APIs pass straight through, /1NEON gets the portal's routing, and everything
// else the site's, from the chosen release
async function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var key = await sessionKey();
  var now = Math.floor(Date.now() / 1000);
  if (key.length < 32 || !signedIn(request, key, now)) return PAGE_FILES.test(uri) ? siteHandler(event) : closed();

  // Sign out, and pick or drop a branch preview (a session cookie; /__preview alone goes back to dev)
  if (uri === "/__signout") return home(GATE, "", "");
  if (uri === "/__preview") {
    var b = param(request, "b");
    return home(PREVIEW, BRANCH.test(b) ? b : "", "");
  }

  if (uri.indexOf("/1NEON/api/") === 0 || uri.indexOf("/chat/api/") === 0) return request;
  if (uri.indexOf("/1NEON") === 0) return portalHandler(event);
  RELEASE_KEY = await releaseKey(request);
  return siteHandler(event);
}
