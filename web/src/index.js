import { curatedProfile, curatedStacks } from "./curated.js";

const publicOrigin = "https://stacks.spot";
const supabasePreview = "https://iuovmgjcfwgwozfnsdgf.supabase.co/functions/v1/web-preview";
const policyPages = new Set([
  "terms", "privacy", "security", "support", "affiliate", "privacy-choices",
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const usernamePattern = /^[a-z0-9_]{3,30}$/;
const demoProductSlugs = new Set([
  "brown-script", "green-stripe", "rust-vintage", "blue-logo", "burgundy-bird",
  "coral-wave", "black-columbia", "slate-bird", "lilac-mountain",
  "bird-head-yellow", "blue-flame", "orange-peaks",
]);

function htmlResponse(html, status = 200, extraHeaders = {}) {
  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "Referrer-Policy": "strict-origin-when-cross-origin",
      ...extraHeaders,
    },
  });
}

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character]));
}

function stackSlug(title) {
  return String(title ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "stack";
}

// Mirrors DiscoverStackPreview in the iPhone app: six cutouts positioned in a
// compact, rounded preview field rather than a generic image grid.
function stackPreview(items) {
  const images = items
    .filter(item => typeof item === "string" || item?.imageURL)
    .map(item => typeof item === "string" ? item : item.imageURL)
    .filter(image => typeof image === "string" && image.startsWith("https://"))
    .slice(0, 6);
  if (!images.length) return '<div class="public-stack-art"><span class="public-stack-empty">A new Stack</span></div>';
  const cutouts = images.map((image, index) => `<img class="public-stack-cutout public-stack-cutout-${index + 1}" src="${escapeHTML(image)}" alt="" loading="lazy">`).join("");
  return `<div class="public-stack-art" aria-hidden="true">${cutouts}</div>`;
}

function curatedCard(stack) {
  const count = stack.items.length;
  return `<a class="public-stack-card" href="/s/${stack.id}">${stackPreview(stack.items)}<h2>${escapeHTML(stack.title)}</h2><p class="public-stack-count">${count} ${count === 1 ? "find" : "finds"}</p><div class="public-stack-author"><span class="public-stack-avatar"><img src="${escapeHTML(curatedProfile.avatarURL)}" alt=""></span><span>${escapeHTML(curatedProfile.displayName)} · Curated by Stacks</span><span class="public-stack-arrow" aria-hidden="true">↗</span></div></a>`;
}

function updatedLabel(value) {
  const updatedAt = new Date(value ?? "");
  if (Number.isNaN(updatedAt.getTime())) return "Recently";
  const elapsed = Math.max(0, Date.now() - updatedAt.getTime());
  const days = Math.floor(elapsed / 86_400_000);
  if (days === 0) return "Today";
  if (days < 7) return `${days}d ago`;
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", timeZone: "UTC" }).format(updatedAt);
}

function discoverCard({ id, title, items, count, author, updatedAt }) {
  const displayName = author?.displayName || "Stacks";
  const username = author?.username ? `@${author.username}` : displayName;
  const avatar = typeof author?.avatarURL === "string" && author.avatarURL.startsWith("https://")
    ? `<img src="${escapeHTML(author.avatarURL)}" alt="" loading="lazy">`
    : `<span>${escapeHTML(String(displayName).slice(0, 1).toUpperCase())}</span>`;
  const itemCount = Number.isInteger(count) && count >= 0 ? count : items.length;
  return `<article class="discover-stack-card"><a class="discover-stack-link" href="/s/${id}" aria-label="Open ${escapeHTML(title)} by ${escapeHTML(displayName)}"><header class="discover-card-heading"><h2>${escapeHTML(title)}</h2><p>${itemCount} ${itemCount === 1 ? "find" : "finds"}</p></header>${stackPreview(items)}<footer class="discover-card-footer"><span class="discover-author-avatar public-stack-avatar">${avatar}</span><span class="discover-author-copy"><strong>${escapeHTML(username)}</strong><small>${escapeHTML(updatedLabel(updatedAt))}</small></span><span class="discover-stack-action">View Stack <span aria-hidden="true">↗</span></span></footer></a></article>`;
}

function curatedDiscoverCard(stack) {
  return discoverCard({
    id: stack.id,
    title: stack.title,
    items: stack.items,
    count: stack.items.length,
    updatedAt: stack.updatedAt,
    author: curatedProfile,
  });
}

function curatedProfilePage() {
  const cards = curatedStacks.map(curatedCard).join("");
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(curatedProfile.displayName)} · Stacks</title><meta name="description" content="Explore Aliva Yakatori's curated Stacks."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="public-page"><main class="public-main"><nav class="demo-topline"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><div class="site-nav-links"><a href="/">Stacks</a><a href="/waitlist">Waitlist</a><a href="/stacks">Explore</a></div></nav><header class="public-heading"><img class="profile-page-avatar" src="${escapeHTML(curatedProfile.avatarURL)}" alt=""><h1>${escapeHTML(curatedProfile.displayName)}</h1><p>@${escapeHTML(curatedProfile.username)} · Curated by Stacks</p><p>${escapeHTML(curatedProfile.bio)}</p></header><section class="public-grid" aria-label="Curated Stacks">${cards}</section><footer class="demo-footer"><a href="/waitlist">Waitlist</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/support">Support</a></footer></main></body></html>`);
}

function curatedStackPage(stack) {
  // Mirror EditorialCollageLayout in the iPhone app: four items per compact
  // page, with the final partial page spaced out and a lone item centered.
  const canvasHeight = stack.items.length <= 4 ? 520 : Math.floor(stack.items.length / 4) * 420 + (stack.items.length % 4 ? 520 : 0);
  const items = stack.items.map((item, index) => {
    const page = Math.floor(index / 4);
    const inPage = index % 4;
    const count = Math.min(4, stack.items.length - page * 4);
    const pageHeight = count === 4 && stack.items.length > 4 ? 420 : 520;
    const pageStart = page * 420;
    const rows = Math.max(1, Math.ceil(count / 2));
    const centered = count === 1 || (count === 3 && inPage === 2);
    const x = centered ? 50 : inPage % 2 === 0 ? 25 : 75;
    const y = pageStart + pageHeight * (Math.floor(inPage / 2) + 0.5) / rows;
    return `<a class="demo-item curated-item" style="left:${x}%;top:${y}px" href="/s/${stack.id}/p/${item.id}" aria-label="${escapeHTML(item.title)} details">${item.imageURL ? `<img src="${escapeHTML(item.imageURL)}" alt="${escapeHTML(item.title)}" loading="lazy">` : `<span class="curated-item-fallback">${escapeHTML(item.brand)}<small>${escapeHTML(item.title)}</small></span>`}</a>`;
  }).join("");
  const update = new Date(stack.updatedAt);
  const date = new Intl.DateTimeFormat("en-US", { weekday: "long", month: "long", day: "numeric", timeZone: "UTC" }).format(update);
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(stack.title)} · Stacks</title><meta name="description" content="Explore ${escapeHTML(stack.title)} by Aliva Yakatori."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="demo-page curated-stack-page"><header class="site-header"><nav class="nav-pill" aria-label="Main navigation"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><a href="/waitlist">Waitlist</a><a href="/stacks">Explore</a></nav></header><main class="demo-main"><header class="demo-stack-header"><div class="demo-stack-actions"><a class="demo-back-action" href="/aliva" aria-label="Back to Aliva's profile">‹</a><span class="demo-share-action" aria-hidden="true">↥</span></div><h1>${escapeHTML(stack.title)}</h1><div class="demo-byline"><span class="preview-avatar"><img src="${escapeHTML(curatedProfile.avatarURL)}" alt=""></span><a href="/aliva">${escapeHTML(curatedProfile.displayName)}</a><span class="demo-date"><span>Last update</span><time datetime="${escapeHTML(stack.updatedAt.slice(0, 10))}">${escapeHTML(date)}</time></span></div></header><section class="demo-canvas" style="height:${canvasHeight}px" aria-label="Products in ${escapeHTML(stack.title)}">${items}</section><aside class="demo-bottom-cta"><h2>Make a Stack of your own.</h2><p>Save the things you love in one place.</p><a class="button" href="/waitlist">Claim your username ↗</a></aside></main></body></html>`);
}

function curatedProductPage(stack, item) {
  const destination = new URL(item.sourceURL);
  if (destination.protocol !== "https:") return informationPage("Product unavailable", "That product link isn't available.", 404);
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(item.title)} · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="product-page"><main class="product-main"><nav class="product-navigation" aria-label="Product navigation"><a class="product-nav-circle" href="/s/${stack.id}" aria-label="Back to ${escapeHTML(stack.title)}">‹</a></nav><div class="product-stage">${item.imageURL ? `<img src="${escapeHTML(item.imageURL)}" alt="${escapeHTML(item.title)}">` : `<span class="curated-item-fallback">${escapeHTML(item.brand)}<small>${escapeHTML(item.title)}</small></span>`}</div><h1>${escapeHTML(item.title)}</h1><section class="product-info" aria-label="Product information"><div class="product-info-row"><span>Brand</span><strong>${escapeHTML(item.brand)}</strong></div><div class="product-info-row"><span>Stack</span><strong>${escapeHTML(stack.title)}</strong></div></section></main><aside class="product-actions"><a class="product-buy" href="${escapeHTML(destination.href)}" target="_blank" rel="noopener noreferrer"><span>View at ${escapeHTML(item.retailer)}</span><span aria-hidden="true">↗</span></a><a class="product-download" href="/waitlist">Claim your username</a></aside></body></html>`);
}

function informationPage(title, message, status = 200) {
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(title)} · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="message-page"><main class="message-card"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><h1>${escapeHTML(title)}</h1><p>${escapeHTML(message)}</p><a class="button" href="/">Back to Stacks</a></main></body></html>`, status, { "X-Robots-Tag": "noindex" });
}

function localizeHTML(html) {
  return html
    .replaceAll("trystacks@gmail.com", "support@stacks.spot")
    .replace(/href="\?page=(terms|privacy|security|support|affiliate|privacy-choices)"/g, 'href="/$1"')
    .replace(/href="https:\/\/iuovmgjcfwgwozfnsdgf\.supabase\.co\/functions\/v1\/web-preview\?page=(terms|privacy|security|support|affiliate|privacy-choices)"/g, 'href="/$1"')
    .replace("</head>", '<link rel="stylesheet" href="/site.css"></head>')
    .replace("<nav><strong>Stacks</strong>", '<nav><a class="legal-wordmark" href="/">Stacks</a>')
    .replace("<span>For iPhone · coming soon</span>", '<a class="get-app" href="/waitlist">Claim your username</a>')
    .replace(/<section class="pitch">[\s\S]*?<\/section>/, section => section.includes('class="get-app"')
      ? section
      : section.replace('</section>', '<a class="get-app" href="/waitlist">Claim your username</a></section>'));
}

async function upstreamPage(url, upstreamFetch, { linkOnly = false } = {}) {
  let response;
  try {
    response = await upstreamFetch(url, {
      headers: { Accept: "text/html", "X-Stacks-Web-Proxy": "1" },
      redirect: "manual",
    });
  } catch (error) {
    console.error("Stacks upstream preview request failed", error);
    return informationPage("Temporarily unavailable", "Please try opening this page again shortly.", 503);
  }
  if (response.status === 404) {
    return informationPage("Stack unavailable", "This Stack is private, expired, or no longer shared.", 404);
  }
  if (response.status >= 300 && response.status < 400) {
    return informationPage("Temporarily unavailable", "Please try opening this page again shortly.", 503);
  }
  if (!response.ok) {
    return informationPage("Temporarily unavailable", "Please try opening this page again shortly.", 503);
  }
  const html = localizeHTML(await response.text());
  return htmlResponse(html, 200, {
    ...(linkOnly ? {
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow, noarchive",
    } : {}),
  });
}

function invitePage(token) {
  const deepLink = `stacks://invite?token=${encodeURIComponent(token)}`;
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>You're invited to a Collab · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="message-page"><main class="message-card"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><h1>You're invited to a Collab.</h1><p>Open this invitation in Stacks to see the shared Stack and join in.</p><a class="button" href="${deepLink}">Open Stacks</a><a class="button secondary" href="/waitlist">Claim your username</a></main></body></html>`, 200, {
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow, noarchive",
  });
}

function associationFile() {
  return new Response(JSON.stringify({
    applinks: {
      apps: [],
      details: [{
        appID: "ZVV8KBVP26.com.owenhackero.stacks",
        paths: ["/s/*", "/invite/*"],
      }],
    },
  }), {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function waitlistJSON(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

const waitlistNamePattern = /^[a-z0-9_]{3,30}$/;
const waitlistEmailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function waitlistRPC(name, params, env, upstreamFetch) {
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) throw new Error("Waitlist backend is not configured");
  const response = await upstreamFetch(`${env.SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify(params),
    signal: AbortSignal.timeout(7_000),
  });
  if (!response.ok) throw new Error(`Waitlist backend returned ${response.status}`);
  return response.json();
}

async function boundedJSON(request) {
  if (Number(request.headers.get("content-length") ?? 0) > 2048) return null;
  if (!request.body) return null;
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 2048) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

async function waitlistEndpoint(request, url, env, upstreamFetch) {
  if (url.pathname === "/api/waitlist/availability") {
    if (request.method !== "GET") return waitlistJSON({ error: "Method not allowed" }, 405);
    const username = (url.searchParams.get("username") ?? "").trim().toLowerCase();
    if (!waitlistNamePattern.test(username)) return waitlistJSON({ available: false });
    try {
      const available = await waitlistRPC("waitlist_username_available", { p_username: username }, env, upstreamFetch);
      return waitlistJSON({ available: available === true });
    } catch (error) {
      console.error(JSON.stringify({ message: "Waitlist availability failed", error: String(error) }));
      return waitlistJSON({ error: "Could not check this username right now." }, 503);
    }
  }

  if (request.method !== "POST") return waitlistJSON({ error: "Method not allowed" }, 405);
  if (request.headers.get("origin") !== publicOrigin || !request.headers.get("content-type")?.startsWith("application/json")) {
    return waitlistJSON({ error: "Invalid request" }, 403);
  }
  const payload = await boundedJSON(request);
  if (!payload || typeof payload !== "object") return waitlistJSON({ error: "Invalid request" }, 400);
  if (payload.company) return waitlistJSON({ status: "joined" }); // Invisible honeypot for simple bots.
  const username = typeof payload.username === "string" ? payload.username.trim().toLowerCase() : "";
  const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
  if (!waitlistNamePattern.test(username)) return waitlistJSON({ status: "invalid_username" }, 400);
  if (email.length > 254 || !waitlistEmailPattern.test(email)) return waitlistJSON({ status: "invalid_email" }, 400);
  try {
    const status = await waitlistRPC("reserve_waitlist_username", { p_username: username, p_email: email }, env, upstreamFetch);
    const known = new Set(["joined", "username_taken", "invalid_username", "invalid_email", "already_taken"]);
    if (!known.has(status)) throw new Error("Unexpected waitlist backend response");
    return waitlistJSON({ status }, status === "joined" ? 201 : 409);
  } catch (error) {
    console.error(JSON.stringify({ message: "Waitlist reservation failed", error: String(error) }));
    return waitlistJSON({ error: "Could not save your spot right now." }, 503);
  }
}

function explorePage(cards, pagination = "") {
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Discover public Stacks · Stacks</title><meta name="description" content="Discover public and curated Stacks."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="discover-page"><header class="discover-site-header"><nav class="discover-nav" aria-label="Main navigation"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><div class="discover-nav-links"><a href="/stacks" aria-current="page">Discover</a><a class="discover-waitlist" href="/waitlist">Claim your username</a></div></nav></header><main class="discover-main"><header class="discover-heading"><p class="eyebrow">From the Stacks community</p><h1>Discover.</h1><p>Wishlists, ideas, and finds worth keeping—stacked by people with a good eye.</p></header><section class="discover-feed" aria-label="Public Stacks">${cards || '<p class="public-empty">No public Stacks to show yet.</p>'}</section>${pagination}<footer class="demo-footer"><a href="/waitlist">Waitlist</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/support">Support</a></footer></main></body></html>`);
}

async function publicStacksPage(url, upstreamFetch) {
  const rawPage = url.searchParams.get("page") ?? "1";
  if (!/^[1-9][0-9]{0,3}$/.test(rawPage)) return informationPage("Page not found", "That page isn't available.", 404);
  const page = Number(rawPage);
  const upstream = new URL(supabasePreview);
  upstream.searchParams.set("feed", "public");
  upstream.searchParams.set("page", String(page));
  let response;
  try {
    response = await upstreamFetch(upstream, { headers: { Accept: "application/json" }, redirect: "manual" });
    if (!response.ok) throw new Error(`Public Stack feed returned ${response.status}`);
    const payload = await response.json();
    if (!Array.isArray(payload.stacks)) throw new Error("Invalid public Stack feed");
    const backendCards = payload.stacks.map((stack) => {
      if (!uuidPattern.test(stack.id)) return "";
      const images = Array.isArray(stack.cutouts) && stack.cutouts.length ? stack.cutouts : (Array.isArray(stack.images) ? stack.images : []);
      const count = Number.isInteger(stack.itemCount) && stack.itemCount >= 0 ? stack.itemCount : images.length;
      return discoverCard({
        id: stack.id,
        title: stack.title,
        items: images,
        count,
        author: stack.author,
        updatedAt: stack.updatedAt,
      });
    }).join("");
    const cards = `${page === 1 ? curatedStacks.map(curatedDiscoverCard).join("") : ""}${backendCards}`;
    const pagination = `<nav class="public-pagination" aria-label="Pages">${page > 1 ? `<a href="/stacks?page=${page - 1}">Previous</a>` : ""}${payload.hasMore ? `<a href="/stacks?page=${page + 1}">Next</a>` : ""}</nav>`;
    return explorePage(cards, pagination);
  } catch (error) {
    console.error("Stacks public feed failed", error);
    if (page === 1) return explorePage(curatedStacks.map(curatedDiscoverCard).join(""));
    return informationPage("Temporarily unavailable", "Please try exploring Stacks again shortly.", 503);
  }
}

async function publicProfilePage(username, upstreamFetch) {
  const upstream = new URL(supabasePreview);
  upstream.searchParams.set("profile", username);
  try {
    const response = await upstreamFetch(upstream, { headers: { Accept: "application/json" }, redirect: "manual" });
    if (response.status === 404) return informationPage("Profile unavailable", "This profile isn't public.", 404);
    if (!response.ok) throw new Error(`Public profile returned ${response.status}`);
    const payload = await response.json();
    if (!payload.profile || !Array.isArray(payload.stacks)) throw new Error("Invalid profile response");
    const profile = payload.profile;
    const avatar = typeof profile.avatarURL === "string" && profile.avatarURL.startsWith("https://")
      ? `<img src="${escapeHTML(profile.avatarURL)}" alt="" class="profile-page-avatar">`
      : `<span class="profile-page-avatar profile-page-initial">${escapeHTML(String(profile.displayName ?? "S").slice(0, 1))}</span>`;
    const cards = payload.stacks.filter(stack => uuidPattern.test(stack.id)).map(stack => {
      const images = Array.isArray(stack.cutouts) && stack.cutouts.length ? stack.cutouts : (Array.isArray(stack.images) ? stack.images : []);
      const count = Number.isInteger(stack.itemCount) && stack.itemCount >= 0 ? stack.itemCount : images.length;
      return `<a class="public-stack-card" href="/s/${stack.id}">${stackPreview(images)}<h2>${escapeHTML(stack.title)}</h2><p class="public-stack-count">${count} ${count === 1 ? "find" : "finds"}</p><span class="public-stack-arrow" aria-hidden="true">↗</span></a>`;
    }).join("");
    return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(profile.displayName)} · Stacks</title><meta name="description" content="Public Stacks from ${escapeHTML(profile.displayName)}."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="public-page"><main class="public-main"><nav class="demo-topline"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><div class="site-nav-links"><a href="/">Stacks</a><a href="/waitlist">Waitlist</a><a href="/stacks">Explore</a></div></nav><header class="public-heading">${avatar}<h1>${escapeHTML(profile.displayName)}</h1><p>@${escapeHTML(profile.username)}</p>${profile.bio ? `<p>${escapeHTML(profile.bio)}</p>` : ""}</header><section class="public-grid" aria-label="Public Stacks">${cards || '<p class="public-empty">No public Stacks yet.</p>'}</section><footer class="demo-footer"><a href="/waitlist">Claim your username</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/support">Support</a></footer></main></body></html>`);
  } catch (error) {
    console.error("Stacks public profile failed", error);
    return informationPage("Temporarily unavailable", "Please try this profile again shortly.", 503);
  }
}

export default {
  async scheduled(controller, env, ctx) {
    ctx.waitUntil((async () => {
      try {
        const response = await fetch(`${env.SUPABASE_URL}/functions/v1/check-price-alerts`, {
          method: "POST",
          headers: { Authorization: `Bearer ${env.PRICE_CHECK_SECRET}` },
        });
        const result = await response.json().catch(() => ({}));
        if (!response.ok) throw new Error(result.error || `Price checker returned ${response.status}`);
        console.log(JSON.stringify({ message: "price alert check completed", cron: controller.cron, ...result }));
      } catch (error) {
        console.error(JSON.stringify({
          message: "price alert check failed",
          cron: controller.cron,
          error: error instanceof Error ? error.message : String(error),
        }));
        throw error;
      }
    })());
  },
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname.toLowerCase() === "www.stacks.spot") {
      return Response.redirect(`${publicOrigin}${url.pathname}${url.search}`, 308);
    }
    if (url.pathname === "/api/waitlist" || url.pathname === "/api/waitlist/availability") {
      return waitlistEndpoint(request, url, env, fetch);
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    if (url.pathname === "/download" || url.pathname === "/download/") return Response.redirect(`${publicOrigin}/waitlist`, 308);
    if (url.pathname === "/api/curated") {
      return new Response(JSON.stringify({ profile: curatedProfile, stacks: curatedStacks }), {
        headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=300", "X-Content-Type-Options": "nosniff" },
      });
    }
    if (url.pathname === "/.well-known/apple-app-site-association" || url.pathname === "/apple-app-site-association") {
      return associationFile();
    }
    if (url.pathname === "/stacks" || url.pathname === "/stacks/") {
      return publicStacksPage(url, fetch);
    }

    const page = url.pathname.slice(1).replace(/\/$/, "");
    if (policyPages.has(page)) {
      const upstream = new URL(supabasePreview);
      upstream.searchParams.set("page", page);
      return upstreamPage(upstream, fetch);
    }

    const curatedProductMatch = /^\/s\/([^/]+)\/p\/([^/]+)\/?$/.exec(url.pathname);
    if (curatedProductMatch) {
      const stack = curatedStacks.find(candidate => candidate.id.toLowerCase() === curatedProductMatch[1].toLowerCase());
      const item = stack?.items.find(candidate => candidate.id.toLowerCase() === curatedProductMatch[2].toLowerCase());
      return stack && item ? curatedProductPage(stack, item) : informationPage("Product unavailable", "That product isn't in this Stack.", 404);
    }

    const stackMatch = /^\/s\/([^/]+)\/?$/.exec(url.pathname);
    if (stackMatch) {
      const stackID = stackMatch[1];
      const curatedStack = curatedStacks.find(candidate => candidate.id.toLowerCase() === stackID.toLowerCase());
      if (curatedStack) return curatedStackPage(curatedStack);
      const token = url.searchParams.get("token");
      if (!uuidPattern.test(stackID) || (token && !uuidPattern.test(token))) {
        return informationPage("Stack unavailable", "This Stack link is invalid.", 404);
      }
      const upstream = new URL(supabasePreview);
      upstream.searchParams.set("stackID", stackID);
      if (token) upstream.searchParams.set("token", token);
      return upstreamPage(upstream, fetch, { linkOnly: Boolean(token) });
    }

    const inviteMatch = /^\/invite\/([^/]+)\/?$/.exec(url.pathname);
    if (inviteMatch) {
      return uuidPattern.test(inviteMatch[1])
        ? invitePage(inviteMatch[1])
        : informationPage("Invitation unavailable", "This invitation link is invalid.", 404);
    }

    if (url.pathname === "/demo/beanies" || url.pathname === "/demo/beanies/") {
      return env.ASSETS.fetch(new Request(new URL("/demo-beanies", url), request));
    }
    const demoProductMatch = /^\/demo\/beanies\/([a-z-]+)\/?$/.exec(url.pathname);
    if (demoProductMatch) {
      return demoProductSlugs.has(demoProductMatch[1])
        ? env.ASSETS.fetch(new Request(new URL("/demo-product", url), request))
        : informationPage("Product unavailable", "That demo product isn't available.", 404);
    }
    if (url.pathname === "/waitlist" || url.pathname === "/waitlist/") {
      return env.ASSETS.fetch(new Request(new URL("/download", url), request));
    }

    // Reserved application routes must be resolved before the friendly
    // /username/stack-slug route, otherwise paths such as /invite/<token> and
    // /demo/beanies are mistaken for public profile Stacks.
    const friendlyStackMatch = /^\/([a-z0-9_]{3,30})\/([a-z0-9-]+)\/?$/i.exec(url.pathname);
    if (friendlyStackMatch) {
      const username = friendlyStackMatch[1].toLowerCase();
      const slug = friendlyStackMatch[2].toLowerCase();
      const curatedStack = username === curatedProfile.username
        ? curatedStacks.find(candidate => stackSlug(candidate.title) === slug)
        : null;
      if (curatedStack) return curatedStackPage(curatedStack);

      const upstream = new URL(supabasePreview);
      upstream.searchParams.set("stackUsername", username);
      upstream.searchParams.set("stackSlug", slug);
      return upstreamPage(upstream, fetch);
    }

    if (url.pathname === "/" || url.pathname === "/index.html" || url.pathname === "/site.css" || url.pathname === "/site.js" || url.pathname === "/waitlist.js" || url.pathname.startsWith("/assets/")) {
      return env.ASSETS.fetch(request);
    }
    const username = url.pathname.slice(1).replace(/\/$/, "").toLowerCase();
    if (url.pathname.split("/").filter(Boolean).length === 1 && usernamePattern.test(username)) {
      if (username === curatedProfile.username) return curatedProfilePage();
      return publicProfilePage(username, fetch);
    }
    return informationPage("Page not found", "That page isn't available.", 404);
  },
};
