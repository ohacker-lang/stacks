import { curatedProfile, curatedStacks } from "./curated.js";

const publicOrigin = "https://stacks.spot";
const supabasePreview = "https://whyufyttlvpiwlunosjm.supabase.co/functions/v1/web-preview";
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
  return profilePage({
    profile: curatedProfile,
    curated: true,
    shareImage: curatedStacks[0]?.items[0]?.imageURL,
    boards: curatedStacks.map(stack => ({
      href: `/s/${stack.id}`,
      title: stack.title,
      count: stack.items.length,
      updatedAt: stack.updatedAt,
      wishlistMode: false,
      images: stack.items.map(item => item.imageURL),
    })),
  });
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
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(stack.title)} · Stacks</title><meta name="description" content="Explore ${escapeHTML(stack.title)} by Aliva Yakatori."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script></head><body class="demo-page curated-stack-page"><header class="site-header"><nav class="nav-pill" aria-label="Main navigation"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><a href="/waitlist">Waitlist</a><a href="/stacks">Explore</a></nav></header><main class="demo-main"><header class="demo-stack-header"><div class="demo-stack-actions"><a class="demo-back-action" href="/aliva" aria-label="Back to Aliva's profile">‹</a><span class="demo-share-action" aria-hidden="true">↥</span></div><h1>${escapeHTML(stack.title)}</h1><div class="demo-byline"><span class="preview-avatar"><img src="${escapeHTML(curatedProfile.avatarURL)}" alt=""></span><a href="/aliva">${escapeHTML(curatedProfile.displayName)}</a><span class="demo-date"><span>Last update</span><time datetime="${escapeHTML(stack.updatedAt.slice(0, 10))}">${escapeHTML(date)}</time></span></div></header><section class="demo-canvas" style="height:${canvasHeight}px" aria-label="Products in ${escapeHTML(stack.title)}">${items}</section><aside class="demo-bottom-cta"><h2>Make a Stack of your own.</h2><p>Save the things you love in one place.</p><a class="button" href="/waitlist">Claim your username ↗</a></aside></main></body></html>`);
}

function curatedProductPage(stack, item) {
  const destination = new URL(item.sourceURL);
  if (destination.protocol !== "https:") return informationPage("Product unavailable", "That product link isn't available.", 404);
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(item.title)} · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script></head><body class="product-page"><main class="product-main"><nav class="product-navigation" aria-label="Product navigation"><a class="product-nav-circle" href="/s/${stack.id}" aria-label="Back to ${escapeHTML(stack.title)}">‹</a></nav><div class="product-stage">${item.imageURL ? `<img src="${escapeHTML(item.imageURL)}" alt="${escapeHTML(item.title)}">` : `<span class="curated-item-fallback">${escapeHTML(item.brand)}<small>${escapeHTML(item.title)}</small></span>`}</div><h1>${escapeHTML(item.title)}</h1><section class="product-info" aria-label="Product information"><div class="product-info-row"><span>Brand</span><strong>${escapeHTML(item.brand)}</strong></div><div class="product-info-row"><span>Stack</span><strong>${escapeHTML(stack.title)}</strong></div></section></main><aside class="product-actions"><a class="product-buy" href="${escapeHTML(destination.href)}" target="_blank" rel="noopener noreferrer"><span>View at ${escapeHTML(item.retailer)}</span><span aria-hidden="true">↗</span></a><a class="product-download" href="/waitlist">Claim your username</a></aside></body></html>`);
}

function informationPage(title, message, status = 200) {
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(title)} · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script></head><body class="message-page"><main class="message-card"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><h1>${escapeHTML(title)}</h1><p>${escapeHTML(message)}</p><a class="button" href="/">Back to Stacks</a></main></body></html>`, status, { "X-Robots-Tag": "noindex" });
}

function localizeHTML(html) {
  return html
    .replaceAll("trystacks@gmail.com", "support@stacks.spot")
    .replace(/href="\?page=(terms|privacy|security|support|affiliate|privacy-choices)"/g, 'href="/$1"')
    .replace(/href="https:\/\/whyufyttlvpiwlunosjm\.supabase\.co\/functions\/v1\/web-preview\?page=(terms|privacy|security|support|affiliate|privacy-choices)"/g, 'href="/$1"')
    .replace("</head>", '<link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script></head>')
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
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>You're invited to a Collab · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script></head><body class="message-page"><main class="message-card"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><h1>You're invited to a Collab.</h1><p>Open this invitation in Stacks to see the shared Stack and join in.</p><a class="button" href="${deepLink}">Open Stacks</a><a class="button secondary" href="/waitlist">Claim your username</a></main></body></html>`, 200, {
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow, noarchive",
  });
}

const appLinkExclusions = [
  "/", "/waitlist", "/waitlist/*", "/download", "/download/*", "/stacks", "/stacks/*",
  "/demo/*", "/api/*", "/assets/*", "/aliva", "/aliva/*", "/.well-known/*",
  ...[...policyPages].map(page => `/${page}`),
];

// PostHog for stacks.spot. Served from the Worker so the project key lives in
// wrangler.toml; without POSTHOG_KEY the script is a no-op. Visitors are
// anonymous and nothing is stored on their device (memory persistence), so no
// cookie banner is needed. Event names are documented in docs/ANALYTICS.md.
function analyticsScript(env) {
  const key = typeof env?.POSTHOG_KEY === "string" ? env.POSTHOG_KEY.trim() : "";
  const host = typeof env?.POSTHOG_HOST === "string" && env.POSTHOG_HOST.startsWith("https://") ? env.POSTHOG_HOST : "https://us.i.posthog.com";
  const body = !key.startsWith("phc_") ? "window.stacksTrack=function(){};" : `!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.crossOrigin="anonymous",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="init capture register reset opt_out_capturing opt_in_capturing set_config".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
posthog.init(${JSON.stringify(key)},{api_host:${JSON.stringify(host)},persistence:"memory",person_profiles:"identified_only",capture_pageview:false,capture_pageleave:false,autocapture:false,disable_session_recording:true});
(function(){var path=location.pathname.replace(/\\/+$/,"")||"/",parts=path.split("/").filter(Boolean),reserved=["waitlist","download","stacks","demo","terms","privacy","security","support","affiliate","privacy-choices"],props={};
if(path==="/")props.page_type="home";
else if(parts[0]==="waitlist"||parts[0]==="download")props.page_type="waitlist";
else if(parts[0]==="stacks")props.page_type="explore";
else if(parts[0]==="demo")props.page_type="demo";
else if(reserved.indexOf(parts[0])>-1)props.page_type="legal";
else if(parts[0]==="s"&&parts[2]==="p")props.page_type="pin";
else if(parts[0]==="s")props.page_type=document.body&&document.body.classList.contains("sp-page")?"board":"wishlist";
else if(parts[0]==="invite")props.page_type="invite";
else if(parts.length===1){props.page_type="profile";props.profile_username=parts[0].toLowerCase()}
else if(parts.length===2){props.page_type="board";props.profile_username=parts[0].toLowerCase();props.stack_slug=parts[1].toLowerCase()}
else props.page_type="other";
posthog.capture("$pageview",props);
window.stacksTrack=function(event,extra){posthog.capture(event,Object.assign({page_type:props.page_type},extra||{}))};
document.addEventListener("click",function(e){var el=e.target.closest&&e.target.closest(".product-buy,[data-share]");if(!el)return;
if(el.classList.contains("product-buy")){var host="";try{host=new URL(el.href).hostname.replace(/^www\\./,"")}catch(_){}window.stacksTrack("buy_clicked",{retailer_host:host})}
else window.stacksTrack("share_clicked")},true)})();`;
  return new Response(body, {
    headers: {
      "Content-Type": "text/javascript; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function associationFile() {
  return new Response(JSON.stringify({
    applinks: {
      apps: [],
      details: [{
        appID: "24H7V96T4Q.spot.stacks.app",
        // Site pages share the /username namespace, so exclude them before the
        // profile wildcards. Mirrors PublicProfileUniversalLink in the app.
        paths: [
          "/s/*", "/invite/*",
          ...appLinkExclusions.map(path => `NOT ${path}`),
          "/*", "/*/*",
        ],
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
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Discover public Stacks · Stacks</title><meta name="description" content="Discover public and curated Stacks."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script></head><body class="discover-page"><header class="discover-site-header"><nav class="discover-nav" aria-label="Main navigation"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><div class="discover-nav-links"><a href="/stacks" aria-current="page">Discover</a><a class="discover-waitlist" href="/waitlist">Claim your username</a></div></nav></header><main class="discover-main"><header class="discover-heading"><p class="eyebrow">From the Stacks community</p><h1>Discover.</h1><p>Wishlists, ideas, and finds worth keeping—stacked by people with a good eye.</p></header><section class="discover-feed" aria-label="Public Stacks">${cards || '<p class="public-empty">No public Stacks to show yet.</p>'}</section>${pagination}<footer class="demo-footer"><a href="/waitlist">Waitlist</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/support">Support</a></footer></main></body></html>`);
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
    if (response.status === 404) return informationPage("Profile unavailable", "There's no Stacks account with that username.", 404);
    if (!response.ok) throw new Error(`Public profile returned ${response.status}`);
    const payload = await response.json();
    if (!payload.profile || !Array.isArray(payload.stacks)) throw new Error("Invalid profile response");
    const profile = payload.profile;
    const stacks = payload.stacks.filter(stack => uuidPattern.test(stack.id));
    // Two public Stacks with the same title share a slug; link the extras by ID.
    const slugCounts = new Map();
    stacks.forEach(stack => slugCounts.set(stack.slug, (slugCounts.get(stack.slug) ?? 0) + 1));
    const boards = stacks.map(stack => {
      const images = Array.isArray(stack.cutouts) && stack.cutouts.length ? stack.cutouts : (Array.isArray(stack.images) ? stack.images : []);
      const slug = typeof stack.slug === "string" && /^[a-z0-9-]{1,80}$/.test(stack.slug) ? stack.slug : null;
      return {
        href: slug && slugCounts.get(slug) === 1 ? `/${username}/${slug}` : `/s/${stack.id}`,
        title: stack.title,
        count: Number.isInteger(stack.itemCount) && stack.itemCount >= 0 ? stack.itemCount : images.length,
        updatedAt: stack.updatedAt,
        wishlistMode: stack.wishlistMode === true,
        images,
      };
    });
    return profilePage({ profile, boards, shareImage: profile.shareImageURL });
  } catch (error) {
    console.error("Stacks public profile failed", error);
    return informationPage("Temporarily unavailable", "Please try this profile again shortly.", 503);
  }
}

// ---- Public profiles and boards (Pinterest-style) -------------------------
// Every account has a page at stacks.spot/username listing its public Stacks
// as boards; each board opens as a masonry grid of product pins.

function httpsURL(value) {
  return typeof value === "string" && value.startsWith("https://") ? value : null;
}

function pageHead({ title, description, canonical, image, robots }) {
  const tags = [
    `<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#ffffff">`,
    `<title>${escapeHTML(title)}</title><meta name="description" content="${escapeHTML(description)}">`,
    `<meta property="og:site_name" content="Stacks"><meta property="og:type" content="website">`,
    `<meta property="og:title" content="${escapeHTML(title)}"><meta property="og:description" content="${escapeHTML(description)}">`,
    canonical ? `<link rel="canonical" href="${escapeHTML(canonical)}"><meta property="og:url" content="${escapeHTML(canonical)}">` : "",
    image ? `<meta property="og:image" content="${escapeHTML(image)}"><meta name="twitter:card" content="summary_large_image">` : `<meta name="twitter:card" content="summary">`,
    robots ? `<meta name="robots" content="${escapeHTML(robots)}">` : "",
    `<link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"><script src="/analytics.js" defer></script>`,
  ];
  return `<head>${tags.join("")}</head>`;
}

const boardNav = `<nav class="sp-nav" aria-label="Main navigation"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><div class="sp-nav-links"><a href="/stacks">Explore</a><a class="sp-nav-cta" href="/waitlist">Get Stacks</a></div></nav>`;
const boardFooter = `<footer class="demo-footer"><a href="/waitlist">Claim your username</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/support">Support</a></footer>`;
// Uses the native share sheet on phones and copies the link elsewhere.
const shareScript = `<script>document.querySelectorAll("[data-share]").forEach(b=>b.addEventListener("click",async()=>{const url=b.dataset.share;try{if(navigator.share){await navigator.share({url});return}await navigator.clipboard.writeText(url);const l=b.textContent;b.textContent="Link copied";setTimeout(()=>b.textContent=l,1600)}catch{}}))</script>`;

function avatarMarkup(profile, className) {
  const image = httpsURL(profile?.avatarURL);
  const initial = String(profile?.displayName || profile?.username || "S").trim().slice(0, 1).toUpperCase();
  return image
    ? `<img class="${className}" src="${escapeHTML(image)}" alt="">`
    : `<span class="${className} sp-avatar-initial" aria-hidden="true">${escapeHTML(initial)}</span>`;
}

function findsLabel(count) {
  return `${count} ${count === 1 ? "find" : "finds"}`;
}

// A Pinterest board cover: one large tile and two small ones.
function boardCover(images) {
  const covers = images.map(httpsURL).filter(Boolean).slice(0, 3);
  const cells = [0, 1, 2].map(index => covers[index]
    ? `<span class="sp-cover-cell"><img src="${escapeHTML(covers[index])}" alt="" loading="lazy"></span>`
    : `<span class="sp-cover-cell"></span>`).join("");
  return `<span class="sp-board-cover" aria-hidden="true">${cells}</span>`;
}

function boardCard({ href, title, count, updatedAt, wishlistMode, images }) {
  const badge = wishlistMode ? `<span class="sp-badge">Wishlist</span>` : "";
  return `<a class="sp-board" href="${escapeHTML(href)}">${boardCover(images)}<span class="sp-board-title">${escapeHTML(title)}${badge}</span><span class="sp-board-meta">${findsLabel(count)} · ${escapeHTML(updatedLabel(updatedAt))}</span></a>`;
}

function profilePage({ profile, boards, curated = false, shareImage = null }) {
  const username = String(profile.username ?? "").toLowerCase();
  const url = `${publicOrigin}/${username}`;
  const stackCount = boards.length;
  const itemCount = boards.reduce((total, board) => total + board.count, 0);
  const handle = `@${escapeHTML(profile.username)}${curated ? " · Curated by Stacks" : ""}`;
  const grid = boards.length
    ? `<section class="sp-board-grid" aria-label="Public Stacks">${boards.map(boardCard).join("")}</section>`
    : `<section class="sp-empty"><h2>No public Stacks yet</h2><p>When @${escapeHTML(profile.username)} makes a Stack public in the app, it shows up here.</p></section>`;
  const description = profile.bio || `${profile.displayName}'s Stacks: ${stackCount} public ${stackCount === 1 ? "Stack" : "Stacks"} on Stacks.`;
  return htmlResponse(`<!doctype html><html lang="en">${pageHead({ title: `${profile.displayName} (@${profile.username}) · Stacks`, description, canonical: url, image: httpsURL(shareImage) ?? httpsURL(profile.avatarURL) })}<body class="sp-page">${boardNav}<main class="sp-main"><header class="sp-profile">${avatarMarkup(profile, "sp-profile-avatar")}<h1>${escapeHTML(profile.displayName)}</h1><p class="sp-handle">${handle}</p>${profile.bio ? `<p class="sp-bio">${escapeHTML(profile.bio)}</p>` : ""}<p class="sp-stats"><strong>${stackCount}</strong> ${stackCount === 1 ? "Stack" : "Stacks"} · <strong>${itemCount}</strong> ${itemCount === 1 ? "find" : "finds"}</p><div class="sp-actions"><button class="sp-button" type="button" data-share="${escapeHTML(url)}">Share</button><a class="sp-button sp-button-dark" href="/waitlist">Get Stacks</a></div></header><nav class="sp-tabs" aria-label="Profile sections"><span aria-current="page">Stacks</span></nav>${grid}${boardFooter}</main>${shareScript}</body></html>`);
}

function formatPrice(price, currencyCode) {
  if (typeof price !== "number" || !Number.isFinite(price)) return "";
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: currencyCode || "USD", maximumFractionDigits: price % 1 ? 2 : 0 }).format(price);
  } catch {
    return "";
  }
}

function boardURL(stack) {
  const username = stack.author?.username ? String(stack.author.username).toLowerCase() : "";
  return username && stack.slug && stack.visibility !== "link_only" ? `${publicOrigin}/${username}/${stack.slug}` : null;
}

function boardPage(stack) {
  const items = (Array.isArray(stack.items) ? stack.items : []).filter(item => uuidPattern.test(item?.id ?? ""));
  const author = stack.author ?? null;
  const canonical = boardURL(stack) ?? `${publicOrigin}/s/${stack.id}`;
  const pins = items.map(item => {
    const image = httpsURL(item.imageURL);
    const price = formatPrice(item.price, item.currencyCode);
    const media = image
      ? `<img src="${escapeHTML(image)}" alt="${escapeHTML(item.title)}" loading="lazy">`
      : `<span class="sp-pin-fallback">${escapeHTML(item.brand || item.title || "Find")}</span>`;
    return `<a class="sp-pin" href="/s/${stack.id}/p/${item.id}"><span class="sp-pin-media">${media}${price ? `<span class="sp-pin-price">${escapeHTML(price)}</span>` : ""}</span><span class="sp-pin-title">${escapeHTML(item.title || "Untitled find")}</span>${item.brand ? `<span class="sp-pin-brand">${escapeHTML(item.brand)}</span>` : ""}</a>`;
  }).join("");
  const byline = author?.username
    ? `<a class="sp-byline" href="/${escapeHTML(String(author.username).toLowerCase())}">${avatarMarkup(author, "sp-byline-avatar")}<span>${escapeHTML(author.displayName)}</span></a>`
    : "";
  const grid = pins
    ? `<section class="sp-pin-grid" aria-label="Finds in ${escapeHTML(stack.title)}">${pins}</section>`
    : `<section class="sp-empty"><h2>Nothing here yet</h2><p>Finds added to this Stack in the app will show up here.</p></section>`;
  const description = `${findsLabel(items.length)} stacked by ${author?.displayName ?? "a Stacks member"}.`;
  const image = items.map(item => httpsURL(item.imageURL)).find(Boolean);
  return htmlResponse(`<!doctype html><html lang="en">${pageHead({ title: `${stack.title} · Stacks`, description, canonical, image, robots: stack.visibility === "link_only" ? "noindex, nofollow" : null })}<body class="sp-page">${boardNav}<main class="sp-main"><header class="sp-board-header"><h1>${escapeHTML(stack.title)}</h1>${byline}<p class="sp-stats">${findsLabel(items.length)} · Updated ${escapeHTML(updatedLabel(stack.updatedAt))}</p><div class="sp-actions"><button class="sp-button" type="button" data-share="${escapeHTML(canonical)}">Share</button></div></header>${grid}<aside class="demo-bottom-cta"><h2>Make a Stack of your own.</h2><p>Save the things you love in one place.</p><a class="button" href="/waitlist">Claim your username ↗</a></aside>${boardFooter}</main>${shareScript}</body></html>`);
}

function pinPage(stack, item) {
  const image = httpsURL(item.imageURL);
  let destination = null;
  try {
    const parsed = item.buyURL ? new URL(item.buyURL) : null;
    destination = parsed?.protocol === "https:" ? parsed : null;
  } catch { destination = null; }
  const retailer = destination ? destination.hostname.replace(/^www\./, "") : "";
  const price = formatPrice(item.price, item.currencyCode);
  const back = boardURL(stack) ?? `/s/${stack.id}`;
  const rows = [
    item.brand ? `<div class="product-info-row"><span>Brand</span><strong>${escapeHTML(item.brand)}</strong></div>` : "",
    price ? `<div class="product-info-row"><span>Price</span><strong>${escapeHTML(price)}</strong></div>` : "",
    item.sizeText ? `<div class="product-info-row"><span>Size</span><strong>${escapeHTML(item.sizeText)}</strong></div>` : "",
    `<div class="product-info-row"><span>Stack</span><strong><a href="${escapeHTML(back)}">${escapeHTML(stack.title)}</a></strong></div>`,
  ].join("");
  const buy = destination
    ? `<a class="product-buy" href="${escapeHTML(destination.href)}" target="_blank" rel="noopener noreferrer"><span>View at ${escapeHTML(retailer)}</span><span aria-hidden="true">↗</span></a>`
    : "";
  return htmlResponse(`<!doctype html><html lang="en">${pageHead({ title: `${item.title || "Find"} · Stacks`, description: `From ${stack.title}${stack.author?.displayName ? ` by ${stack.author.displayName}` : ""} on Stacks.`, canonical: `${publicOrigin}/s/${stack.id}/p/${item.id}`, image, robots: stack.visibility === "link_only" ? "noindex, nofollow" : null })}<body class="product-page"><main class="product-main"><nav class="product-navigation" aria-label="Product navigation"><a class="product-nav-circle" href="${escapeHTML(back)}" aria-label="Back to ${escapeHTML(stack.title)}">‹</a></nav><div class="product-stage">${image ? `<img src="${escapeHTML(image)}" alt="${escapeHTML(item.title)}">` : `<span class="curated-item-fallback">${escapeHTML(item.brand)}<small>${escapeHTML(item.title)}</small></span>`}</div><h1>${escapeHTML(item.title || "Untitled find")}</h1>${item.description ? `<p class="sp-pin-description">${escapeHTML(item.description)}</p>` : ""}<section class="product-info" aria-label="Product information">${rows}</section></main><aside class="product-actions">${buy}<a class="product-download" href="/waitlist">Claim your username</a></aside></body></html>`);
}

// Fetches a Stack as JSON from web-preview. Returns { stack } or { error }.
async function stackPayload(upstream, upstreamFetch) {
  let response;
  try {
    response = await upstreamFetch(upstream, {
      headers: { Accept: "application/json", "X-Stacks-Web-Proxy": "1" },
      redirect: "manual",
    });
  } catch (error) {
    console.error("Stacks board request failed", error);
    return { error: informationPage("Temporarily unavailable", "Please try opening this page again shortly.", 503) };
  }
  if (response.status === 400 || response.status === 404) {
    return { error: informationPage("Stack unavailable", "This Stack is private, expired, or no longer shared.", 404) };
  }
  if (!response.ok) {
    return { error: informationPage("Temporarily unavailable", "Please try opening this page again shortly.", 503) };
  }
  const payload = await response.json().catch(() => null);
  const stack = payload?.stack;
  return { stack: stack && uuidPattern.test(stack.id ?? "") && typeof stack.title === "string" ? stack : null };
}

// Public boards render here. Wishlists keep web-preview's page, which carries
// the email-verified gift-claim flow.
async function boardOrUpstream(upstream, upstreamFetch) {
  const { stack, error } = await stackPayload(upstream, upstreamFetch);
  if (error) return error;
  if (!stack || stack.wishlistMode) return upstreamPage(upstream, upstreamFetch);
  return boardPage(stack);
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
    if (url.pathname === "/analytics.js") return analyticsScript(env);
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
      if (stack) return item ? curatedProductPage(stack, item) : informationPage("Product unavailable", "That product isn't in this Stack.", 404);
      if (!uuidPattern.test(curatedProductMatch[1]) || !uuidPattern.test(curatedProductMatch[2])) {
        return informationPage("Product unavailable", "This product link is invalid.", 404);
      }
      const upstream = new URL(supabasePreview);
      upstream.searchParams.set("stackID", curatedProductMatch[1]);
      const token = url.searchParams.get("token");
      if (token && uuidPattern.test(token)) upstream.searchParams.set("token", token);
      const { stack: liveStack, error } = await stackPayload(upstream, fetch);
      if (error) return error;
      const liveItem = liveStack?.items?.find(candidate => String(candidate.id).toLowerCase() === curatedProductMatch[2].toLowerCase());
      return liveStack && liveItem ? pinPage(liveStack, liveItem) : informationPage("Product unavailable", "That product isn't in this Stack.", 404);
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
      if (token) {
        upstream.searchParams.set("token", token);
        return upstreamPage(upstream, fetch, { linkOnly: true });
      }
      return boardOrUpstream(upstream, fetch);
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
      return boardOrUpstream(upstream, fetch);
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
