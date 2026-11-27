// site/functions/test/dev-auth.test.mjs - Fixtures for dev.neon1.tech's sign-in (dev-auth.mjs), run
// with node --test. The keys and Cognito's token endpoint are fakes; CloudFront-shaped events in.

import { test } from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { readFileSync } from "node:fs";
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
let pool;          // (action, body) => Cognito API JSON, or throws
let called = [];
const handler = makeHandler({
  config,
  keys: async () => keys,
  post: async (url, form) => { posted.push({ url, form }); return answer(form); },
  idp: async (action, body) => { called.push({ action, body }); return pool(action, body); },
});

/** A form post to /__signin, as CloudFront hands it over */
function submit(fields, querystring = `k=${keys.link}`) {
  const e = event("/__signin", querystring);
  Object.assign(e.Records[0].cf.request, { method: "POST", body: { encoding: "base64", data: Buffer.from(String(new URLSearchParams(fields))).toString("base64"), inputTruncated: false } });
  return handler(e);
}
const refuse = (name) => () => { throw Object.assign(new Error(name), { name }); };

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

/** Step 1: the state from the redirect and the cookie it sets */
async function begin() {
  const r = await handler(event("/__signin", `k=${keys.link}`));
  assert.equal(r.status, "200");
  const loc = new URL(/<a href="([^"]+)">Use a passkey/.exec(r.body)[1].replace(/&amp;/g, "&"));
  const cookie = r.headers["set-cookie"][0].value.split(";")[0];
  return { r, loc, state: loc.searchParams.get("state"), cookie };
}

const set = (r) => r.headers["set-cookie"].map((h) => h.value);


// --- Step 1: the private sign-in address ---


test("without the right link key /__signin is the not-found page, signed in or not", async () => {
  const exp = Math.floor(Date.now() / 1000) + 100;
  const n1dev = `n1dev=${exp}.${crypto.createHmac("sha256", keys.session).update(`n1dev|${exp}`).digest("hex")}`;
  const missing = (await handler(event("/anything-else"))).body;
  for (const qs of ["", "k=", "k=nope", `k=${keys.link}x`]) {
    for (const jar of ["", n1dev]) {
      const r = await handler(event("/__signin", qs, jar));
      assert.equal(r.status, "404", qs);
      assert.equal(r.body, missing);
    }
  }
});

test("the page's styles are exactly signin.css, so the header's hash allows them", async () => {
  const { r } = await begin();
  assert.equal(/<style>([\s\S]*)<\/style>/.exec(r.body)[1], readFileSync(new URL("../signin.css", import.meta.url), "utf8"));
  assert.equal(/<script type="module">([\s\S]*)<\/script>/.exec(r.body)[1], readFileSync(new URL("../signin.js", import.meta.url), "utf8"));
  assert.ok(!r.body.includes(keys.link));
  // A viewer-request function may answer with at most 40 KB
  assert.ok(Buffer.byteLength(r.body) < 40_000);
});

test("the link's card starts a PKCE sign-in at the dev pool, bound to this browser", async () => {
  const { r, loc, state, cookie } = await begin();
  assert.equal(loc.origin + loc.pathname, "https://auth-dev.example/oauth2/authorize");
  assert.equal(loc.searchParams.get("client_id"), "client123");
  assert.equal(loc.searchParams.get("redirect_uri"), "https://dev.example/__auth");
  assert.equal(loc.searchParams.get("code_challenge_method"), "S256");
  assert.equal(loc.searchParams.get("nonce"), state);
  assert.match(cookie, /^n1auth=/);
  const attrs = r.headers["set-cookie"][0].value;
  for (const a of ["HttpOnly", "Secure", "Path=/__auth", "Max-Age=3600"]) assert.match(attrs, new RegExp(a));
  // The challenge is the verifier the cookie carries, hashed
  const verifier = cookie.split("=")[1].split(".")[1];
  assert.equal(loc.searchParams.get("code_challenge"), crypto.createHash("sha256").update(verifier).digest("base64url"));
});

test("a signed-in device that opens /__signin goes straight home", async () => {
  const exp = Math.floor(Date.now() / 1000) + 100;
  const n1dev = `n1dev=${exp}.${crypto.createHmac("sha256", keys.session).update(`n1dev|${exp}`).digest("hex")}`;
  assert.equal((await handler(event("/__signin", `k=${keys.link}`, n1dev))).headers.location[0].value, "/");
});


// --- The emailed code, on neon1's own forms ---


test("a post without the link key gets the 404 and never reaches Cognito", async () => {
  called = [];
  for (const qs of ["", "k=nope"]) assert.equal((await submit({ username: "a@neon1.example" }, qs)).status, "404");
  assert.equal(called.length, 0);
});

test("the email sends a code; the code step is marked up for password managers", async () => {
  called = [];
  pool = () => ({ ChallengeName: "EMAIL_OTP", Session: "sess-1" });
  const r = await submit({ username: " a@neon1.example " });
  assert.equal(r.status, "200");
  assert.deepEqual(called[0].body.AuthParameters, { USERNAME: "a@neon1.example", PREFERRED_CHALLENGE: "EMAIL_OTP" });
  for (const part of ['name="username" autocomplete="username" value="a@neon1.example"', 'name="session" value="sess-1"', 'name="code" type="text" inputmode="numeric" autocomplete="one-time-code"']) assert.ok(r.body.includes(part), part);
  assert.ok(!r.body.includes(keys.link));
  assert.ok(Buffer.byteLength(r.body) < 40_000);
});

test("an account offered a choice is asked for the emailed code", async () => {
  called = [];
  pool = (action) => (action === "InitiateAuth" ? { ChallengeName: "SELECT_CHALLENGE", Session: "pick" } : { ChallengeName: "EMAIL_OTP", Session: "sess-2" });
  assert.match((await submit({ username: "a@neon1.example" })).body, /value="sess-2"/);
  assert.equal(called[1].body.ChallengeResponses.ANSWER, "EMAIL_OTP");
});

test("a member's right code gets the cookie and goes home", async () => {
  pool = () => ({ AuthenticationResult: { IdToken: idToken(undefined) } });
  called = [];
  const r = await submit({ username: "a@neon1.example", session: "sess-1", code: "1234 5678" });
  assert.equal(r.status, "303");
  assert.equal(r.headers.location[0].value, "/");
  assert.match(set(r)[0], /^n1dev=\d+\.[0-9a-f]{64}; Max-Age=2592000; Path=\/; HttpOnly; Secure/);
  assert.equal(called[0].body.ChallengeResponses.EMAIL_OTP_CODE, "12345678");
});

test("a right code from outside the group, or a token for elsewhere, gets the 404", async () => {
  for (const extra of [{ "cognito:groups": ["other"] }, { aud: "other" }, { iss: "https://evil" }, { token_use: "access" }, { exp: 1 }]) {
    pool = () => ({ AuthenticationResult: { IdToken: idToken(undefined, extra) } });
    const r = await submit({ username: "a@neon1.example", session: "s", code: "1" });
    assert.equal(r.status, "404", JSON.stringify(extra));
  }
});

test("a wrong code asks again; an expired one or a limit goes back to the email", async () => {
  const typed = { username: "a@neon1.example", session: "sess-1", code: "00000000" };
  pool = refuse("CodeMismatchException");
  assert.match((await submit(typed)).body, /didn&#39;t match[\s\S]*value="sess-1"/);
  pool = refuse("NotAuthorizedException");
  assert.match((await submit(typed)).body, /code has expired[\s\S]*name="signin"/);
  pool = refuse("LimitExceededException");
  assert.match((await submit(typed)).body, /Too many tries[\s\S]*name="signin"/);
});

test("send a new code starts over for the same email, and typed text is escaped", async () => {
  called = [];
  pool = () => ({ ChallengeName: "EMAIL_OTP", Session: "sess-3" });
  const r = await submit({ username: '"><script>x</script>', session: "old", again: "1" });
  assert.equal(called[0].action, "InitiateAuth");
  assert.ok(!r.body.includes("<script>x"));
});


// --- A passkey: back from Cognito ---


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

test("no sign-in cookie, a forged or expired one, or a mismatched state never reaches Cognito", async () => {
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

test("missing or short keys keep everything closed, as the not-found page", async () => {
  const weak = makeHandler({ config, keys: async () => ({ link: "", session: "" }), post: async () => ({}) });
  assert.equal((await weak(event("/__signin", "k="))).status, "404");
  const broken = makeHandler({ config, keys: async () => { throw new Error("ssm down"); }, post: async () => ({}) });
  assert.equal((await broken(event("/__signin", `k=${keys.link}`))).status, "404");
  const r = await handler(event("/anything-else"));
  assert.equal(r.status, "404");
  const router = readFileSync(new URL("../site-router.js", import.meta.url), "utf8");
  const page = (code) => /NOT_FOUND = ([\s\S]*?<\/html>';)/.exec(code)[1];
  assert.equal(r.body, new Function("return " + page(router))());
});
