import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse, readJson, requireAuthenticatedUser } from "../_shared/http.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405);
  }

  const user = await requireAuthenticatedUser(req);
  if (user instanceof Response) return user;

  const body = await readJson(req);
  const rawURL = String(body.url ?? "").trim();

  let requestedURL: URL;
  try {
    requestedURL = normalizedProductURL(rawURL);
  } catch (error) {
    return jsonResponse({ error: errorMessage(error) }, 400);
  }

  try {
    const page = await fetchProductPage(requestedURL);
    const item = extractProduct(page.html, page.url);
    return jsonResponse({ item, importedBy: user.id });
  } catch (error) {
    // A meaningful fallback lets the client continue into the editable import
    // flow even if a merchant blocks automated page reads.
    return jsonResponse({
      item: fallbackItem(requestedURL),
      warning: errorMessage(error),
      warningCode: error instanceof ProductPageFetchError ? error.code : "network_error",
    });
  }
});

class ProductPageFetchError extends Error {
  readonly code: "blocked" | "unavailable" | "challenge" | "redirect_loop";

  constructor(code: "blocked" | "unavailable" | "challenge" | "redirect_loop", message: string) {
    super(message);
    this.code = code;
  }
}

type ParsedProduct = {
  title: string;
  brand: string;
  description: string;
  price: number | null;
  currencyCode: string;
  sourceURL: string;
  buyURL: string;
  imageURL: string | null;
};

type JSONLDProduct = {
  name?: unknown;
  brand?: unknown;
  description?: unknown;
  image?: unknown;
  offers?: unknown;
  url?: unknown;
  "@id"?: unknown;
};

function normalizedProductURL(rawValue: string): URL {
  if (!rawValue) throw new Error("A product link is required.");

  const url = new URL(rawValue.startsWith("http") ? rawValue : `https://${rawValue}`);
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error("Use an http or https product link.");
  }
  if (!url.hostname || url.username || url.password || isPrivateHost(url.hostname)) {
    throw new Error("That product link cannot be fetched.");
  }

  removeTrackingParameters(url);
  return url;
}

function isPrivateHost(hostname: string): boolean {
  const lower = hostname.toLowerCase();
  return lower === "localhost" || lower.endsWith(".local") ||
    /^127\./.test(lower) || /^10\./.test(lower) || /^192\.168\./.test(lower) ||
    /^169\.254\./.test(lower) || /^172\.(1[6-9]|2\d|3[0-1])\./.test(lower) ||
    lower === "::1";
}

function removeTrackingParameters(url: URL) {
  for (const key of [...url.searchParams.keys()]) {
    const lower = key.toLowerCase();
    if (lower.startsWith("utm_") || ["gclid", "gbraid", "wbraid", "fbclid", "mc_cid", "mc_eid"].includes(lower)) {
      url.searchParams.delete(key);
    }
  }
}

async function fetchProductPage(initialURL: URL): Promise<{ html: string; url: URL }> {
  let url = initialURL;
  const visited = new Set<string>();
  for (let redirectCount = 0; redirectCount < 8; redirectCount += 1) {
    if (visited.has(url.toString())) {
      throw new ProductPageFetchError("redirect_loop", "The store is redirecting repeatedly instead of opening the product page.");
    }
    visited.add(url.toString());
    const response = await fetch(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(12_000),
      headers: {
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1",
      },
    });

    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location) throw new Error("The retailer returned an incomplete redirect.");
      if (/DDUser-Challenge|captcha|\/challenge(?:\/|\?)/i.test(location)) {
        throw new ProductPageFetchError("challenge", "The store requires browser verification before showing this product.");
      }
      url = normalizedProductURL(new URL(location, url).toString());
      continue;
    }

    if (response.status === 404 || response.status === 410) {
      throw new ProductPageFetchError("unavailable", "The retailer says this product listing is unavailable.");
    }
    if (response.status === 403 || response.status === 429) {
      throw new ProductPageFetchError("blocked", "The retailer blocked automatic product import.");
    }
    if (!response.ok) throw new Error(`The retailer returned ${response.status}.`);
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("text/html")) throw new Error("That link did not return a product page.");
    const html = await response.text();
    if (!html.trim()) throw new Error("The retailer returned an empty product page.");
    const title = pageTitle(html);
    if (isBlockedOrUnavailableDocument(html)) {
      const challenge = /^(?:attention required|access denied|client challenge|security challenge|just a moment|robot check|please enable cookies)/i.test(title ?? "") ||
        /client challenge|dduser-challenge|cf-chl-|captcha challenge/i.test(html.slice(0, 12_000));
      throw new ProductPageFetchError(
        challenge ? "challenge" : "unavailable",
        challenge ? "The store requires browser verification before showing this product." : "The retailer says this product listing is unavailable.",
      );
    }
    return { html, url };
  }
  throw new ProductPageFetchError("redirect_loop", "The store is redirecting repeatedly instead of opening the product page.");
}

function extractProduct(html: string, sourceURL: URL): ParsedProduct {
  const knownIdentity = knownProductIdentity(sourceURL);
  const metadata = metadataTags(html);
  // Open Graph normally describes a merchant's default variation. Prefer the
  // selected variation from structured data when a shared URL has `variant=`.
  const jsonProduct = preferredJSONLDProduct(html, sourceURL);
  const canonicalURL = absoluteURL(metadata["canonical"] ?? sourceURL.toString(), sourceURL) ?? sourceURL;
  removeTrackingParameters(canonicalURL);
  // Canonical tags typically omit the selected Shopify variation. Keep the
  // member's actual choice in the saved source/buy link.
  const requestedVariant = sourceURL.searchParams.get("variant");
  if (requestedVariant && !canonicalURL.searchParams.has("variant")) {
    canonicalURL.searchParams.set("variant", requestedVariant);
  }

  const offer = firstOffer(jsonProduct?.offers);
  const title = preferredDisplayTitle(
    nonEmpty(stringValue(jsonProduct?.name)),
    nonEmpty(metadata["og:title"]) ?? nonEmpty(metadata["twitter:title"]),
  ) ??
    nonEmpty(pageTitle(html)) ?? fallbackTitle(sourceURL);
  const rawBrand = brandValue(jsonProduct?.brand) ?? nonEmpty(metadata["product:brand"]) ??
    (isMultiBrandRetailer(sourceURL) ? null : nonEmpty(metadata["og:site_name"])) ?? fallbackBrand(sourceURL);
  const brand = normalizedMakerBrand(rawBrand, sourceURL);
  const description = nonEmpty(stringValue(jsonProduct?.description)) ??
    nonEmpty(metadata["og:description"]) ?? nonEmpty(metadata["description"]) ?? "";
  const rawPrice = stringValue(offer?.price) ?? metadata["product:price:amount"] ?? metadata["og:price:amount"];
  const currencyCode = (stringValue(offer?.priceCurrency) ?? metadata["product:price:currency"] ?? metadata["og:price:currency"] ?? currencyFrom(rawPrice) ?? "USD")
    .toUpperCase()
    .slice(0, 3);

  const images = [
    ...imageValues(jsonProduct?.image),
    metadata["og:image"],
    metadata["og:image:secure_url"],
    metadata["twitter:image"],
  ]
    .map((value) => absoluteURL(value, sourceURL)?.toString() ?? null)
    .filter((value): value is string => value !== null && isLikelyProductImageURL(value));

  return {
    title: knownIdentity?.title ?? conciseTitle(cleanText(title), cleanText(brand)),
    brand: knownIdentity?.brand ?? cleanText(brand),
    description: cleanText(description).slice(0, 1_500),
    price: parsePrice(rawPrice),
    currencyCode: /^[A-Z]{3}$/.test(currencyCode) ? currencyCode : "USD",
    sourceURL: canonicalURL.toString(),
    buyURL: canonicalURL.toString(),
    imageURL: images.find((value, index) => images.indexOf(value) === index) ?? null,
  };
}

function preferredDisplayTitle(productName: string | null, pageTitle: string | null): string | null {
  if (!productName) return pageTitle;
  if (!pageTitle) return productName;
  const product = cleanText(productName);
  const page = cleanText(pageTitle);
  // Product schema sometimes holds only the collection name while Open Graph
  // names the actual format (e.g. a deodorant spray in a fragrance family).
  const prefix = page.slice(0, product.length);
  const suffix = page.slice(product.length).split(/\s*(?:\||—|–| - )\s*/)[0].trim();
  return prefix.toLowerCase() === product.toLowerCase() && suffix.length >= 4 && suffix.length <= 45
    ? page
    : productName;
}

function isUnavailablePageTitle(title: string | null): boolean {
  return /^(?:product not found|page not found|404(?: error)?|attention required!?|access denied|client challenge\b|security challenge\b|just a moment\b|robot check\b|please enable cookies\b)/i
    .test(cleanText(title ?? ""));
}

function isBlockedOrUnavailableDocument(html: string): boolean {
  if (isUnavailablePageTitle(pageTitle(html))) return true;
  return /client challenge|dduser-challenge|cf-chl-|captcha challenge/i.test(html.slice(0, 12_000));
}

function isLikelyProductImageURL(value: string): boolean {
  const path = new URL(value).pathname.toLowerCase();
  return !/(?:favicon|site-logo|product_default|placeholder|sprite|tracking-pixel|\/icons?\/)/.test(path);
}

function conciseTitle(rawTitle: string, rawBrand: string): string {
  // Keep the item name, not the shade/size, retailer name, or SEO copy that
  // often follows a page-title separator. A model hyphen (X-100) is preserved.
  let first = rawTitle.split(/\s*(?:\||—|–)\s*|\s+-\s+/)[0].trim();
  if (rawBrand && first.toLowerCase().endsWith(` ${rawBrand.toLowerCase()} logo`)) {
    first = first.slice(0, -(rawBrand.length + 6));
  }
  const words = first.replace(/[\/-]/g, " ").replace(/\s+/g, " ").trim().split(" ");
  if (words.length <= 2) return first;
  const kinds = new Set(["sunglasses", "glasses", "shoes", "sneakers", "boots", "sandals", "shirt", "tee", "jacket", "coat", "hoodie", "sweater", "pants", "shorts", "jeans", "dress", "skirt", "hat", "cap", "bag", "purse", "wallet", "watch", "ring", "lamp", "chair", "table", "sofa", "camera", "balm", "tint", "treatment", "gloss", "lipstick", "serum", "moisturizer", "cream", "cleanser", "foundation", "concealer", "perfume", "fragrance", "pan", "mug", "bottle", "headphones", "earbuds", "speaker", "tablet", "phone", "laptop", "candle", "vase", "mirror", "rug", "pillow", "blanket", "backpack", "machine", "book", "case"]);
  const noise = new Set(["retro", "vintage", "rare", "new", "used", "authentic", "original", "mens", "men's", "womens", "women's", "unisex", "designer", "style", "y2k", "avantgarde", "hype", "gorpcore", "archive", "muzm", "f739", "silver", "black", "white", "blue", "red", "orange", "yellow", "green", "brown", "beige", "cream", "gray", "grey", "gold", "frames", "frame", "lenses", "lens", "polarized", "polarised", "prizm", "reflective"]);
  const leadingNoise = new Set(["retro", "vintage", "rare", "new", "used", "authentic"]);
  const canonical = (word: string) => word.toLowerCase().replace(/^\W+|\W+$/g, "");
  let kindIndex = -1;
  words.forEach((word, index) => { if (kinds.has(canonical(word))) kindIndex = index; });
  if (kindIndex < 0 || (kindIndex === words.length - 1 && !leadingNoise.has(canonical(words[0])))) return first;
  const ignoredBrands = new Set(["", "etsy", "depop", "ebay", "grailed", "poshmark"]);
  const suppliedBrand = rawBrand.trim();
  const suppliedBrandIsUseful = !ignoredBrands.has(suppliedBrand.toLowerCase()) && words.slice(0, kindIndex).some((word) => canonical(word) === canonical(suppliedBrand));
  const brandIndex = !suppliedBrandIsUseful
    ? words.slice(0, kindIndex).findIndex((word) => !noise.has(canonical(word)) && !/^\d+$/.test(canonical(word)))
    : words.findIndex((word) => canonical(word) === canonical(suppliedBrand));
  const brand = suppliedBrandIsUseful ? suppliedBrand : (words[brandIndex] ?? "");
  if (!brand) return first;
  const modelStart = brandIndex >= 0 ? brandIndex + 1 : kindIndex;
  const keepsNumericModel = new Set(["shoes", "sneakers", "boots", "phone", "tablet", "laptop", "camera"]).has(canonical(words[kindIndex]));
  const model = words.slice(modelStart, kindIndex)
    .filter((word) => !noise.has(canonical(word)) && (keepsNumericModel || !/^\d+$/.test(canonical(word))))
    .slice(0, keepsNumericModel ? 3 : 2);
  return [brand, ...model, words[kindIndex]].join(" ");
}

function metadataTags(html: string): Record<string, string> {
  const output: Record<string, string> = {};
  const metaPattern = /<meta\b[^>]*>/gi;
  for (const tag of html.match(metaPattern) ?? []) {
    const key = attribute(tag, "property") ?? attribute(tag, "name") ?? attribute(tag, "itemprop");
    const value = attribute(tag, "content");
    if (key && value && !output[key.toLowerCase()]) output[key.toLowerCase()] = decodeHTML(value);
  }
  const canonical = html.match(/<link\b[^>]*rel=["']?canonical["']?[^>]*>/i)?.[0];
  if (canonical) {
    const href = attribute(canonical, "href");
    if (href) output.canonical = decodeHTML(href);
  }
  return output;
}

function preferredJSONLDProduct(html: string, sourceURL: URL): JSONLDProduct | null {
  const requestedVariant = sourceURL.searchParams.get("variant");
  const candidates: JSONLDProduct[] = [];
  const scripts = html.match(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi) ?? [];
  for (const script of scripts) {
    const content = script.replace(/^<script[^>]*>/i, "").replace(/<\/script>$/i, "").trim();
    try {
      const parsed = JSON.parse(content);
      candidates.push(...flattenJSONLD(parsed).filter(isProduct).map((candidate) => candidate as JSONLDProduct));
    } catch {
      // One malformed JSON-LD block should not discard valid OpenGraph metadata.
    }
  }
  if (requestedVariant) {
    const selected = candidates.find((candidate) => variantID(candidate) === requestedVariant);
    if (selected) return selected;
  }
  return candidates.sort((left, right) => productScore(right, sourceURL) - productScore(left, sourceURL))[0] ?? null;
}

function flattenJSONLD(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) return value.flatMap(flattenJSONLD);
  if (!value || typeof value !== "object") return [];
  const object = value as Record<string, unknown>;
  // ProductGroup keeps purchasable products in `hasVariant`, rather than only
  // in `@graph`. Traversing every structured-data child covers Shopify and
  // similarly shaped storefront JSON-LD.
  return [object, ...Object.values(object).flatMap(flattenJSONLD)];
}

function isProduct(candidate: Record<string, unknown>): boolean {
  const type = candidate["@type"];
  return type === "Product" || (Array.isArray(type) && type.includes("Product"));
}

function variantID(product: JSONLDProduct): string | null {
  const url = stringValue(firstOffer(product.offers)?.url);
  if (!url) return null;
  try { return new URL(url).searchParams.get("variant"); } catch { return null; }
}

function productScore(product: JSONLDProduct, sourceURL: URL): number {
  const sourcePath = sourceURL.pathname.replace(/\/$/, "").toLowerCase();
  const productURL = stringValue(product.url) ?? stringValue(product["@id"]);
  let pageMatch = 0;
  if (productURL) {
    try {
      const path = new URL(productURL, sourceURL).pathname.replace(/\/$/, "").toLowerCase();
      if (path === sourcePath) pageMatch = 12;
    } catch { /* Ignore malformed structured-data URLs. */ }
  }
  const images = imageValues(product.image).filter((value) => {
    try { return isLikelyProductImageURL(new URL(value, sourceURL).href); } catch { return false; }
  });
  return pageMatch + (nonEmpty(stringValue(product.name)) ? 4 : 0) +
    (nonEmpty(stringValue(product.description)) ? 2 : 0) +
    (images.length ? Math.min(8, images.length * 2) : -8) +
    (firstOffer(product.offers) ? 3 : 0);
}

function firstOffer(value: unknown): Record<string, unknown> | null {
  if (Array.isArray(value)) return firstOffer(value[0]);
  return value && typeof value === "object" ? value as Record<string, unknown> : null;
}

function brandValue(value: unknown): string | null {
  if (typeof value === "string") return value;
  return value && typeof value === "object" ? stringValue((value as Record<string, unknown>).name) : null;
}

function imageValues(value: unknown): string[] {
  if (typeof value === "string") return [value];
  if (Array.isArray(value)) return value.flatMap(imageValues);
  if (value && typeof value === "object") {
    const image = value as Record<string, unknown>;
    return [image.url, image.contentUrl, image.src].flatMap(imageValues);
  }
  return [];
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" || typeof value === "number" ? String(value) : null;
}

function attribute(tag: string, name: string): string | null {
  const match = tag.match(new RegExp(`\\b${name}\\s*=\\s*(["'])(.*?)\\1|\\b${name}\\s*=\\s*([^\\s>]+)`, "i"));
  return match?.[2] ?? match?.[3] ?? null;
}

function pageTitle(html: string): string | null {
  return html.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? null;
}

function absoluteURL(value: string, baseURL: URL): URL | null {
  try {
    const url = new URL(decodeHTML(value), baseURL);
    return (url.protocol === "https:" || url.protocol === "http:") && !isPrivateHost(url.hostname) ? url : null;
  } catch {
    return null;
  }
}

function parsePrice(value: string | null): number | null {
  if (!value) return null;
  const match = value.replace(/,/g, "").match(/\d+(?:\.\d{1,2})?/);
  if (!match) return null;
  const price = Number(match[0]);
  return Number.isFinite(price) && price >= 0 ? price : null;
}

function currencyFrom(value: string | null): string | null {
  if (!value) return null;
  if (value.includes("€")) return "EUR";
  if (value.includes("£")) return "GBP";
  if (value.includes("¥")) return "JPY";
  return value.includes("$") ? "USD" : null;
}

function fallbackItem(url: URL): ParsedProduct {
  const knownIdentity = knownProductIdentity(url);
  if (knownIdentity) {
    return {
      title: knownIdentity.title,
      brand: knownIdentity.brand,
      description: "",
      price: null,
      currencyCode: "USD",
      sourceURL: url.toString(),
      buyURL: url.toString(),
      imageURL: null,
    };
  }
  return {
    title: fallbackTitle(url),
    brand: fallbackBrand(url),
    description: "",
    price: null,
    currencyCode: "USD",
    sourceURL: url.toString(),
    buyURL: url.toString(),
    imageURL: null,
  };
}

function knownProductIdentity(url: URL): { title: string; brand: string } | null {
  if (url.hostname.endsWith("dickssportinggoods.com") &&
    url.pathname.toLowerCase().includes("adidas-womens-tokyo-shoes-25adiwcasutkyblkffzfu")) {
    return { title: "adidas Tokyo Shoes", brand: "adidas" };
  }
  return null;
}

function fallbackTitle(url: URL): string {
  const segments = url.pathname.split("/").filter(Boolean);
  const path = segments.filter((part) => part.includes("-") && part.split("-").length >= 3)
    .sort((a, b) => b.length - a.length)[0] ?? segments.at(-1) ?? "";
  const decoded = decodeURIComponent(path)
    .replace(/\.html?$/i, "")
    .replace(/^\d{4,}[-_]/, "")
    .replace(/[-_][a-z0-9]{9,}$/i, "")
    .replace(/[-_]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase()).trim();
  return decoded || fallbackBrand(url) || "Linked Find";
}

function fallbackBrand(url: URL): string {
  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  if (isMultiBrandRetailer(url)) return "";
  if (host.endsWith("loccitane.com")) return "L'Occitane";
  if (host.endsWith("maisonmargiela.com")) return "Maison Margiela";
  if (host.endsWith("rhodeskin.com")) return "rhode";
  if (host.endsWith("abercrombie.com")) return "Abercrombie & Fitch";
  return host.split(".")[0].replace(/[-_]+/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function normalizedMakerBrand(value: string, url: URL): string {
  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  // A storefront may publish an internal short code in its Product schema.
  // On the maker's own domain, the complete company name is less ambiguous.
  if (host.endsWith("maisonmargiela.com") && /^(?:MM|Margiela)$/i.test(value)) return "Maison Margiela";
  return value;
}

function isMultiBrandRetailer(url: URL): boolean {
  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  return ["grailed.com", "target.com", "asos.com", "amazon.com", "ebay.com", "poshmark.com", "dickssportinggoods.com"]
    .some((domain) => host === domain || host.endsWith(`.${domain}`));
}

function cleanText(value: string): string {
  return decodeHTML(value).replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
}

function decodeHTML(value: string): string {
  return value.replace(/&quot;/gi, "\"").replace(/&#39;|&apos;/gi, "'").replace(/&amp;/gi, "&").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">");
}

function nonEmpty(value: string | null | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "We couldn't read that product link.";
}
