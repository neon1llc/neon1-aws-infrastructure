// site/functions/dev-auth.mjs - dev.neon1.tech's sign-in, a Lambda@Edge viewer-request function on
// /__signin and /__auth only (site-dev/main.tf). Two steps, both required:
//   1. /__signin?k=<link key> (the secret link) sends the browser to the dev Cognito sign-in.
//   2. Cognito returns to /__auth with a code; a person in the dev-access group gets the 30-day
//      n1dev cookie that dev-gate.js checks on every other request.
// Every failure is the same bare 404 dev-gate.js gives, so a stranger learns nothing either way.
// Lambda@Edge has no environment variables: config.json beside this file is written by Terraform.

import crypto from "node:crypto";
import { readFileSync } from "node:fs";


// Cookie names and lifetimes; n1dev's format must match dev-gate.js's sign()
const GATE = "n1dev";
const START = "n1auth";
const THIRTY_DAYS = 2592000;
const TEN_MINUTES = 600;
// How long fetched keys are reused, so a new link or a sign-out-all takes effect within a minute
const KEY_CACHE_MS = 60000;


// --- Small helpers ---


const b64url = (buf) => Buffer.from(buf).toString("base64url");
const hmac = (key, text) => crypto.createHmac("sha256", key).update(text).digest("hex");

/** Equal strings, compared in constant time (hashing first evens out the lengths) */
function same(a, b) {
  const h = (s) => crypto.createHash("sha256").update(String(s)).digest();
  return crypto.timingSafeEqual(h(a), h(b));
}

/** The request's cookies as name -> value (last one wins) */
function cookies(request) {
  const out = {};
  for (const h of request.headers.cookie || []) {
    for (const part of h.value.split(";")) {
      const i = part.indexOf("=");
      if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
    }
  }
  return out;
}

/** A Lambda@Edge response header list */
const header = (key, value) => [{ key, value }];

/** The bare 404 dev-gate.js gives, never cached and never indexed */
function closed() {
  return {
    status: "404",
    statusDescription: "Not Found",
    headers: {
      "content-type": header("Content-Type", "text/plain; charset=utf-8"),
      "cache-control": header("Cache-Control", "no-store"),
      "x-robots-tag": header("X-Robots-Tag", "noindex, nofollow"),
    },
    body: "Not found",
  };
}

/** A no-store redirect that sets the given cookies */
function redirect(location, setCookies) {
  return {
    status: "302",
    statusDescription: "Found",
    headers: {
      location: header("Location", location),
      "cache-control": header("Cache-Control", "no-store"),
      "set-cookie": setCookies.map((value) => ({ key: "Set-Cookie", value })),
    },
  };
}

/** The ID token's claims. It comes straight from Cognito's token endpoint over TLS, so the
 * connection vouches for it (OpenID Connect Core 3.1.3.7); its contents are still checked */
function claims(idToken) {
  return JSON.parse(Buffer.from(String(idToken).split(".")[1] || "", "base64url").toString("utf8"));
}


// --- The handler, built from its dependencies so tests can supply fakes ---


/**
 * config: { authDomain, clientId, issuer, publicUrl, group, linkParam, sessionParam }
 * keys(): resolves { link, session } (the two SSM SecureStrings)
 * post(url, form): resolves the token endpoint's JSON
 */
export function makeHandler({ config, keys, post, now = () => Date.now() }) {
  const callback = `${config.publicUrl}/__auth`;

  // Step 1: the secret link. A right key starts a Cognito sign-in bound to this browser
  async function start(params, k) {
    if (k.link.length < 32 || k.session.length < 32 || !same(params.get("k") || "", k.link)) return closed();
    const state = b64url(crypto.randomBytes(16));
    const verifier = b64url(crypto.randomBytes(32));
    const exp = Math.floor(now() / 1000) + TEN_MINUTES;
    const value = `${state}.${verifier}.${exp}`;
    const cookie = `${START}=${value}.${hmac(k.session, `${START}|${value}`)}; Max-Age=${TEN_MINUTES}; Path=/__auth; HttpOnly; Secure; SameSite=Lax`;
    const q = new URLSearchParams({
      response_type: "code",
      client_id: config.clientId,
      redirect_uri: callback,
      scope: "openid email",
      state,
      nonce: state,
      code_challenge: b64url(crypto.createHash("sha256").update(verifier).digest()),
      code_challenge_method: "S256",
    });
    return redirect(`https://${config.authDomain}/oauth2/authorize?${q}`, [cookie]);
  }

  // Step 2: Cognito's answer. Only the browser that used the link, and only a dev-access member
  async function finish(params, jar, k) {
    const t = Math.floor(now() / 1000);

    // Back from adding a passkey (no code): a signed-in device just goes home
    if (!params.get("code")) {
      const [exp, mac] = (jar[GATE] || "").split(".");
      return Number(exp) > t && k.session.length >= 32 && same(mac || "", hmac(k.session, `${GATE}|${exp}`)) ? redirect("/", []) : closed();
    }

    const parts = (jar[START] || "").split(".");
    if (parts.length !== 4 || k.session.length < 32) return closed();
    const [state, verifier, exp, mac] = parts;
    if (!same(mac, hmac(k.session, `${START}|${state}.${verifier}.${exp}`)) || Number(exp) <= t) return closed();
    if (!same(params.get("state") || "", state)) return closed();

    let tokens;
    try {
      tokens = await post(`https://${config.authDomain}/oauth2/token`, {
        grant_type: "authorization_code",
        client_id: config.clientId,
        code: params.get("code"),
        redirect_uri: callback,
        code_verifier: verifier,
      });
    } catch {
      return closed();
    }

    let c;
    try { c = claims(tokens.id_token); } catch { return closed(); }
    const ok = c.iss === config.issuer && c.aud === config.clientId && c.token_use === "id" && c.nonce === state &&
      Number(c.exp) > t && Array.isArray(c["cognito:groups"]) && c["cognito:groups"].includes(config.group);
    if (!ok) return closed();

    const until = t + THIRTY_DAYS;
    return redirect("/", [
      `${GATE}=${until}.${hmac(k.session, `${GATE}|${until}`)}; Max-Age=${THIRTY_DAYS}; Path=/; HttpOnly; Secure; SameSite=Lax`,
      `${START}=; Max-Age=0; Path=/__auth; HttpOnly; Secure; SameSite=Lax`,
    ]);
  }

  return async function handler(event) {
    const request = event.Records[0].cf.request;
    const params = new URLSearchParams(request.querystring || "");
    let k;
    try { k = await keys(); } catch { return closed(); }
    if (request.uri === "/__signin") return start(params, k);
    if (request.uri === "/__auth") return finish(params, cookies(request), k);
    return closed();
  };
}


// --- The deployed handler: config from Terraform, keys from SSM (us-east-1), the token endpoint by fetch ---


let config;
let cached = { at: 0, value: null };
let live;

/** The two keys, fetched at most once a minute per edge location */
async function ssmKeys() {
  if (cached.value && Date.now() - cached.at < KEY_CACHE_MS) return cached.value;
  const { SSMClient, GetParametersCommand } = await import("@aws-sdk/client-ssm");
  const ssm = new SSMClient({ region: "us-east-1" });
  const out = await ssm.send(new GetParametersCommand({ Names: [config.linkParam, config.sessionParam], WithDecryption: true }));
  const get = (name) => (out.Parameters || []).find((p) => p.Name === name)?.Value || "";
  cached = { at: Date.now(), value: { link: get(config.linkParam), session: get(config.sessionParam) } };
  return cached.value;
}

/** A form POST that must answer 200 with JSON within four seconds (viewer requests get five) */
async function postForm(url, form) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form),
    signal: AbortSignal.timeout(4000),
  });
  if (!r.ok) throw new Error(`token endpoint ${r.status}`);
  return r.json();
}

export async function handler(event) {
  if (!live) {
    config = JSON.parse(readFileSync(new URL("./config.json", import.meta.url), "utf8"));
    live = makeHandler({ config, keys: ssmKeys, post: postForm });
  }
  return live(event);
}
