import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { isUUID, serviceClient } from "../_shared/supabase.ts";

const bucket = "stack-media";

function stackSlug(title: string): string {
  return (title ?? "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "stack";
}

type PreviewItem = {
  id: string;
  title: string;
  brand: string;
  description: string;
  price: number | null;
  currency_code: string | null;
  size_text: string;
  buy_url: string | null;
  affiliate_url: string | null;
  original_image_path: string | null;
  removed_background_image_path: string | null;
  removal_status: string;
  placement_x: number;
  placement_y: number;
  placement_scale: number;
  rotation_degrees: number;
  has_custom_placement: boolean;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const url = new URL(req.url);
    const legalPage = url.searchParams.get("page");
    if (legalPage && ["privacy", "terms", "security", "support", "affiliate", "privacy-choices"].includes(legalPage)) {
      const destination = publicSiteURL(req, `/${legalPage}`);
      if (destination) return Response.redirect(destination, 308);
      return publicInformationPage(legalPage);
    }
    if (url.searchParams.get("feed") === "public") {
      const rawPage = url.searchParams.get("page") ?? "1";
      if (!/^[1-9][0-9]{0,3}$/.test(rawPage)) return jsonResponse({ error: "Invalid page." }, 400);
      return await publicStackFeed(Number(rawPage));
    }
    const publicUsername = url.searchParams.get("profile")?.trim().toLowerCase();
    if (publicUsername) {
      if (!/^[a-z0-9_]{3,30}$/.test(publicUsername)) return jsonResponse({ error: "Profile unavailable." }, 404);
      return await publicProfile(publicUsername);
    }
    const admin = serviceClient();
    let stackID = url.searchParams.get("stackID")?.trim() ?? "";
    const stackUsername = url.searchParams.get("stackUsername")?.trim().toLowerCase() ?? "";
    const stackPathSlug = url.searchParams.get("stackSlug")?.trim().toLowerCase() ?? "";
    const linkToken = url.searchParams.get("token")?.trim() ?? "";
    if (stackUsername || stackPathSlug) {
      if (!/^[a-z0-9_]{3,30}$/.test(stackUsername) || !/^[a-z0-9-]{1,80}$/.test(stackPathSlug)) {
        return jsonResponse({ error: "Stack unavailable." }, 404);
      }
      const { data: owner } = await admin
        .from("profiles")
        .select("id")
        .eq("username", stackUsername)
        .maybeSingle();
      if (!owner) return jsonResponse({ error: "Stack unavailable." }, 404);
      const { data: candidates, error: candidateError } = await admin
        .from("stacks")
        .select("id, title")
        .eq("owner_id", owner.id)
        .eq("visibility", "public");
      if (candidateError) throw candidateError;
      stackID = candidates?.find(candidate => stackSlug(candidate.title) === stackPathSlug)?.id ?? "";
    }
    if (!isUUID(stackID)) return jsonResponse({ error: "A valid Stack is required." }, 400);

    const sharedPath = `/s/${stackID}${isUUID(linkToken) ? `?token=${encodeURIComponent(linkToken)}` : ""}`;
    const destination = publicSiteURL(req, sharedPath);
    if (destination) return Response.redirect(destination, 308);

    const stack = await loadSharedStack(admin, stackID, linkToken);
    if (!stack) return jsonResponse({ error: "This Stack is unavailable." }, 404);

    const { data: profile } = await admin
      .from("profiles")
      .select("display_name, username, avatar_path")
      .eq("id", stack.owner_id)
      .single();
    const { data: items, error: itemsError } = await admin
      .from("stack_items")
      .select("id, title, brand, description, price, currency_code, size_text, buy_url, affiliate_url, original_image_path, removed_background_image_path, removal_status, placement_x, placement_y, placement_scale, rotation_degrees, has_custom_placement")
      .eq("stack_id", stack.id)
      .order("created_at");
    if (itemsError) throw itemsError;

    const { data: claims, error: claimsError } = await admin.from("gift_claims")
      .select("item_id, status")
      .eq("stack_id", stack.id)
      .in("status", ["claimed", "purchased"]);
    if (claimsError) throw claimsError;
    const claimByItem = new Map((claims ?? []).map((claim) => [claim.item_id, claim.status]));
    const previewItems = await Promise.all((items ?? []).map((item) =>
      toPreviewItem(admin, item as PreviewItem, claimByItem.get(item.id) ?? null)));
    const avatarURL = profile?.avatar_path
      ? (await admin.storage.from("profile-media").createSignedUrl(profile.avatar_path, 300)).data?.signedUrl ?? null
      : null;
    const payload = {
      stack: {
        id: stack.id,
        title: stack.title,
        wishlistMode: stack.wishlist_mode,
        author: profile ? {
          displayName: profile.display_name,
          username: profile.username,
          avatarURL,
        } : null,
        items: previewItems,
      },
    };
    if ((req.headers.get("accept") ?? "").includes("text/html")) {
      return new Response(renderPage(payload.stack, stackID, linkToken), {
        headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
      });
    }
    return jsonResponse(payload);
  } catch (error) {
    console.error("web-preview", error);
    return jsonResponse({ error: "Unable to load this Stack." }, 500);
  }
});

async function publicStackFeed(page: number): Promise<Response> {
  const admin = serviceClient();
  const pageSize = 12;
  // A public link alone is not consent to be listed. Respect the owner's
  // Discover opt-in, and never include private or link-only Stacks here.
  const { data: stacks, error } = await admin.from("stacks")
    .select("id, title, owner_id, updated_at, profiles!stacks_owner_id_fkey!inner(display_name, username, avatar_path, discovery_enabled)")
    .eq("visibility", "public")
    .eq("profiles.discovery_enabled", true)
    .order("updated_at", { ascending: false })
    .range((page - 1) * pageSize, page * pageSize);
  if (error) throw error;
  const hasMore = (stacks ?? []).length > pageSize;
  const results = await Promise.all((stacks ?? []).slice(0, pageSize).map(async (stack) => {
    const profile = Array.isArray(stack.profiles) ? stack.profiles[0] : stack.profiles;
    const { data: items, error: itemError, count: itemCount } = await admin.from("stack_items")
      .select("removed_background_image_path, original_image_path", { count: "exact" })
      .eq("stack_id", stack.id)
      .order("created_at")
      .limit(6);
    if (itemError) throw itemError;
    const imagePaths = (items ?? []).map((item) => item.removed_background_image_path ?? item.original_image_path).filter((path): path is string => Boolean(path));
    const images = await Promise.all(imagePaths.map(async (path) =>
      (await admin.storage.from(bucket).createSignedUrl(path, 300)).data?.signedUrl ?? null
    ));
    const avatarURL = profile?.avatar_path
      ? (await admin.storage.from("profile-media").createSignedUrl(profile.avatar_path, 300)).data?.signedUrl ?? null
      : null;
    return {
      id: stack.id,
      title: stack.title,
      updatedAt: stack.updated_at,
      author: {
        displayName: profile?.display_name ?? "Stacks",
        username: profile?.username ?? "",
        avatarURL,
      },
      itemCount: itemCount ?? items?.length ?? 0,
      images: images.filter((image): image is string => Boolean(image)),
    };
  }));
  return new Response(JSON.stringify({ stacks: results, page, hasMore }), {
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
  });
}

async function publicProfile(username: string): Promise<Response> {
  const admin = serviceClient();
  const { data: profile, error: profileError } = await admin.from("profiles")
    .select("id, display_name, username, bio, avatar_path, discovery_enabled, profile_share_enabled")
    .eq("username", username)
    .maybeSingle();
  if (profileError) throw profileError;
  if (!profile) return jsonResponse({ error: "Profile unavailable." }, 404);

  const { data: stacks, error: stackError } = await admin.from("stacks")
    .select("id, title, updated_at")
    .eq("owner_id", profile.id)
    .eq("visibility", "public")
    .order("updated_at", { ascending: false })
    .limit(24);
  if (stackError) throw stackError;
  // Sharing one's profile is an explicit opt-in; a public Stack also exposes
  // its byline without making unrelated private Stacks or bio public.
  if (!profile.profile_share_enabled && !profile.discovery_enabled && (stacks ?? []).length === 0) {
    return jsonResponse({ error: "Profile unavailable." }, 404);
  }
  const avatarURL = profile.avatar_path
    ? (await admin.storage.from("profile-media").createSignedUrl(profile.avatar_path, 300)).data?.signedUrl ?? null
    : null;
  const publicStacks = await Promise.all((stacks ?? []).map(async (stack) => {
    const { data: items, error } = await admin.from("stack_items")
      .select("removed_background_image_path, original_image_path")
      .eq("stack_id", stack.id)
      .order("created_at")
      .limit(4);
    if (error) throw error;
    const images = await Promise.all((items ?? []).map(async (item) => {
      const path = item.removed_background_image_path ?? item.original_image_path;
      return path ? (await admin.storage.from(bucket).createSignedUrl(path, 300)).data?.signedUrl ?? null : null;
    }));
    return { id: stack.id, title: stack.title, images: images.filter((image): image is string => Boolean(image)) };
  }));
  return jsonResponse({ profile: {
    displayName: profile.display_name,
    username: profile.username,
    bio: profile.discovery_enabled ? profile.bio : "",
    avatarURL,
  }, stacks: publicStacks });
}

function publicSiteURL(req: Request, path: string): string | null {
  if (!(req.headers.get("accept") ?? "").includes("text/html") || req.headers.get("x-stacks-web-proxy") === "1") return null;
  const site = Deno.env.get("STACKS_PUBLIC_SITE_URL")?.trim();
  if (!site) return null;
  try {
    const origin = new URL(site);
    return origin.protocol === "https:" ? new URL(path, origin).href : null;
  } catch {
    return null;
  }
}

async function loadSharedStack(
  admin: ReturnType<typeof serviceClient>,
  stackID: string,
  linkToken: string,
) {
  const { data: publicStack, error: publicError } = await admin
    .from("stacks")
    .select("id, owner_id, title, wishlist_mode, visibility")
    .eq("id", stackID)
    .eq("visibility", "public")
    .maybeSingle();
  if (!publicError && publicStack) return publicStack;

  if (!isUUID(linkToken)) return null;
  const { data: linkOnlyStack, error: linkError } = await admin
    .from("stacks")
    .select("id, owner_id, title, wishlist_mode, visibility")
    .eq("id", stackID)
    .eq("visibility", "link_only")
    .eq("public_link_token", linkToken)
    .maybeSingle();
  return linkError ? null : linkOnlyStack;
}

async function toPreviewItem(admin: ReturnType<typeof serviceClient>, item: PreviewItem, claimStatus: string | null) {
  const imagePath = item.removed_background_image_path ?? item.original_image_path;
  const imageURL = imagePath
    ? (await admin.storage.from(bucket).createSignedUrl(imagePath, 300)).data?.signedUrl ?? null
    : null;
  return {
    id: item.id,
    title: item.title,
    brand: item.brand,
    description: item.description,
    price: item.price,
    currencyCode: item.currency_code,
    sizeText: item.size_text,
    // Browser guests are not sent a stored affiliate link. Eligibility must be
    // checked for their own country before a commissionable URL is used.
    buyURL: item.buy_url,
    imageURL,
    removalStatus: item.removal_status,
    claimStatus,
    hasCustomPlacement: item.has_custom_placement,
    placement: {
      x: item.placement_x,
      y: item.placement_y,
      scale: item.placement_scale,
      rotationDegrees: item.rotation_degrees,
    },
  };
}

type BrowserStack = {
  title: string;
  wishlistMode: boolean;
  author: { displayName: string; username: string; avatarURL: string | null } | null;
  items: Awaited<ReturnType<typeof toPreviewItem>>[];
};

function escapeHTML(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character] ?? character));
}

function safeExternalURL(value: string | null): string | null {
  if (!value) return null;
  try {
    const parsed = new URL(value);
    return ["http:", "https:"].includes(parsed.protocol) ? parsed.href : null;
  } catch {
    return null;
  }
}

function renderPage(stack: BrowserStack, stackID: string, linkToken: string): string {
  const author = stack.author;
  const avatar = safeExternalURL(author?.avatarURL ?? null);
  const cutouts = stack.items.map((item, index) => {
    const image = safeExternalURL(item.imageURL);
    const buy = safeExternalURL(item.buyURL);
    const claimed = item.claimStatus === "claimed" || item.claimStatus === "purchased";
    const page = Math.floor(index / 6);
    const count = Math.min(6, stack.items.length - page * 6);
    const indexInPage = index % 6;
    const rows = Math.ceil(count / 2);
    const defaultX = count % 2 === 1 && indexInPage === count - 1 ? 50 : indexInPage % 2 === 0 ? 25 : 75;
    const defaultY = ((Math.floor(indexInPage / 2) + 0.5) / rows) * 100;
    const pageHeight = stack.items.length <= 6 || count < 6 ? 520 : 420;
    const pageStart = page * 420;
    const x = item.hasCustomPlacement ? item.placement.x * 100 : defaultX;
    const y = item.hasCustomPlacement ? item.placement.y * 100 : defaultY;
    const rotation = item.hasCustomPlacement ? Math.max(-25, Math.min(25, item.placement.rotationDegrees || 0)) : 0;
    const width = Math.max(24, Math.min(count === 1 ? 64 : 42, (count === 1 ? 64 : 42) * (item.hasCustomPlacement ? item.placement.scale : 1)));
    return `<button class="sticker${claimed ? " claimed" : ""}" type="button" data-item-id="${escapeHTML(item.id)}" data-title="${escapeHTML(item.title)}" data-brand="${escapeHTML(item.brand)}" data-image="${escapeHTML(image ?? "")}" data-buy="${escapeHTML(buy ?? "")}" data-claimed="${claimed}" style="left:${x}%;top:${pageStart + y * pageHeight / 100}px;width:${width}%;transform:translate(-50%,-50%) rotate(${rotation}deg)" aria-label="${escapeHTML(item.title)}${claimed ? ", claimed" : ""}">
      ${image ? `<img src="${escapeHTML(image)}" alt="">` : `<span>${escapeHTML(item.title)}</span>`}</button>`;
  }).join("");
  const projectURL = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const appStoreURL = safeExternalURL(Deno.env.get("STACKS_APP_STORE_URL") ?? null);
  const fullPages = Math.floor(stack.items.length / 6);
  const trailingItems = stack.items.length % 6;
  const canvasHeight = Math.max(520, fullPages * 420 + (trailingItems ? 520 : 0));
  const legalBase = `${projectURL}/functions/v1/web-preview?page=`;
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>${escapeHTML(stack.title)} · Stacks</title><style>
    *{box-sizing:border-box}body{margin:0;background:#fff;color:#171717;font:16px -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}main{max-width:560px;margin:auto;padding:16px 16px 110px}
    .topline{display:flex;align-items:center;justify-content:space-between;height:44px}.wordmark{font-weight:750;font-size:20px;letter-spacing:-.05em}.get-app{border-radius:99px;background:#171717;color:#fff;text-decoration:none;padding:11px 16px;font-size:13px;font-weight:650}
    h1{font-size:clamp(40px,10vw,49px);line-height:1;letter-spacing:-.043em;margin:20px 4px 11px;overflow-wrap:anywhere}header{border-bottom:1px solid #ddd;padding:0 4px 10px}header p{font-size:13px;color:#6d6d6d;line-height:1.4}
    .byline{display:flex;align-items:center;gap:7px;font-size:14px;color:#444}.byline img,.avatar{width:22px;height:22px;border-radius:50%;object-fit:cover;background:#ddd}.avatar{display:grid;place-items:center;font-size:12px}.byline .date{margin-left:auto;text-align:right;font-size:10px;color:#777}
    .canvas{position:relative;width:100%;overflow:hidden;margin-top:14px}.sticker{position:absolute;display:grid;place-items:center;aspect-ratio:1;border:0;background:transparent;padding:0;cursor:pointer}.sticker img{width:100%;height:100%;object-fit:contain;filter:drop-shadow(0 4px 6px #0002)}.sticker.claimed{filter:grayscale(1);opacity:.3}.sticker span{font-size:13px}
    .pitch{border-top:1px solid #ddd;padding:25px 4px;text-align:center}.pitch h2{font-size:25px;letter-spacing:-.04em;margin:0 0 8px}.pitch p{color:#666;line-height:1.4}.pitch .get-app{display:inline-block;margin-top:6px}footer{display:flex;justify-content:center;gap:16px;flex-wrap:wrap;font-size:12px;padding:28px 4px}footer a{color:#666}
    dialog{border:0;border-radius:24px;padding:28px;width:min(92vw,400px);box-shadow:0 20px 80px #0003}dialog::backdrop{background:#0007}dialog h2{margin-top:0}dialog input{display:block;width:100%;padding:13px;border:1px solid #ccc;border-radius:12px;margin:12px 0;font:inherit}dialog button,.retailer{border:0;border-radius:99px;padding:11px 16px;background:#171717;color:#fff;text-decoration:none;font:600 13px -apple-system,BlinkMacSystemFont,sans-serif;cursor:pointer;display:inline-block;margin:5px 4px 5px 0}.retailer{background:#ececec;color:#171717}.error{color:#a22;min-height:20px;font-size:13px}
</style></head><body><main><div class="topline"><span class="wordmark">Stacks</span>${appStoreURL ? `<a class="get-app" href="${escapeHTML(appStoreURL)}">Get the app</a>` : `<span>For iPhone · coming soon</span>`}</div><header><h1>${escapeHTML(stack.title)}</h1><div class="byline">${avatar ? `<img src="${escapeHTML(avatar)}" alt="">` : `<span class="avatar">${escapeHTML(author?.displayName?.slice(0, 1) ?? "S")}</span>`}<span>${escapeHTML(author?.displayName ?? "Stacks")}</span><span class="date">${stack.items.length} ${stack.items.length === 1 ? "find" : "finds"}</span></div></header><section class="canvas" aria-label="Products in this Stack" style="height:${canvasHeight}px">${cutouts}</section><section class="pitch"><h2>Keep your finds together.</h2><p>Make your own Stacks for inspiration or wishlists to share.</p>${appStoreURL ? `<a class="get-app" href="${escapeHTML(appStoreURL)}">Download Stacks</a>` : ""}</section><footer><a href="${escapeHTML(legalBase)}privacy">Privacy</a><a href="${escapeHTML(legalBase)}terms">Terms</a><a href="${escapeHTML(legalBase)}affiliate">Affiliate disclosure</a><a href="${escapeHTML(legalBase)}privacy-choices">Privacy choices</a><a href="${escapeHTML(legalBase)}security">Security</a><a href="${escapeHTML(legalBase)}support">Support</a></footer></main>
    <dialog id="item-dialog"><h2 id="item-title"></h2><p id="item-brand"></p><img id="item-image" alt="" style="width:100%;max-height:230px;object-fit:contain"><div><a id="item-buy" class="retailer" target="_blank" rel="noopener noreferrer">Visit retailer</a><button id="item-claim" type="button">Claim gift</button><button id="item-close" type="button">Close</button></div></dialog>
    <dialog id="claim-dialog" class="modal"><h2>Claim this gift</h2><p>Verify your email so the gift is reserved for you.</p><input id="claim-name" autocomplete="name" placeholder="Your name"><input id="claim-email" type="email" autocomplete="email" placeholder="Email address"><button id="send-code">Send code</button><input id="claim-code" inputmode="numeric" autocomplete="one-time-code" placeholder="Email code" hidden><button id="confirm-claim" hidden>Verify and claim</button><p id="claim-error" class="error" role="alert"></p><button id="cancel-claim" type="button">Cancel</button></dialog>
    <script>
    const api=${JSON.stringify(projectURL)},key=${JSON.stringify(anonKey)},stackID=${JSON.stringify(stackID)},linkToken=${JSON.stringify(linkToken)};
    const dialog=document.querySelector('#claim-dialog'),error=document.querySelector('#claim-error');let itemID=null;
    const itemDialog=document.querySelector('#item-dialog');
    document.querySelectorAll('[data-item-id]').forEach(button=>button.addEventListener('click',()=>{const data=button.dataset;itemID=data.itemId;document.querySelector('#item-title').textContent=data.title;document.querySelector('#item-brand').textContent=data.brand;const image=document.querySelector('#item-image');image.src=data.image;image.hidden=!data.image;const buy=document.querySelector('#item-buy');buy.href=data.buy;buy.hidden=!data.buy;const claim=document.querySelector('#item-claim');claim.hidden=${!stack.wishlistMode}||data.claimed==='true';itemDialog.showModal()}));
    document.querySelector('#item-close').onclick=()=>itemDialog.close();
    document.querySelector('#item-claim').onclick=()=>{itemDialog.close();error.textContent='';dialog.showModal()};
    document.querySelector('#cancel-claim').onclick=()=>dialog.close();
    document.querySelector('#send-code').onclick=async()=>{const email=document.querySelector('#claim-email').value.trim();if(!email){error.textContent='Enter your email.';return}try{const res=await fetch(api+'/auth/v1/otp',{method:'POST',headers:{'Content-Type':'application/json',apikey:key},body:JSON.stringify({email,create_user:true})});if(!res.ok)throw new Error('Could not send a code.');document.querySelector('#claim-code').hidden=false;document.querySelector('#confirm-claim').hidden=false;error.textContent='Check your email for the verification code.'}catch(e){error.textContent=e.message}};
    document.querySelector('#confirm-claim').onclick=async()=>{const name=document.querySelector('#claim-name').value.trim(),email=document.querySelector('#claim-email').value.trim(),token=document.querySelector('#claim-code').value.trim();if(!name||!token){error.textContent='Enter your name and email code.';return}try{const verify=await fetch(api+'/auth/v1/verify',{method:'POST',headers:{'Content-Type':'application/json',apikey:key},body:JSON.stringify({email,token,type:'email'})});const session=await verify.json();if(!verify.ok||!session.access_token)throw new Error('That code could not be verified.');const response=await fetch(api+'/functions/v1/claim-gift',{method:'POST',headers:{'Content-Type':'application/json',apikey:key,Authorization:'Bearer '+session.access_token},body:JSON.stringify({stackID,itemID,claimerName:name,linkToken:linkToken||null})});const result=await response.json();if(!response.ok)throw new Error(result.error||'Could not claim this gift.');dialog.close();location.reload()}catch(e){error.textContent=e.message}};
    </script></body></html>`;
}

function publicInformationPage(page: string): Response {
  const operator = Deno.env.get("STACKS_LEGAL_NAME")?.trim();
  const support = Deno.env.get("STACKS_SUPPORT_EMAIL")?.trim();
  if (!operator || !support || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(support)) {
    return new Response("Public policy pages are not configured yet.", { status: 503 });
  }
  const email = escapeHTML(support);
  const name = escapeHTML(operator);
  const sections: Record<string, { title: string; body: string }> = {
    privacy: {
      title: "Privacy Policy",
      body: `<p class="effective">Updated October 4, 2026</p><p>${name} operates Stacks. This policy explains the information Stacks processes in the app and browser viewer, why we process it, and the choices available to you.</p>
      <h2>Information we process</h2><p>We process account details such as email address, display name, username and profile photo; Stacks, saved products, photos and links you provide; collaboration, follow, report, block and wishlist-claim activity; subscription entitlement state; price-alert settings and observed retailer prices; device push tokens and notification preferences; and limited technical logs needed to operate, diagnose and protect the service. We do not ask for payment-card details for retailer purchases because those purchases occur with the retailer.</p>
      <h2>How we use information</h2><p>We use this information to authenticate you, display and sync your content, import products, monitor product pages when you enable a price alert, deliver requested notifications, enable sharing and collaboration, administer wishlist claims, provide support, prevent abuse, maintain security, comply with law and improve reliability. Where EU or UK law applies, our legal bases may include performing our contract with you, our legitimate interests in operating and securing Stacks, your consent where required, and compliance with legal obligations.</p>
      <h2>Price alerts and notifications</h2><p>If you create a price alert, our servers periodically request the product page you chose and store price observations, check times and error status. Prices may be delayed, unavailable or inaccurate, and an alert is not a price guarantee. Push notifications require your device token and Apple processes delivery under its own privacy terms. You can disable price notifications in Stacks or in iOS Settings and can delete an alert at any time.</p>
      <h2>Website waitlist</h2><p>If you join the waitlist, we store your requested username, email address and signup time to reserve the name and contact you about launch. A website reservation is not proof that you own the email address; we may require email verification before attaching the username to an app account. We do not use waitlist email addresses for unrelated marketing without separate consent. To change or remove a reservation, contact <a href="mailto:${email}">${email}</a>.</p>
      <h2>Sharing and visibility</h2><p>Public Stacks can be viewed by others. When you choose Share profile, your name, username and profile photo become available at stacks.spot/your-username; this does not list your private or link-only Stacks or opt you into Discover. You can turn off direct profile sharing from the same menu, although a Discover profile or public Stack may still make that page accessible. Anyone holding an active link-only Stack URL may be able to view that Stack. Private Stacks are limited to authorized members. Collaborators can access content in their shared Stack. Choose visibility carefully and do not place sensitive information in public or link-only content.</p>
      <h2>Service providers</h2><p>We use service providers, including Supabase, for authentication, database, storage and server functions. We disclose only information reasonably needed for those providers to perform services for us. Providers may process information in countries other than your own; where required, we rely on recognized transfer safeguards.</p>
      <h2>Affiliate links and external retailers</h2><p>For a potential affiliate link, our server may send the destination product URL and a two-letter country code to an affiliate-link provider to determine whether the retailer is eligible and to return a qualifying referral URL. We do not send your Stacks account ID, name, email address or an app advertising identifier with that request. A qualifying link is labeled before you click it. Once you open an external retailer or affiliate destination, that third party processes information under its own privacy notice and may use cookies or similar technologies. See our <a href="?page=affiliate">Affiliate Disclosure</a>.</p>
      <h2>Tracking and cookies</h2><p>Stacks does not currently include a third-party advertising SDK or use app data to track you across other companies’ apps or websites. The browser viewer does not currently set nonessential advertising cookies. If we introduce tracking or nonessential cookies, we will update this policy and request consent where required before enabling them.</p>
      <h2>Retention and deletion</h2><p>We retain account and content data while your account is active and as needed to provide Stacks. When you delete your account, we delete or de-identify account content subject to limited retention needed for security, fraud prevention, dispute resolution, backups and legal obligations. The exact period depends on the record and reason it is retained. You can request account deletion inside the app.</p>
      <h2>Your privacy rights</h2><p>Depending on where you live, you may have rights to access, correct, delete, restrict or object to processing, receive a portable copy, withdraw consent, or appeal a decision. You may also complain to your local data-protection authority. Use the in-app controls or email <a href="mailto:${email}">${email}</a>. We may need to verify your request and may retain information where permitted by law.</p>
      <h2>Children</h2><p>Stacks is not directed to children under 13, or under the minimum digital-consent age required where they live. If you believe a child provided personal information without appropriate authorization, contact us.</p>
      <h2>Changes and contact</h2><p>We may update this policy and will provide notice of material changes where required. Privacy questions or requests may be sent to <a href="mailto:${email}">${email}</a>.</p>`,
    },
    terms: {
      title: "Terms of Service",
      body: `<p class="effective">Effective September 21, 2026 · Version 2026-09-21</p><p>These Terms are a binding agreement between you and ${name}, the operator of Stacks. By affirmatively accepting these Terms, creating an account, or continuing to use Stacks after receiving notice of an updated version, you agree to them and acknowledge the <a href="?page=privacy">Privacy Policy</a>. If you do not agree, do not create an account or use Stacks.</p>
      <h2>Who may use Stacks</h2><p>You must be legally capable of entering this agreement and at least 13 years old, or older if your country requires a higher minimum age. If you use Stacks for an organization, you represent that you are authorized to bind it.</p>
      <h2>Your account</h2><p>Provide accurate information, protect your sign-in credentials, and promptly tell us about unauthorized access. You are responsible for activity through your account except to the extent caused by our failure to use reasonable care. We may suspend or terminate access for material or repeated violations, fraud, security risk, or legal necessity, subject to applicable law.</p>
      <h2>Your content and license to operate Stacks</h2><p>You retain ownership of content you submit. You grant ${name} a non-exclusive, worldwide, royalty-free license to host, store, reproduce, adapt solely for technical presentation, display, distribute and otherwise process that content only as needed to operate, secure, improve and promote the Stacks service according to your visibility choices. This license ends when the content is deleted except for reasonable backup periods, content already shared by others as permitted, and legal or security retention. You represent that you have the rights needed to submit the content and grant this license.</p>
      <h2>Acceptable use</h2><p>Do not upload or share unlawful, infringing, deceptive, harassing, hateful, sexually exploitative, privacy-invasive or malicious content; impersonate others; manipulate claims, follows or engagement; scrape or reverse engineer the service except where law permits; bypass access controls; introduce harmful code; or use Stacks to violate another person's rights. We may remove content and restrict accounts to protect users, third parties and the service. Public content may be reported and accounts may be blocked.</p>
      <h2>Brands, trademarks and product images</h2><p>Brand names, logos, product images and trademarks displayed in user content or retailer listings belong to their respective owners. Their appearance identifies products or sources and does not mean that a brand sponsors, endorses, is affiliated with, or has approved Stacks. Stacks does not grant you rights in third-party marks. Rights holders may report suspected infringement to <a href="mailto:${email}">${email}</a>; include the work or mark, the challenged material, its location, your contact information and a good-faith explanation.</p>
      <h2>Independent retailers and product information</h2><p>Stacks is a discovery and organization service, not the seller, manufacturer, payment processor, shipping provider or warranty provider for products linked in the service. Retailers are independent third parties. Product titles, images, descriptions, prices, availability and links may come from users, retailers or automated imports and may be incomplete, delayed or inaccurate. Verify material information with the retailer before purchasing. Transactions, payment, delivery, returns, recalls, warranties, taxes and disputes are governed by the retailer's terms and applicable law.</p>
      <h2>Affiliate links and advertising</h2><p>Some clearly marked links are advertising links. If you buy through a qualifying link, ${name} may earn a commission from a retailer or affiliate network without increasing your price. Not every link or purchase qualifies, and the commercial relationship does not make the retailer a sponsor of Stacks or make Stacks the retailer's agent. See the <a href="?page=affiliate">Affiliate Disclosure</a>. Users with their own material relationship to a brand or seller are responsible for making any additional legally required disclosure.</p>
      <h2>Wishlists and Collabs</h2><p>A wishlist claim is only a coordination signal. It is not a purchase, contract to purchase, payment reservation, guarantee or transfer of ownership. Collab members may view or edit shared content according to their permissions. Stack owners are responsible for granting and revoking access appropriately.</p>
      <h2>Subscriptions</h2><p>If you purchase Stacks Pro, payment and subscription management are handled through Apple's App Store under the terms and price shown before purchase. Subscriptions renew unless canceled through your Apple account. Apple's standard licensed-application terms also apply to the app where applicable.</p>
      <h2>Service availability and changes</h2><p>We may update, add, remove, suspend or discontinue features. We do not promise uninterrupted or error-free operation or permanent availability of any third-party product, link or integration. We will provide notice of material changes when required by law.</p>
      <h2>Disclaimers</h2><p>To the maximum extent permitted by law, Stacks is provided “as is” and “as available,” without implied warranties of merchantability, fitness for a particular purpose, title or non-infringement. We do not warrant user content, retailer content, external sites, product safety, quality, legality or transaction outcomes. Nothing in these Terms excludes warranties or consumer guarantees that cannot legally be excluded.</p>
      <h2>Limitation of liability</h2><p>To the maximum extent permitted by law, ${name} and its service providers will not be liable for indirect, incidental, special, consequential, exemplary or punitive damages, lost profits, lost data, or losses arising from independent retailers or external sites. Where liability may lawfully be limited, our total liability arising from Stacks will not exceed the greater of US $100 or the amount you paid ${name} for Stacks during the 12 months before the event giving rise to the claim. These limits do not apply to fraud, willful misconduct, gross negligence, death or personal injury caused by negligence, or any liability or statutory consumer right that cannot legally be limited.</p>
      <h2>Your responsibility for claims</h2><p>To the extent permitted by law, if your unlawful content, misuse of Stacks, or violation of another person's rights causes a third-party claim against ${name}, you agree to reimburse reasonable losses and costs resulting from that claim. This does not apply to losses caused by ${name}, and it does not reduce rights that applicable consumer law gives you.</p>
      <h2>Disputes and applicable rights</h2><p>Contact <a href="mailto:${email}">${email}</a> first so we can try to resolve a concern. These Terms do not require arbitration, waive class-action rights, select a governing jurisdiction, or deprive you of protections that apply where you live unless a later, clearly disclosed agreement validly says otherwise.</p>
      <h2>Changes and severability</h2><p>We may update these Terms. For material changes, we will provide notice and request renewed acceptance where required. If part of these Terms is unenforceable, the remaining provisions continue to the extent permitted by law. A failure to enforce a provision is not a waiver.</p>
      <h2>Contact</h2><p>Questions, legal notices, content complaints and intellectual-property reports may be sent to <a href="mailto:${email}">${email}</a>.</p>`,
    },
    security: {
      title: "Security at Stacks",
      body: `<p>Stacks uses authenticated access controls for private data, transport encryption, and time-limited links for private product media. Public and link-only Stacks are intentionally viewable by others according to their sharing settings.</p>
      <p>Keep your sign-in email secure. Treat link-only Stack URLs as private invitations; anyone with the link may be able to view the Stack until it is changed or removed.</p>
      <p>To report a security concern, email <a href="mailto:${email}">${email}</a> with enough detail for us to investigate. Please do not include passwords or sensitive personal data in your first message.</p>`,
    },
    support: {
      title: "Stacks Support",
      body: `<p>Need help with your account, a shared Stack, a wishlist claim, or a report? Email <a href="mailto:${email}">${email}</a>.</p><p>You can report or block public content from the Discover feed in the app. You can request account deletion in Profile settings.</p>`,
    },
    affiliate: {
      title: "Affiliate Disclosure",
      body: `<p class="effective">Effective September 20, 2026</p><p>Some product links in Stacks are advertising links. If you buy through a qualifying link, ${name} may earn a commission from the retailer or an affiliate network. Your price is unchanged.</p>
      <h2>How we label commissionable links</h2><p>Before a commissionable Buy link, Stacks displays: <strong>“Ad · If you buy through this link, Stacks earns a commission. Your price is unchanged.”</strong> We place this disclosure with the action so you can see it before deciding to visit the retailer. A generic “affiliate link” label is not used as a substitute for that explanation.</p>
      <h2>When Stacks does not earn a commission</h2><p>Not every retailer, product, country or purchase is eligible. If our server cannot confirm an eligible affiliate destination for the visitor’s region, Stacks uses the original product link and does not say that the link earns a commission. A commission is never guaranteed.</p>
      <h2>Independent retailers</h2><p>Retailers and affiliate networks are independent third parties. A link does not mean Stacks manufactures, sells, endorses or guarantees the product. Prices, availability, shipping, returns, warranties and retailer terms are controlled by the retailer. Product information may change, so verify it with the retailer before buying.</p>
      <h2>User-created content</h2><p>Users can save and share their own products and opinions. Unless separately and clearly disclosed, users are not paid by Stacks merely for adding an item. If a user has another material relationship with a brand or seller, they are responsible for making any additional legally required disclosure in their content.</p>
      <h2>Privacy</h2><p>Our server may provide a destination product URL and two-letter country code to an affiliate-link provider to check eligibility. We do not send your Stacks account ID, name, email address or app advertising identifier in that check. The external site may process information under its own policy after you click. Read our <a href="?page=privacy">Privacy Policy</a> for more detail.</p>
      <h2>Questions</h2><p>Questions about a link or this disclosure may be sent to <a href="mailto:${email}">${email}</a>.</p>`,
    },
    "privacy-choices": {
      title: "Privacy Choices",
      body: `<p class="effective">Effective September 20, 2026</p><p>You can edit your profile and Stacks, control Stack visibility, leave a Collab, block or report an account, and delete your account using controls in the Stacks app.</p>
      <h2>Access, correction and portability</h2><p>To request access to, correction of, or a portable copy of eligible personal information, email <a href="mailto:${email}">${email}</a> from the address associated with your account. Tell us the request and your country or region. We may verify your identity before responding.</p>
      <h2>Deletion</h2><p>You can start account deletion from Profile settings in the app. For help, email <a href="mailto:${email}">${email}</a>. Some limited records may be retained where permitted for security, fraud prevention, backups, disputes or legal obligations.</p>
      <h2>Consent, objection and appeals</h2><p>Where applicable, you may withdraw consent, object to or restrict certain processing, or appeal our response to a privacy request. You may also contact your local privacy or data-protection authority. Email <a href="mailto:${email}">${email}</a> to exercise these choices.</p>
      <h2>Sales, sharing and targeted advertising</h2><p>Stacks does not currently sell personal information or use app data for cross-context behavioral or targeted advertising. If that changes, we will update our notices and provide any legally required opt-out controls before the change takes effect.</p>`,
    },
  };
  const selected = sections[page];
  if (!selected) return new Response("Not found", { status: 404 });
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${selected.title} · Stacks</title><style>body{font:16px/1.6 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;color:#171717;background:#fff;margin:0}main{max-width:720px;margin:auto;padding:32px 22px 80px}h1{font-size:clamp(38px,8vw,64px);letter-spacing:-.05em;line-height:1.05;margin-bottom:10px}h2{font-size:21px;margin-top:30px}a{color:#171717}.effective{color:#666;font-size:14px;margin-top:0}nav{display:flex;gap:16px;flex-wrap:wrap;font-size:13px;padding:20px 0;border-bottom:1px solid #ddd}</style></head><body><main><nav><strong>Stacks</strong><a href="?page=privacy">Privacy</a><a href="?page=terms">Terms</a><a href="?page=affiliate">Affiliate disclosure</a><a href="?page=privacy-choices">Privacy choices</a><a href="?page=security">Security</a><a href="?page=support">Support</a></nav><h1>${selected.title}</h1>${selected.body}</main></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}
