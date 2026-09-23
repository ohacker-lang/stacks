import assert from "node:assert/strict";
import test from "node:test";
import worker from "./index.js";

const stackID = "486c448c-dcb6-4f2f-91d1-1d71419eb7a6";
const token = "65737075-8e4c-4dd2-af18-1c26cc59cb55";
const assets = { ASSETS: { fetch: async () => new Response("asset", { status: 200 }) } };

test("association file is direct JSON with only shared routes", async () => {
  const response = await worker.fetch(new Request("https://stacks.spot/.well-known/apple-app-site-association"), assets);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json");
  const body = await response.json();
  assert.equal(body.applinks.details[0].appID, "ZVV8KBVP26.com.owenhackero.stacks");
  assert.deepEqual(body.applinks.details[0].paths, ["/s/*", "/invite/*"]);
});

test("www redirects to the canonical hostname without dropping path or token", async () => {
  const response = await worker.fetch(new Request(`https://www.stacks.spot/s/${stackID}?token=${token}`), assets);
  assert.equal(response.status, 308);
  assert.equal(response.headers.get("location"), `https://stacks.spot/s/${stackID}?token=${token}`);
});

test("a shared Stack is fetched from Supabase and uses branded legal links", async () => {
  const originalFetch = globalThis.fetch;
  let upstream;
  globalThis.fetch = async (requestURL, options) => {
    upstream = { url: requestURL.toString(), accept: options.headers.Accept, proxy: options.headers["X-Stacks-Web-Proxy"], redirect: options.redirect };
    return new Response('<html><head></head><body><a href="https://iuovmgjcfwgwozfnsdgf.supabase.co/functions/v1/web-preview?page=privacy">Privacy</a></body></html>');
  };
  try {
    const response = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}?token=${token}`), assets);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow, noarchive");
    assert.equal(response.headers.get("referrer-policy"), "no-referrer");
    assert.match(upstream.url, new RegExp(`stackID=${stackID}`));
    assert.match(upstream.url, new RegExp(`token=${token}`));
    assert.equal(upstream.accept, "text/html");
    assert.equal(upstream.proxy, "1");
    assert.equal(upstream.redirect, "manual");
    assert.match(await response.text(), /href="\/privacy"/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("invalid and unavailable links never render private content", async () => {
  const invalid = await worker.fetch(new Request("https://stacks.spot/s/not-a-uuid"), assets);
  assert.equal(invalid.status, 404);
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("unavailable", { status: 404 });
  try {
    const unavailable = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}`), assets);
    assert.equal(unavailable.status, 404);
    assert.equal(unavailable.headers.get("x-robots-tag"), "noindex");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("unexpected upstream redirects are never followed", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(null, { status: 302, headers: { Location: "https://example.com/" } });
  try {
    const response = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}`), assets);
    assert.equal(response.status, 503);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("collaboration invitations are generic and not indexable", async () => {
  const response = await worker.fetch(new Request(`https://stacks.spot/invite/${token}`), assets);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow, noarchive");
  assert.match(await response.text(), /Open Stacks/);
});

test("the Beanies demo is a static asset, separate from live shared Stacks", async () => {
  let requestedPath;
  const demoAssets = { ASSETS: { fetch: async (request) => {
    requestedPath = new URL(request.url).pathname;
    return new Response("demo");
  } } };
  const response = await worker.fetch(new Request("https://stacks.spot/demo/beanies"), demoAssets);
  assert.equal(response.status, 200);
  assert.equal(requestedPath, "/demo-beanies");
});

test("each demo beanie has a direct product-detail route and unknown products fail closed", async () => {
  let requestedPath;
  const demoAssets = { ASSETS: { fetch: async (request) => {
    requestedPath = new URL(request.url).pathname;
    return new Response("product detail");
  } } };
  for (const slug of ["blue-logo", "bird-head-yellow", "blue-flame", "orange-peaks"]) {
    const product = await worker.fetch(new Request(`https://stacks.spot/demo/beanies/${slug}`), demoAssets);
    assert.equal(product.status, 200, `${slug} has a detail page`);
    assert.equal(requestedPath, "/demo-product");
  }
  const missing = await worker.fetch(new Request("https://stacks.spot/demo/beanies/unknown"), demoAssets);
  assert.equal(missing.status, 404);
  const removed = await worker.fetch(new Request("https://stacks.spot/demo/beanies/lime-stripe"), demoAssets);
  assert.equal(removed.status, 404);
});

test("download page is a static asset without inventing an App Store URL", async () => {
  let requestedPath;
  const downloadAssets = { ASSETS: { fetch: async (request) => {
    requestedPath = new URL(request.url).pathname;
    return new Response("download");
  } } };
  const response = await worker.fetch(new Request("https://stacks.spot/download"), downloadAssets);
  assert.equal(response.status, 200);
  assert.equal(requestedPath, "/download");
});

test("app-backed Stack page links to download while the App Store listing is pending", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('<html><head></head><body><div class="topline"><span>For iPhone · coming soon</span></div><section class="pitch"><h2>Make a Stack</h2><p>Try it.</p></section></body></html>');
  try {
    const response = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}`), assets);
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.equal((html.match(/href="\/download"/g) ?? []).length, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("public feed renders only sanitized IDs and escaped app content", async () => {
  const originalFetch = globalThis.fetch;
  let upstream;
  globalThis.fetch = async (url) => {
    upstream = url.toString();
    return new Response(JSON.stringify({ page: 1, hasMore: true, stacks: [
      { id: stackID, title: '<script>alert(1)</script>', author: { displayName: 'A & B' }, images: ['https://example.com/hat.png'] },
      { id: 'not-a-uuid', title: 'Should not appear', author: { displayName: 'Private' }, images: [] },
    ] }));
  };
  try {
    const response = await worker.fetch(new Request('https://stacks.spot/stacks'), assets);
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.match(upstream, /feed=public/);
    assert.match(html, new RegExp(`href="/s/${stackID}"`));
    assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
    assert.match(html, /A &amp; B/);
    assert.doesNotMatch(html, /Should not appear/);
    assert.match(html, /stacks\?page=2/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("public feed fails closed when its backend is unavailable", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('unavailable', { status: 503 });
  try {
    const response = await worker.fetch(new Request('https://stacks.spot/stacks'), assets);
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('x-robots-tag'), 'noindex');
  } finally {
    globalThis.fetch = originalFetch;
  }
});
