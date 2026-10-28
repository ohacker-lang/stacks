import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import sharp from "sharp";
import worker from "./index.js";

const stackID = "486c448c-dcb6-4f2f-91d1-1d71419eb7a6";
const token = "65737075-8e4c-4dd2-af18-1c26cc59cb55";
const assets = { ASSETS: { fetch: async () => new Response("asset", { status: 200 }) } };

test("association file opens Stacks, invites, profiles and boards but not site pages", async () => {
  const response = await worker.fetch(new Request("https://stacks.spot/.well-known/apple-app-site-association"), assets);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("content-type"), "application/json");
  const body = await response.json();
  assert.equal(body.applinks.details[0].appID, "ZVV8KBVP26.com.owenhackero.stacks");
  const paths = body.applinks.details[0].paths;
  assert.deepEqual(paths.slice(0, 2), ["/s/*", "/invite/*"]);
  assert.deepEqual(paths.slice(-2), ["/*", "/*/*"]);
  for (const page of ["/", "/waitlist", "/stacks", "/privacy", "/terms", "/aliva", "/demo/*"]) {
    assert.ok(paths.indexOf(`NOT ${page}`) > 1 && paths.indexOf(`NOT ${page}`) < paths.indexOf("/*"), page);
  }
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

test("ordinary stacks.spot/username pages show only public profile data supplied by the backend", async () => {
  const originalFetch = globalThis.fetch;
  let requested;
  globalThis.fetch = async (url) => {
    requested = url.toString();
    return Response.json({
      profile: { displayName: "Alex", username: "alex", bio: "Beanies", avatarURL: null },
      stacks: [{ id: stackID, title: "Beanies", images: [] }],
    });
  };
  try {
    const response = await worker.fetch(new Request("https://stacks.spot/Alex"), assets);
    assert.equal(response.status, 200);
    assert.match(requested, /profile=alex/);
    assert.match(await response.text(), new RegExp(`/s/${stackID}`));
  } finally { globalThis.fetch = originalFetch; }
});

test("Aliva is a code-backed curator, not a backend account", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error("Aliva must not query Supabase"); };
  try {
    const catalog = await worker.fetch(new Request("https://stacks.spot/api/curated"), assets);
    assert.equal(catalog.status, 200);
    const data = await catalog.json();
    assert.equal(data.profile.username, "aliva");
    assert.equal(data.stacks[0].title, "Fall Reset");
    assert.equal(data.stacks[0].items.length, 19);
    assert.ok(data.stacks[0].items.every(item => item.sourceURL.startsWith("https://")));

    const profile = await worker.fetch(new Request("https://stacks.spot/aliva"), assets);
    assert.match(await profile.text(), /Curated by Stacks/);
    const stack = await worker.fetch(new Request(`https://stacks.spot/s/${data.stacks[0].id}`), assets);
    assert.equal(stack.status, 200);
    const stackHTML = await stack.text();
    assert.match(stackHTML, /Fall Reset/);
    assert.match(stackHTML, /height:2200px/);
    assert.match(stackHTML, /left:50%;top:2070px/);
    const item = data.stacks[0].items[5];
    const product = await worker.fetch(new Request(`https://stacks.spot/s/${data.stacks[0].id}/p/${item.id}`), assets);
    assert.equal(product.status, 200);
    assert.match(await product.text(), /saiehello\.com\/products\/the-vanity-case-1/);
  } finally { globalThis.fetch = originalFetch; }
});

test("curated products stay inside non-overlapping two-column placement boxes", async () => {
  const catalog = await worker.fetch(new Request("https://stacks.spot/api/curated"), assets);
  for (const stack of (await catalog.json()).stacks) {
    const response = await worker.fetch(new Request(`https://stacks.spot/s/${stack.id}`), assets);
    const html = await response.text();
    const positions = [...html.matchAll(/class="demo-item curated-item" style="left:(\d+)%;top:(\d+)px"/g)]
      .map(([, x, y]) => ({ x: Number(x), y: Number(y) }));
    assert.equal(positions.length, stack.items.length);
    for (let index = 0; index < positions.length; index += 1) {
      const position = positions[index];
      const inPage = index % 4;
      const pageCount = Math.min(4, stack.items.length - Math.floor(index / 4) * 4);
      const centered = pageCount === 1 || (pageCount === 3 && inPage === 2);
      assert.equal(position.x, centered ? 50 : inPage % 2 === 0 ? 25 : 75);
      if (index >= 2) assert.ok(position.y - positions[index - 2].y >= 205);
    }
  }

  // The prior regression was an image 3x taller than its correctly sized tile.
  const css = readFileSync(new URL("../public/site.css", import.meta.url), "utf8");
  const imageRule = css.match(/\.curated-stack-page \.demo-item img\{([^}]+)\}/)?.[1];
  assert.ok(imageRule, "Curated images need an explicit containment rule");
  const declarations = Object.fromEntries(imageRule.split(";").filter(Boolean).map(declaration => {
    const [property, ...value] = declaration.split(":");
    return [property.trim(), value.join(":").trim()];
  }));
  assert.equal(declarations.position, "absolute");
  assert.equal(declarations.width, "100%");
  assert.equal(declarations.height, "100%");
  assert.equal(declarations["object-fit"], "contain");

  assert.match(css, /\.public-grid\{grid-template-columns:repeat\(auto-fit,minmax\(min\(100%,270px\),390px\)\);justify-content:center\}/);
  assert.match(css, /\.public-stack-card\{position:relative;width:100%;max-width:390px;justify-self:center/);
});

test("every published curated product has a transparent cutout", async () => {
  const catalog = await worker.fetch(new Request("https://stacks.spot/api/curated"), assets);
  for (const stack of (await catalog.json()).stacks) for (const item of stack.items) {
    const imageURL = new URL(item.imageURL);
    assert.equal(imageURL.origin, "https://stacks.spot");
    assert.match(imageURL.pathname, /^\/assets\/[a-z0-9/_-]+\.(png|webp)$/);
    const file = new URL(`../public${imageURL.pathname}`, import.meta.url);
    const image = sharp(readFileSync(file));
    const { data, info } = await image.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const alphaAt = (x, y) => data[(y * info.width + x) * info.channels + 3];
    const corners = [[0, 0], [info.width - 1, 0], [0, info.height - 1], [info.width - 1, info.height - 1]];
    assert.ok(corners.every(([x, y]) => alphaAt(x, y) < 24), `${item.title} retained its photo background`);
    assert.ok(data.some((value, index) => index % info.channels === 3 && value > 240), `${item.title} is empty`);
  }
});

test("product detail cutouts are bounded by their stage before the title", async () => {
  const catalog = await worker.fetch(new Request("https://stacks.spot/api/curated"), assets);
  const stack = (await catalog.json()).stacks[0];
  const item = stack.items[1]; // Tall HydroJug image exposed the overflow.
  const response = await worker.fetch(new Request(`https://stacks.spot/s/${stack.id}/p/${item.id}`), assets);
  const html = await response.text();
  assert.ok(html.indexOf('class="product-stage"') < html.indexOf(`<h1>${item.title}</h1>`));

  const css = readFileSync(new URL("../public/site.css", import.meta.url), "utf8");
  const stage = css.match(/\.product-stage\{([^}]+)\}/)?.[1] ?? "";
  const image = css.match(/\.product-stage img\{([^}]+)\}/)?.[1] ?? "";
  assert.match(stage, /position:relative/);
  assert.match(stage, /height:min\(320px,38svh\)/);
  assert.match(image, /position:absolute/);
  assert.match(image, /height:100%/);
  assert.match(image, /max-height:100%/);
  assert.match(image, /object-fit:contain/);
});

test("a non-public username fails closed", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ error: "Profile unavailable" }, { status: 404 });
  try {
    const response = await worker.fetch(new Request("https://stacks.spot/privateuser"), assets);
    assert.equal(response.status, 404);
  } finally { globalThis.fetch = originalFetch; }
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

test("waitlist page is a static asset and old download links redirect", async () => {
  let requestedPath;
  const downloadAssets = { ASSETS: { fetch: async (request) => {
    requestedPath = new URL(request.url).pathname;
    return new Response("download");
  } } };
  const response = await worker.fetch(new Request("https://stacks.spot/waitlist"), downloadAssets);
  assert.equal(response.status, 200);
  assert.equal(requestedPath, "/download");
  const oldLink = await worker.fetch(new Request("https://stacks.spot/download"), downloadAssets);
  assert.equal(oldLink.status, 308);
  assert.equal(oldLink.headers.get("location"), "https://stacks.spot/waitlist");
});

test("app-backed Stack page links to waitlist while the App Store listing is pending", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('<html><head></head><body><div class="topline"><span>For iPhone · coming soon</span></div><section class="pitch"><h2>Make a Stack</h2><p>Try it.</p></section></body></html>');
  try {
    const response = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}`), assets);
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.equal((html.match(/href="\/waitlist"/g) ?? []).length, 2);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("waitlist availability checks use Supabase without exposing emails", async () => {
  const originalFetch = globalThis.fetch;
  let upstream;
  globalThis.fetch = async (url, options) => {
    upstream = { url, options };
    return Response.json(true);
  };
  try {
    const env = { ...assets, SUPABASE_URL: "https://example.supabase.co", SUPABASE_PUBLISHABLE_KEY: "public-key" };
    const response = await worker.fetch(new Request("https://stacks.spot/api/waitlist/availability?username=aliva"), env);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { available: true });
    assert.match(upstream.url, /rpc\/waitlist_username_available$/);
    assert.equal(JSON.parse(upstream.options.body).p_username, "aliva");
    const invalid = await worker.fetch(new Request("https://stacks.spot/api/waitlist/availability?username=ab"), env);
    assert.deepEqual(await invalid.json(), { available: false });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("waitlist signup validates input, writes one private RPC, and handles taken names", async () => {
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (url, options) => {
    calls += 1;
    assert.match(url, /rpc\/reserve_waitlist_username$/);
    assert.deepEqual(JSON.parse(options.body), { p_username: "aliva", p_email: "aliva@example.com" });
    return Response.json(calls === 1 ? "joined" : "username_taken");
  };
  try {
    const env = { ...assets, SUPABASE_URL: "https://example.supabase.co", SUPABASE_PUBLISHABLE_KEY: "public-key" };
    const headers = { Origin: "https://stacks.spot", "Content-Type": "application/json" };
    const input = { username: "Aliva", email: "Aliva@Example.com" };
    const joined = await worker.fetch(new Request("https://stacks.spot/api/waitlist", { method: "POST", headers, body: JSON.stringify(input) }), env);
    assert.equal(joined.status, 201);
    assert.deepEqual(await joined.json(), { status: "joined" });
    const taken = await worker.fetch(new Request("https://stacks.spot/api/waitlist", { method: "POST", headers, body: JSON.stringify(input) }), env);
    assert.equal(taken.status, 409);
    assert.deepEqual(await taken.json(), { status: "username_taken" });
    const invalid = await worker.fetch(new Request("https://stacks.spot/api/waitlist", { method: "POST", headers, body: JSON.stringify({ username: "a", email: "bad" }) }), env);
    assert.equal(invalid.status, 400);
    assert.equal(calls, 2);
    const crossSite = await worker.fetch(new Request("https://stacks.spot/api/waitlist", { method: "POST", headers: { Origin: "https://elsewhere.test", "Content-Type": "application/json" }, body: JSON.stringify(input) }), env);
    assert.equal(crossSite.status, 403);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("public legal pages show the support domain address", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('<html><head></head><body><a href="mailto:trystacks@gmail.com">trystacks@gmail.com</a></body></html>');
  try {
    const response = await worker.fetch(new Request("https://stacks.spot/support"), assets);
    const html = await response.text();
    assert.match(html, /mailto:support@stacks\.spot/);
    assert.doesNotMatch(html, /trystacks@gmail\.com/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("demo products show saved prices without inventing unavailable prices", () => {
  const productHTML = readFileSync(new URL("../public/demo-product.html", import.meta.url), "utf8");
  const siteJS = readFileSync(new URL("../public/site.js", import.meta.url), "utf8");
  assert.match(productHTML, /id="demo-product-price"/);
  for (const expected of ["$25.00", "€17.99", "$88.00", "$60.00", "€24.95", "From $85", "$30.00"]) {
    assert.ok(siteJS.includes(expected), `${expected} shown in catalog`);
  }
  assert.match(siteJS, /"black-columbia"[^\n]+"Out of stock"/);
  assert.match(siteJS, /"green-stripe"[^\n]+"Check Amazon"/);
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
    assert.match(html, /class="discover-feed"/);
    assert.match(html, /class="discover-stack-card"/);
    assert.match(html, /class="discover-card-heading"/);
    assert.match(html, /class="discover-card-footer"/);
    const card = html.match(/<article class="discover-stack-card">([\s\S]*?)<\/article>/)?.[1] ?? "";
    assert.ok(card.indexOf("discover-card-heading") < card.indexOf("public-stack-art"));
    assert.match(card, /public-stack-cutout-1/);
    assert.doesNotMatch(html, /Should not appear/);
    assert.match(html, /stacks\?page=2/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("public feed falls back to code-backed curation when its backend is unavailable", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response('unavailable', { status: 503 });
  try {
    const response = await worker.fetch(new Request('https://stacks.spot/stacks'), assets);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.match(html, /Fall Reset/);
    assert.doesNotMatch(html, /Private Stack/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

const itemID = "0d3e7c1a-5b8f-4c2e-9a71-3f6b2d8e4c10";
const boardStack = {
  id: stackID,
  title: "Fall <Fits>",
  slug: "fall-fits",
  visibility: "public",
  updatedAt: new Date().toISOString(),
  wishlistMode: false,
  author: { displayName: "Neeha", username: "Neeha", avatarURL: null },
  items: [{ id: itemID, title: "Samba OG", brand: "adidas", price: 100, currencyCode: "USD", buyURL: "https://www.adidas.com/us/samba", imageURL: "https://example.supabase.co/signed/samba.png" }],
};

test("every account gets a profile page, even with no public Stacks", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ profile: { displayName: "Neeha", username: "neeha", bio: "", avatarURL: null, stackCount: 0, itemCount: 0 }, stacks: [] });
  try {
    const response = await worker.fetch(new Request("https://stacks.spot/neeha"), assets);
    assert.equal(response.status, 200);
    const html = await response.text();
    assert.match(html, /No public Stacks yet/);
    assert.match(html, /<link rel="canonical" href="https:\/\/stacks\.spot\/neeha">/);
  } finally { globalThis.fetch = originalFetch; }
});

test("profile boards link by username and slug, falling back to IDs for duplicate titles", async () => {
  const otherID = "7f1c2b3a-4d5e-4f60-8a71-b2c3d4e5f607";
  const thirdID = "8a2d3c4b-5e6f-4a71-9b82-c3d4e5f60718";
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({
    profile: { displayName: "Neeha", username: "neeha", bio: "Things I love", avatarURL: null, shareImageURL: "https://example.supabase.co/signed/cover.png" },
    stacks: [
      { id: stackID, title: "Fall Fits", slug: "fall-fits", itemCount: 3, images: ["https://example.supabase.co/a.png", "javascript:alert(1)"], wishlistMode: false },
      { id: otherID, title: "Lamps", slug: "lamps", itemCount: 1, images: [], wishlistMode: true },
      { id: thirdID, title: "Lamps", slug: "lamps", itemCount: 0, images: [], wishlistMode: false },
    ],
  });
  try {
    const html = await (await worker.fetch(new Request("https://stacks.spot/neeha"), assets)).text();
    assert.match(html, /href="\/neeha\/fall-fits"/);
    assert.match(html, new RegExp(`href="/s/${otherID}"`));
    assert.match(html, new RegExp(`href="/s/${thirdID}"`));
    assert.match(html, /<strong>3<\/strong> Stacks · <strong>4<\/strong> finds/);
    assert.match(html, /Wishlist/);
    assert.match(html, /og:image" content="https:\/\/example\.supabase\.co\/signed\/cover\.png"/);
    assert.doesNotMatch(html, /javascript:/);
  } finally { globalThis.fetch = originalFetch; }
});

test("a public board renders as escaped pins with a canonical username URL", async () => {
  const originalFetch = globalThis.fetch;
  let requested;
  globalThis.fetch = async (url, options) => {
    requested = { url: url.toString(), accept: options.headers.Accept };
    return Response.json({ stack: boardStack });
  };
  try {
    const response = await worker.fetch(new Request("https://stacks.spot/neeha/fall-fits"), assets);
    assert.equal(response.status, 200);
    assert.match(requested.url, /stackUsername=neeha/);
    assert.match(requested.url, /stackSlug=fall-fits/);
    assert.equal(requested.accept, "application/json");
    const html = await response.text();
    assert.match(html, /Fall &lt;Fits&gt;/);
    assert.match(html, new RegExp(`href="/s/${stackID}/p/${itemID}"`));
    assert.match(html, /\$100/);
    assert.match(html, /href="https:\/\/stacks\.spot\/neeha\/fall-fits"/);
    assert.match(html, /href="\/neeha"/);
  } finally { globalThis.fetch = originalFetch; }
});

test("wishlist boards keep the claim-enabled preview page", async () => {
  const originalFetch = globalThis.fetch;
  const accepts = [];
  globalThis.fetch = async (url, options) => {
    accepts.push(options.headers.Accept);
    return options.headers.Accept === "application/json"
      ? Response.json({ stack: { ...boardStack, wishlistMode: true } })
      : new Response("<html><head></head><body>Claim a gift</body></html>");
  };
  try {
    const html = await (await worker.fetch(new Request(`https://stacks.spot/s/${stackID}`), assets)).text();
    assert.deepEqual(accepts, ["application/json", "text/html"]);
    assert.match(html, /Claim a gift/);
  } finally { globalThis.fetch = originalFetch; }
});

test("a pin page shows the find and only follows https buy links", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => Response.json({ stack: { ...boardStack, items: [{ ...boardStack.items[0] }, { ...boardStack.items[0], id: stackID, buyURL: "http://insecure.example" }] } });
  try {
    const pin = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}/p/${itemID}`), assets);
    assert.equal(pin.status, 200);
    const html = await pin.text();
    assert.match(html, /View at adidas\.com/);
    assert.match(html, /Samba OG/);
    const insecure = await (await worker.fetch(new Request(`https://stacks.spot/s/${stackID}/p/${stackID}`), assets)).text();
    assert.doesNotMatch(insecure, /insecure\.example/);
    const missing = await worker.fetch(new Request(`https://stacks.spot/s/${stackID}/p/7f1c2b3a-4d5e-4f60-8a71-b2c3d4e5f607`), assets);
    assert.equal(missing.status, 404);
  } finally { globalThis.fetch = originalFetch; }
});
