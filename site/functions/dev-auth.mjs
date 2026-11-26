// site/functions/dev-auth.mjs - dev.neon1.tech's sign-in, a Lambda@Edge viewer-request function on
// /__signin and /__auth only (site-dev/main.tf).
//   1. /__signin?k=<link key>, a private address that only changes when someone changes it on
//      purpose, shows the sign-in card; its button starts the dev Cognito sign-in (a passkey or
//      email code). A device already signed in goes straight home. Without the key it's a 404.
//   2. Cognito returns to /__auth with a code; a person in the dev-access group gets the 30-day
//      n1dev cookie that dev-gate.js checks on every other request.
// Every failure is the same not-found page dev-gate.js gives.
// Lambda@Edge has no environment variables: config.json beside this file is written by Terraform.

import crypto from "node:crypto";
import { readFileSync } from "node:fs";


// Cookie names and lifetimes; n1dev's format must match dev-gate.js's sign()
const GATE = "n1dev";
const START = "n1auth";
const THIRTY_DAYS = 2592000;
const ONE_HOUR = 3600;
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

// The not-found page; must match NOT_FOUND in site-router.js (a test checks)
const NOT_FOUND = '<!doctype html><html lang="en"><head><meta charset="utf-8">' +
  '<meta name="viewport" content="width=device-width, initial-scale=1">' +
  '<title>neon1 · not found</title><meta name="robots" content="noindex">' +
  '<link rel="stylesheet" href="/shared/neon1.css"><link rel="stylesheet" href="/shared/not-found.css">' +
  '</head><body><canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas>' +
  '<main class="nf glass glass-pane"><h1 class="glitch" data-text="404">404</h1>' +
  '<p>There\'s nothing at this address.</p><a href="https://neon1.tech/">Back to neon1.tech</a></main>' +
  '<script type="module" src="/shared/not-found.js"></script></body></html>';

/** The not-found page dev-gate.js gives, never cached and never indexed */
function closed() {
  return {
    status: "404",
    statusDescription: "Not Found",
    headers: {
      "content-type": header("Content-Type", "text/html; charset=utf-8"),
      "cache-control": header("Cache-Control", "no-store"),
      "x-robots-tag": header("X-Robots-Tag", "noindex, nofollow"),
    },
    body: NOT_FOUND,
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


// --- The sign-in card ---


// Its styles and script go in the page as they are, so the header policy can allow exactly them
const CSS = readFileSync(new URL("./signin.css", import.meta.url), "utf8");
const JS = readFileSync(new URL("./signin.js", import.meta.url), "utf8");

// The dev mark "DE>" (neon1's brand set); the tab icon is its ">" and follows the browser's light or dark
const MARK = '<svg class="mark" viewBox="2 12.5 62.5 39" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.5 20V44H8.5a12 12 0 0 0 0-24ZM39 20H29V44H39M29 32H37M46 15.5L60 32L46 48.5"/></svg>';
const TAB = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="6.5 6.5 51 51"><style>@media (prefers-color-scheme:dark){path{stroke:#6CFFA8}}</style><path d="M20 12L44 32L20 52" fill="none" stroke="#327641" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/></svg>');
const LOGO = '<svg viewBox="0 0 64 64" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" aria-hidden="true"><path d="M6 6a24 24 0 0 1 24 24v30M6 12a18 18 0 0 1 18 18v30M6 18a12 12 0 0 1 12 12v30M6 24a6 6 0 0 1 6 6v30"/><path d="M34 6a24 24 0 0 1 24 24v30M34 12a18 18 0 0 1 18 18v30M34 18a12 12 0 0 1 12 12v30M34 24a6 6 0 0 1 6 6v30"/></svg>';
const SUN = '<svg class="theme-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2.2M12 19.3v2.2M2.5 12h2.2M19.3 12h2.2M5.3 5.3l1.6 1.6M17.1 17.1l1.6 1.6M5.3 18.7l1.6-1.6M17.1 6.9l1.6-1.6"/></svg>';
const MOON = '<svg class="theme-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20 14.6A8.2 8.2 0 0 1 9.4 4a8.2 8.2 0 1 0 10.6 10.6Z"/></svg>';
const BUG = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M5.5 5.2V4a2.5 2.5 0 0 1 5 0v1.2M4.4 6.2h7.2v3.6a3.6 3.6 0 0 1-7.2 0zM8 6.4v7M1.8 7.6l2.6.9M14.2 7.6l-2.6.9M2.2 12.2l2.5-1.2M13.8 12.2 11.3 11"/></svg>';
const TALK = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M2.5 3h11v7.2H8.4L5.2 13v-2.8H2.5zM5.4 5.8h5.2M5.4 7.6h3.2"/></svg>';

// Pages dev's gate doesn't serve to strangers are the public site's
const SITE = "https://neon1.tech";
const SEP = '<span class="sep" aria-hidden="true">\\</span>';
const out = (href, text, cls = "", icon = "", label = "") => `<a class="ext${cls}" href="${href}" target="_blank" rel="noopener"${label ? ` aria-label="${label}"` : ""}>${icon}<span class="ext-end">${text}</span></a>`;
const page = (policy, text) => `<a href="${SITE}/knowledge/${policy}/" target="_blank" rel="noopener">${text}</a>`;

/** The legal strip under the panel, as on 1NEON's public pages */
const foot = () => '<footer class="pub-foot"><div class="legal"><div class="foot-meta">' + out(`${SITE}/`, "neon1.tech") +
  '<p class="look-pick" role="group" aria-label="Theme"><span class="look-lead" aria-hidden="true">theme</span><button class="look-opt" type="button" data-look="matrix">matrix</button>' + SEP + '<button class="look-opt" type="button" data-look="sentinel">sentinel</button></p></div>' +
  `<span class="owner">© ${new Date().getFullYear()} neon1 LLC, New York${SEP}${page("company/registration", "state registration")}</span>` +
  `<span class="policies">${page("policies/privacy", "privacy")}${SEP}${page("policies/cookies", "browser storage")}${SEP}${page("policies/terms", "terms")}</span>` +
  '<span class="report-links"><span class="report-lead">report</span>' + out(`${SITE}/report-bug/?from=dev`, "bug", " report-bug", BUG, "report a bug") + SEP + out(`${SITE}/feedback/?from=dev`, "feedback", " report-feedback", TALK, "report feedback") + '</span></div></footer>';

/** The private sign-in screen with one button, to the given Cognito address */
function card(href, setCookie) {
  const body = '<!doctype html><html lang="en" data-style="sentinel" data-theme="awake"><head><meta charset="utf-8">' +
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"><meta name="referrer" content="no-referrer">' +
    `<title>Sign in · neon1 dev</title><meta name="robots" content="noindex"><link rel="icon" href="${TAB}" type="image/svg+xml">` +
    '<link rel="stylesheet" href="/shared/neon1.css"><style>' + CSS + '</style><script type="module">' + JS + '</script></head><body><main class="signin">' +
    '<canvas id="rain" aria-hidden="true"></canvas><canvas id="lens" aria-hidden="true"></canvas><div class="veil"></div>' +
    `<header class="n1-bar pub-bar alone"><div class="n1-inner"><a class="n1-logo" href="${SITE}/" aria-label="neon1.tech home">${LOGO}<span><span class="ne">neon</span><span class="one">1</span></span></a>` +
    `<button class="theme-sw" type="button" role="switch" aria-checked="false" aria-label="Dark mode" title="light or dark">${SUN}${MOON}<span class="theme-knob" aria-hidden="true"></span></button></div></header>` +
    '<div class="panel">' + MARK + '<h1 class="signin-h">neon1 dev</h1><p class="signin-lead">Sign in with your dev account.</p>' +
    '<a class="btn" href="' + href.replace(/&/g, "&amp;") + '">Sign in</a><p class="next-hint">A passkey or an emailed code.</p></div>' +
    foot() + '</main></body></html>';
  return {
    status: "200",
    statusDescription: "OK",
    headers: {
      "content-type": header("Content-Type", "text/html; charset=utf-8"),
      "cache-control": header("Cache-Control", "no-store"),
      "set-cookie": header("Set-Cookie", setCookie),
    },
    body,
  };
}


// --- The handler, built from its dependencies so tests can supply fakes ---


/**
 * config: { authDomain, clientId, issuer, publicUrl, group, linkParam, sessionParam }
 * keys(): resolves { link, session } (the two SSM SecureStrings)
 * post(url, form): resolves the token endpoint's JSON
 */
export function makeHandler({ config, keys, post, now = () => Date.now() }) {
  const callback = `${config.publicUrl}/__auth`;

  // A device with a current cookie
  function signedIn(jar, k) {
    const [exp, mac] = (jar[GATE] || "").split(".");
    return Number(exp) > Math.floor(now() / 1000) && k.session.length >= 32 && same(mac || "", hmac(k.session, `${GATE}|${exp}`));
  }

  // Step 1: with the link key, the card whose button starts a Cognito sign-in bound to this browser
  async function start(params, jar, k) {
    if (k.link.length < 32 || k.session.length < 32 || !same(params.get("k") || "", k.link)) return closed();
    if (signedIn(jar, k)) return redirect("/", []);
    const state = b64url(crypto.randomBytes(16));
    const verifier = b64url(crypto.randomBytes(32));
    const exp = Math.floor(now() / 1000) + ONE_HOUR;
    const value = `${state}.${verifier}.${exp}`;
    const cookie = `${START}=${value}.${hmac(k.session, `${START}|${value}`)}; Max-Age=${ONE_HOUR}; Path=/__auth; HttpOnly; Secure; SameSite=Lax`;
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
    return card(`https://${config.authDomain}/oauth2/authorize?${q}`, cookie);
  }

  // Step 2: Cognito's answer. Only the browser that used the link, and only a dev-access member
  async function finish(params, jar, k) {
    const t = Math.floor(now() / 1000);

    // Back from adding a passkey (no code): a signed-in device just goes home
    if (!params.get("code")) return signedIn(jar, k) ? redirect("/", []) : closed();

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
    if (request.uri === "/__signin") return start(params, cookies(request), k);
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
