// site/functions/test/routers.test.mjs - Semantic fixtures for the two CloudFront Functions, run with
// node --test. The functions are plain ES5 scripts, so each is loaded into its own context and its
// handler called with CloudFront-shaped events. Runtime-specific checks stay with CloudFront itself.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

// What the fake key value store answers for "release": a value, or an Error to throw like a failed read
const store = { release: "0123456789ab" };

/** The file's handler, loaded the way CloudFront runs a function: a script with a global handler.
 * The runtime's `import cf from 'cloudfront'` is replaced by a fake whose store reads `store` */
function load(name) {
  const cf = { kvs: () => ({ get: async (key) => { const v = store[key]; if (v instanceof Error) throw v; if (v === undefined) throw new Error("not found"); return v; } }) };
  const ctx = { cf };
  const code = readFileSync(new URL(`../${name}`, import.meta.url), "utf8").replace(/^import cf from 'cloudfront';$/m, "");
  vm.runInNewContext(code, ctx);
  return ctx.handler;
}

/** A viewer request for a path, host, and query (CloudFront's querystring shape) */
function event(uri, { host = "neon1.tech", qs = {} } = {}) {
  return { request: { uri, headers: { host: { value: host } }, querystring: qs } };
}

const portal = load("portal-router.js");
const site = load("site-router.js");

test("the bare portal path keeps its query when it redirects", async () => {
  const r = (await portal(event("/1NEON", { qs: { email: { value: "a%40b.example" }, next: { value: "" } } })));
  assert.equal(r.statusCode, 301);
  assert.equal(r.headers.location.value, "/1NEON/?email=a%40b.example&next");
  assert.equal((await portal(event("/1NEON"))).headers.location.value, "/1NEON/");
});

test("repeated query keys survive the www redirect", async () => {
  const r = (await portal(event("/1NEON/me", { host: "www.neon1.tech", qs: { a: { value: "1", multiValue: [{ value: "1" }, { value: "2" }] } } })));
  assert.equal(r.headers.location.value, "https://neon1.tech/1NEON/me?a=1&a=2");
});

test("app routes get the shell, files pass through, encoded names stay intact", async () => {
  assert.equal((await portal(event("/1NEON/o/acme/workspace"))).uri, "/1NEON/index.html");
  assert.equal((await portal(event("/1NEON/"))).uri, "/1NEON/index.html");
  assert.equal((await portal(event("/1NEON/assets/app-1a2b.js"))).uri, "/1NEON/assets/app-1a2b.js");
  assert.equal((await portal(event("/1NEON/assets/a%20b.png"))).uri, "/1NEON/assets/a%20b.png");
});

test("paths that only start with the letters 1NEON are not the portal", async () => {
  for (const uri of ["/1NEONx", "/1NEON.html", "/1NEONS/a"]) {
    const r = (await portal(event(uri)));
    assert.equal(r.statusCode, 404, uri);
    assert.equal(r.headers["cache-control"].value, "no-store");
  }
});

test("the site router keeps its home page, files, www redirect, and not-found page", async () => {
  assert.equal((await site(event("/"))).uri, "/releases/0123456789ab/index.html");
  assert.equal((await site(event("/shared/neon1.css"))).uri, "/releases/0123456789ab/shared/neon1.css");
  assert.equal((await site(event("/about", { host: "www.neon1.tech", qs: { x: { value: "1" } } }))).headers.location.value, "https://neon1.tech/about?x=1");
  assert.equal((await site(event("/nope"))).statusCode, 404);
});

test("/faqs, with or without its slash, redirects to the questions in the knowledge center", async () => {
  for (const uri of ["/faqs", "/faqs/"]) {
    const r = (await site(event(uri)));
    assert.equal(r.statusCode, 301);
    assert.equal(r.headers.location.value, "/knowledge/faq/working-with-neon1/");
  }
});

test("knowledge center folders serve their index page, and gain a slash when they lack one", async () => {
  assert.equal((await site(event("/knowledge/"))).uri, "/releases/0123456789ab/knowledge/index.html");
  assert.equal((await site(event("/knowledge/forms/intake/"))).uri, "/releases/0123456789ab/knowledge/forms/intake/index.html");
  assert.equal((await site(event("/knowledge/forms/intake/neon1-intake.pdf"))).uri, "/releases/0123456789ab/knowledge/forms/intake/neon1-intake.pdf");
  const bare = (await site(event("/knowledge", { qs: { q: { value: "backup" } } })));
  assert.equal(bare.statusCode, 301);
  assert.equal(bare.headers.location.value, "/knowledge/?q=backup");
  assert.equal((await site(event("/knowledge/forms/intake"))).headers.location.value, "/knowledge/forms/intake/");
  assert.equal((await site(event("/knowledgebase"))).statusCode, 404);
  // A shelf's folder has no page of its own: it goes to that shelf on the front page
  const shelf = await site(event("/knowledge/faq/"));
  assert.equal(shelf.statusCode, 301);
  assert.equal(shelf.headers.location.value, "/knowledge/#faq");
  assert.equal((await site(event("/knowledge/faq"))).headers.location.value, "/knowledge/faq/");
  assert.equal((await site(event("/knowledge/x/", { host: "www.neon1.tech" }))).headers.location.value, "https://neon1.tech/knowledge/x/");
});

test("blog folders serve their index page, and gain a slash when they lack one", async () => {
  assert.equal((await site(event("/blog/"))).uri, "/releases/0123456789ab/blog/index.html");
  assert.equal((await site(event("/blog/some-post/"))).uri, "/releases/0123456789ab/blog/some-post/index.html");
  assert.equal((await site(event("/blog/feed.xml"))).uri, "/releases/0123456789ab/blog/feed.xml");
  assert.equal((await site(event("/blog"))).headers.location.value, "/blog/");
  assert.equal((await site(event("/blog/some-post"))).headers.location.value, "/blog/some-post/");
  assert.equal((await site(event("/blogs"))).statusCode, 404);
});

test("mta-sts serves only its policy file and sends everything else to the apex", async () => {
  assert.equal((await site(event("/.well-known/mta-sts.txt", { host: "mta-sts.neon1.tech" }))).uri, "/.well-known/mta-sts.txt");
  assert.equal((await site(event("/", { host: "mta-sts.neon1.tech" }))).headers.location.value, "https://neon1.tech/");
  assert.equal((await site(event("/.well-known/security.txt", { host: "mta-sts.neon1.tech" }))).headers.location.value, "https://neon1.tech/.well-known/security.txt");
  assert.equal((await portal(event("/1NEON/me", { host: "mta-sts.neon1.tech" }))).headers.location.value, "https://neon1.tech/1NEON/me");
});


test("pages and files come from the live release; fonts, media, and .well-known stay shared", async () => {
  assert.equal((await site(event("/js/views.js"))).uri, "/releases/0123456789ab/js/views.js");
  assert.equal((await site(event("/fonts/a.woff2"))).uri, "/fonts/a.woff2");
  assert.equal((await site(event("/media/room.glb"))).uri, "/media/room.glb");
  assert.equal((await site(event("/.well-known/security.txt"))).uri, "/.well-known/security.txt");
});

test("without a valid release the bucket's top level serves, as before releases", async () => {
  for (const value of [undefined, new Error("store unavailable"), "../../etc", "0123456789AB"]) {
    store.release = value;
    assert.equal((await site(event("/"))).uri, "/", String(value));
    assert.equal((await site(event("/knowledge/"))).uri, "/knowledge/index.html", String(value));
  }
  store.release = "0123456789ab";
});
