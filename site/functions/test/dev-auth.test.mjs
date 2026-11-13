// site/functions/test/dev-auth.test.mjs - Fixtures for dev.neon1.tech's sign-in (dev-auth.mjs), run
// with node --test. The keys and Cognito's token endpoint are fakes; CloudFront-shaped events in.

import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { makeHandler } from "../dev-auth.mjs";


// --- Fakes: two keys, a config like Terraform's, and a token endpoint that answers as told ---


const keys = { link: "L".repeat(43), session: "S".repeat(43) };
const config = {
  authDomain: "auth-dev.example",
  clientId: "client123",
  issuer: "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_pool",
  publicUrl: "https://dev.example",
  group: "dev-access",
};

let answer;        // (form) => token endpoint JSON, or throws
let posted = [];
const handler = makeHandler({
  config,
  keys: async () => keys,
  post: async (url, form) => { posted.push({ url, form }); return answer(form); },
});

/** A viewer request for a path, query string, and cookie header */
function event(uri, querystring = "", cookie = "") {
  const headers = cookie ? { cookie: [{ key: "Cookie", value: cookie }] } : {};
  return { Records: [{ cf: { request: { uri, querystring, headers } } }] };
}

/** An unsigned JWT carrying these claims (the endpoint is trusted over TLS, so no signature is checked) */
const jwt = (c) => `x.${Buffer.from(JSON.stringify(c)).toString("base64url")}.y`;

/** The ID token Cognito would give a person, with overrides */
function idToken(state, extra = {}) {
  return jwt({ iss: config.issuer, aud: config.clientId, token_use: "id", nonce: state, exp: Math.floor(Date.now() / 1000) + 300, "cognito:groups": ["dev-access"], ...extra });
}

/** Step 1 with the right link: the state from the redirect and the cookie it sets */
async function begin() {
  const r = await handler(event("/__signin", `k=${keys.link}`));
  assert.equal(r.status, "302");
  const loc = new URL(r.headers.location[0].value);
  const cookie = r.headers["set-cookie"][0].value.split(";")[0];
  return { r, loc, state: loc.searchParams.get("state"), cookie };
}

const set = (r) => r.headers["set-cookie"].map((h) => h.value);


// --- Step 1: the secret link ---


test("a wrong, empty, or missing link key gets the bare 404", async () => {
  for (const qs of ["", "k=", "k=nope", `k=${keys.link}x`]) {
    const r = await handler(event("/__signin", qs));
    assert.equal(r.status, "404", qs);
    assert.equal(r.body, "Not found");
    assert.equal(r.headers["cache-control"][0].value, "no-store");
  }
});

test("the right link starts a PKCE sign-in at the dev pool, bound to this browser", async () => {
  const { r, loc, state, cookie } = await begin();
  assert.equal(loc.origin + loc.pathname, "https://auth-dev.example/oauth2/authorize");
  assert.equal(loc.searchParams.get("client_id"), "client123");
  assert.equal(loc.searchParams.get("redirect_uri"), "https://dev.example/__auth");
  assert.equal(loc.searchParams.get("code_challenge_method"), "S256");
  assert.equal(loc.searchParams.get("nonce"), state);
  assert.match(cookie, /^n1auth=/);
  const attrs = r.headers["set-cookie"][0].value;
  for (const a of ["HttpOnly", "Secure", "Path=/__auth", "Max-Age=600"]) assert.match(attrs, new RegExp(a));
  // The challenge is the verifier the cookie carries, hashed
  const verifier = cookie.split("=")[1].split(".")[1];
  assert.equal(loc.searchParams.get("code_challenge"), crypto.createHash("sha256").update(verifier).digest("base64url"));
  // The link key itself never leaves in the redirect
  assert.ok(!r.headers.location[0].value.includes(keys.link));
});


// --- Step 2: back from Cognito ---


test("a dev-access member gets the 30-day cookie dev-gate.js accepts", async () => {
  const { state, cookie } = await begin();
  answer = () => ({ id_token: idToken(state) });
  posted = [];
  const r = await handler(event("/__auth", `code=abc&state=${state}`, cookie));
  assert.equal(r.status, "302");
  assert.equal(r.headers.location[0].value, "/");
  const [gate, cleared] = set(r);
  const [exp, mac] = gate.split(";")[0].split("=")[1].split(".");
  assert.equal(mac, crypto.createHmac("sha256", keys.session).update(`n1dev|${exp}`).digest("hex"));
  assert.match(gate, /Max-Age=2592000; Path=\/; HttpOnly; Secure/);
  assert.match(cleared, /^n1auth=; Max-Age=0/);
  // The exchange used the verifier and the registered callback
  assert.equal(posted[0].url, "https://auth-dev.example/oauth2/token");
  assert.equal(posted[0].form.redirect_uri, "https://dev.example/__auth");
  assert.equal(posted[0].form.code_verifier, cookie.split("=")[1].split(".")[1]);
});

test("someone outside the group, or a token for another client or pool, gets the 404", async () => {
  const cases = [{ "cognito:groups": ["other"] }, { "cognito:groups": undefined }, { aud: "other" }, { iss: "https://evil" }, { token_use: "access" }, { nonce: "x" }, { exp: 1 }];
  for (const extra of cases) {
    const { state, cookie } = await begin();
    answer = () => ({ id_token: idToken(state, extra) });
    assert.equal((await handler(event("/__auth", `code=abc&state=${state}`, cookie))).status, "404", JSON.stringify(extra));
  }
});

test("no link cookie, a forged or expired one, or a mismatched state never reaches Cognito", async () => {
  const { state, cookie } = await begin();
  answer = () => { throw new Error("should not be called"); };
  posted = [];
  const [name, value] = cookie.split("=");
  const [s, v, exp] = value.split(".");
  const forged = `${name}=${s}.${v}.${exp}.${"0".repeat(64)}`;
  const oldExp = Math.floor(Date.now() / 1000) - 1;
  const expired = `${name}=${s}.${v}.${oldExp}.${crypto.createHmac("sha256", keys.session).update(`n1auth|${s}.${v}.${oldExp}`).digest("hex")}`;
  for (const [qs, c] of [[`code=a&state=${state}`, ""], [`code=a&state=${state}`, forged], [`code=a&state=${state}`, expired], ["code=a&state=other", cookie]]) {
    assert.equal((await handler(event("/__auth", qs, c))).status, "404", c || "no cookie");
  }
  assert.equal(posted.length, 0);
});

test("a failed code exchange gets the 404", async () => {
  const { state, cookie } = await begin();
  answer = () => { throw new Error("400"); };
  assert.equal((await handler(event("/__auth", `code=abc&state=${state}`, cookie))).status, "404");
  answer = () => ({ id_token: "garbage" });
  const again = await begin();
  assert.equal((await handler(event("/__auth", `code=abc&state=${again.state}`, again.cookie))).status, "404");
});

test("back from adding a passkey: a signed-in device goes home, anyone else gets the 404", async () => {
  const exp = Math.floor(Date.now() / 1000) + 100;
  const n1dev = `n1dev=${exp}.${crypto.createHmac("sha256", keys.session).update(`n1dev|${exp}`).digest("hex")}`;
  assert.equal((await handler(event("/__auth", "", n1dev))).headers.location[0].value, "/");
  assert.equal((await handler(event("/__auth", ""))).status, "404");
  assert.equal((await handler(event("/__auth", "", `n1dev=${exp}.beef`))).status, "404");
});

test("missing or short keys keep everything closed", async () => {
  const weak = makeHandler({ config, keys: async () => ({ link: "", session: "" }), post: async () => ({}) });
  assert.equal((await weak(event("/__signin", "k="))).status, "404");
  const broken = makeHandler({ config, keys: async () => { throw new Error("ssm down"); }, post: async () => ({}) });
  assert.equal((await broken(event("/__signin", `k=${keys.link}`))).status, "404");
  assert.equal((await handler(event("/anything-else"))).status, "404");
});
