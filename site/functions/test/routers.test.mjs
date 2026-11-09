// site/functions/test/routers.test.mjs - Semantic fixtures for the two CloudFront Functions, run with
// node --test. The functions are plain ES5 scripts, so each is loaded into its own context and its
// handler called with CloudFront-shaped events. Runtime-specific checks stay with CloudFront itself.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

/** The file's handler, loaded the way CloudFront runs a function: a script with a global handler */
function load(name) {
  const ctx = {};
  vm.runInNewContext(readFileSync(new URL(`../${name}`, import.meta.url), "utf8"), ctx);
  return ctx.handler;
}

/** A viewer request for a path, host, and query (CloudFront's querystring shape) */
function event(uri, { host = "neon1.tech", qs = {} } = {}) {
  return { request: { uri, headers: { host: { value: host } }, querystring: qs } };
}

const portal = load("portal-router.js");
const site = load("site-router.js");

test("the bare portal path keeps its query when it redirects", () => {
  const r = portal(event("/1NEON", { qs: { email: { value: "a%40b.example" }, next: { value: "" } } }));
  assert.equal(r.statusCode, 301);
  assert.equal(r.headers.location.value, "/1NEON/?email=a%40b.example&next");
  assert.equal(portal(event("/1NEON")).headers.location.value, "/1NEON/");
});

test("repeated query keys survive the www redirect", () => {
  const r = portal(event("/1NEON/me", { host: "www.neon1.tech", qs: { a: { value: "1", multiValue: [{ value: "1" }, { value: "2" }] } } }));
  assert.equal(r.headers.location.value, "https://neon1.tech/1NEON/me?a=1&a=2");
});

test("app routes get the shell, files pass through, encoded names stay intact", () => {
  assert.equal(portal(event("/1NEON/o/acme/workspace")).uri, "/1NEON/index.html");
  assert.equal(portal(event("/1NEON/")).uri, "/1NEON/index.html");
  assert.equal(portal(event("/1NEON/assets/app-1a2b.js")).uri, "/1NEON/assets/app-1a2b.js");
  assert.equal(portal(event("/1NEON/assets/a%20b.png")).uri, "/1NEON/assets/a%20b.png");
});

test("paths that only start with the letters 1NEON are not the portal", () => {
  for (const uri of ["/1NEONx", "/1NEON.html", "/1NEONS/a"]) {
    const r = portal(event(uri));
    assert.equal(r.statusCode, 404, uri);
    assert.equal(r.headers["cache-control"].value, "no-store");
  }
});

test("the site router keeps its home page, files, www redirect, and not-found page", () => {
  assert.equal(site(event("/")).uri, "/");
  assert.equal(site(event("/shared/neon1.css")).uri, "/shared/neon1.css");
  assert.equal(site(event("/about", { host: "www.neon1.tech", qs: { x: { value: "1" } } })).headers.location.value, "https://neon1.tech/about?x=1");
  assert.equal(site(event("/nope")).statusCode, 404);
});
