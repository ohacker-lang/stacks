const publicOrigin = "https://stacks.spot";
const supabasePreview = "https://iuovmgjcfwgwozfnsdgf.supabase.co/functions/v1/web-preview";
const policyPages = new Set([
  "terms", "privacy", "security", "support", "affiliate", "privacy-choices",
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
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

function informationPage(title, message, status = 200) {
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHTML(title)} · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="message-page"><main class="message-card"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><h1>${escapeHTML(title)}</h1><p>${escapeHTML(message)}</p><a class="button" href="/">Back to Stacks</a></main></body></html>`, status, { "X-Robots-Tag": "noindex" });
}

function localizeHTML(html) {
  return html
    .replace(/href="\?page=(terms|privacy|security|support|affiliate|privacy-choices)"/g, 'href="/$1"')
    .replace(/href="https:\/\/iuovmgjcfwgwozfnsdgf\.supabase\.co\/functions\/v1\/web-preview\?page=(terms|privacy|security|support|affiliate|privacy-choices)"/g, 'href="/$1"')
    .replace("</head>", '<link rel="stylesheet" href="/site.css"></head>')
    .replace("<nav><strong>Stacks</strong>", '<nav><a class="legal-wordmark" href="/">Stacks</a>')
    .replace("<span>For iPhone · coming soon</span>", '<a class="get-app" href="/download">Download Stacks</a>')
    .replace(/<section class="pitch">[\s\S]*?<\/section>/, section => section.includes('class="get-app"')
      ? section
      : section.replace('</section>', '<a class="get-app" href="/download">Download Stacks</a></section>'));
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
  return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>You're invited to a Collab · Stacks</title><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="message-page"><main class="message-card"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><h1>You're invited to a Collab.</h1><p>Open this invitation in Stacks to see the shared Stack and join in.</p><a class="button" href="${deepLink}">Open Stacks</a><a class="button secondary" href="/download">Download Stacks</a></main></body></html>`, 200, {
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
    const cards = payload.stacks.map((stack) => {
      if (!uuidPattern.test(stack.id)) return "";
      const images = (Array.isArray(stack.images) ? stack.images : []).slice(0, 4)
        .filter((image) => typeof image === "string" && image.startsWith("https://"))
        .map((image) => `<img src="${escapeHTML(image)}" alt="" loading="lazy">`).join("");
      const avatar = typeof stack.author?.avatarURL === "string" && stack.author.avatarURL.startsWith("https://")
        ? `<img src="${escapeHTML(stack.author.avatarURL)}" alt="" loading="lazy">`
        : `<span>${escapeHTML(String(stack.author?.displayName ?? "S").slice(0, 1))}</span>`;
      return `<a class="public-stack-card" href="/s/${stack.id}"><div class="public-stack-art">${images || '<span class="public-stack-empty">A new Stack</span>'}</div><h2>${escapeHTML(stack.title)}</h2><div class="public-stack-author"><span class="public-stack-avatar">${avatar}</span><span>${escapeHTML(stack.author?.displayName ?? "Stacks")}</span><span class="public-stack-arrow" aria-hidden="true">↗</span></div></a>`;
    }).join("");
    const pagination = `<nav class="public-pagination" aria-label="Pages">${page > 1 ? `<a href="/stacks?page=${page - 1}">Previous</a>` : ""}${payload.hasMore ? `<a href="/stacks?page=${page + 1}">Next</a>` : ""}</nav>`;
    return htmlResponse(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Explore public Stacks · Stacks</title><meta name="description" content="Discover public Stacks made in the app."><link rel="icon" type="image/png" href="/assets/stacks-logo.png"><link rel="stylesheet" href="/site.css"></head><body class="public-page"><main class="public-main"><nav class="demo-topline"><a class="wordmark" href="/"><img class="wordmark-logo" src="/assets/stacks-logo.png" alt="">Stacks</a><div class="site-nav-links"><a href="/">Stacks</a><a href="/download">Download</a><a href="/stacks" aria-current="page">Explore</a></div></nav><header class="public-heading"><p class="eyebrow">From the app</p><h1>Explore Stacks.</h1><p>Public finds from people using Stacks.</p><a class="button" href="/download">Download Stacks</a></header><section class="public-grid" aria-label="Public Stacks">${cards || '<p class="public-empty">No public Stacks to show yet.</p>'}</section>${pagination}<footer class="demo-footer"><a href="/download">Download</a><a href="/terms">Terms</a><a href="/privacy">Privacy</a><a href="/support">Support</a></footer></main></body></html>`);
  } catch (error) {
    console.error("Stacks public feed failed", error);
    return informationPage("Temporarily unavailable", "Please try exploring Stacks again shortly.", 503);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    if (url.hostname.toLowerCase() === "www.stacks.spot") {
      return Response.redirect(`${publicOrigin}${url.pathname}${url.search}`, 308);
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

    const stackMatch = /^\/s\/([^/]+)\/?$/.exec(url.pathname);
    if (stackMatch) {
      const stackID = stackMatch[1];
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
    if (url.pathname === "/download" || url.pathname === "/download/") {
      return env.ASSETS.fetch(new Request(new URL("/download", url), request));
    }

    if (url.pathname === "/" || url.pathname === "/index.html" || url.pathname === "/site.css" || url.pathname === "/site.js" || url.pathname.startsWith("/assets/")) {
      return env.ASSETS.fetch(request);
    }
    return informationPage("Page not found", "That page isn't available.", 404);
  },
};
