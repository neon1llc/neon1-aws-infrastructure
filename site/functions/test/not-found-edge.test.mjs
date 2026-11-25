// site/functions/test/not-found-edge.test.mjs - Fixtures for the origin-response function that hides S3's errors, run with node --test.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { handler } from "../not-found-edge.mjs";


/** An origin response as Lambda@Edge delivers it, carrying S3's own headers */
function origin(status) {
  return {
    Records: [{
      cf: {
        response: {
          status: String(status),
          statusDescription: "x",
          headers: {
            server: [{ key: "Server", value: "AmazonS3" }],
            "x-amz-request-id": [{ key: "x-amz-request-id", value: "ABC123" }],
            "content-type": [{ key: "Content-Type", value: "application/xml" }],
            "transfer-encoding": [{ key: "Transfer-Encoding", value: "chunked" }],
          },
        },
      },
    }],
  };
}

/** The site router's own not-found body, to prove both places serve the same page */
async function routerPage() {
  const code = readFileSync(new URL("../site-router.js", import.meta.url), "utf8").replace(/^import cf from 'cloudfront';$/m, "");
  const ctx = { cf: { kvs: () => ({ get: async () => "0123456789ab" }) } };
  vm.runInNewContext(code, ctx);
  const r = await ctx.handler({ request: { uri: "/nope", headers: { host: { value: "neon1.tech" } }, querystring: {} } });
  return r.body.data;
}


test("a missing file or forbidden key becomes the not-found page with a 404", async () => {
  for (const status of [403, 404, 400, 405, 416]) {
    const r = await handler(origin(status));
    assert.equal(r.status, "404");
    assert.equal(r.body, await routerPage());
    assert.match(r.headers["content-type"][0].value, /^text\/html/);
  }
});

test("nothing from S3 reaches the visitor", async () => {
  const r = await handler(origin(404));
  // Transfer-Encoding stays because CloudFront rejects a reply that drops it
  assert.deepEqual(Object.keys(r.headers).sort(), ["cache-control", "content-type", "transfer-encoding"]);
  assert.doesNotMatch(r.body, /NoSuchKey|AmazonS3|releases\/|RequestId|amz/i);
});

test("a server error is the same page as a 503", async () => {
  const r = await handler(origin(500));
  assert.equal(r.status, "503");
  assert.match(r.body, /data-text="503">503/);
  assert.match(r.body, /not-found\.css/);
  assert.doesNotMatch(r.body, /xml|S3|amz/i);
});

test("successful responses pass through untouched", async () => {
  const event = origin(200);
  assert.equal(await handler(event), event.Records[0].cf.response);
});
