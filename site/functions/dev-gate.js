// site/functions/dev-gate.js - The front of dev.neon1.tech's CloudFront Function. build-dev.mjs
// joins it after site-router.js and portal-router.js (their handlers renamed siteHandler and
// portalHandler) into dev-router.js, the one function every dev behavior runs.
//
// Nothing is served without a signed cookie. /__signin?k=<gate key> sets it for 30 days; the key
// lives only in the dev store's "gate" key, so changing it signs every device out. Anyone without
// the cookie gets a bare 404 that says nothing about what's here.

import crypto from 'crypto';


// Cookie names and lifetime
var GATE = "n1dev";
var PREVIEW = "n1preview";
var THIRTY_DAYS = 2592000;
// Branch preview names, as the dev deploy writes them (lowercase, digits, and dashes)
var BRANCH = /^[a-z0-9][a-z0-9-]{0,39}$/;


// The gate key from the store, or "" (which keeps everything closed)
async function gateKey() {
  try { return await kvs.get("gate"); } catch (e) { return ""; }
}


// A cookie value: expiry seconds and an HMAC over them with the gate key
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


// A bare 404 that is never cached and never indexed
function closed() {
  return {
    statusCode: 404,
    statusDescription: "Not Found",
    headers: {
      "content-type": { value: "text/plain; charset=utf-8" },
      "cache-control": { value: "no-store" },
      "x-robots-tag": { value: "noindex, nofollow" },
    },
    body: { encoding: "text", data: "Not found" },
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


// Gate first, then the APIs pass straight through, /1NEON gets the portal's routing, and everything
// else the site's, from the chosen release
async function handler(event) {
  var request = event.request;
  var uri = request.uri;
  var key = await gateKey();
  var now = Math.floor(Date.now() / 1000);
  if (key.length < 32) return closed();

  // Sign in: the link's key must match the store's exactly
  if (uri === "/__signin") {
    if (param(request, "k") !== key) return closed();
    var exp = now + THIRTY_DAYS;
    return home(GATE, sign(key, exp), "Max-Age=" + THIRTY_DAYS + "; HttpOnly; ");
  }
  if (!signedIn(request, key, now)) return closed();

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
