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
    });
  }
});

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
  for (let redirectCount = 0; redirectCount < 4; redirectCount += 1) {
    const response = await fetch(url, {
      redirect: "manual",
      signal: AbortSignal.timeout(12_000),
      headers: {
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": "StacksProductImport/1.0 (+https://stacks.app)",
      },
    });

    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location) throw new Error("The retailer returned an incomplete redirect.");
      url = normalizedProductURL(new URL(location, url).toString());
      continue;
    }

    if (!response.ok) throw new Error(`The retailer returned ${response.status}.`);
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("text/html")) throw new Error("That link did not return a product page.");
    const html = await response.text();
    if (!html.trim()) throw new Error("The retailer returned an empty product page.");
    return { html, url };
  }
  throw new Error("The product link redirected too many times.");
}

function extractProduct(html: string, sourceURL: URL): ParsedProduct {
  const metadata = metadataTags(html);
  const jsonProduct = preferredJSONLDProduct(html);
  const canonicalURL = absoluteURL(metadata["canonical"] ?? sourceURL.toString(), sourceURL) ?? sourceURL;
  removeTrackingParameters(canonicalURL);

  const offer = firstOffer(jsonProduct?.offers);
  const title = nonEmpty(stringValue(jsonProduct?.name)) ??
    nonEmpty(metadata["og:title"]) ?? nonEmpty(metadata["twitter:title"]) ??
    nonEmpty(pageTitle(html)) ?? fallbackTitle(sourceURL);
  const brand = brandValue(jsonProduct?.brand) ?? nonEmpty(metadata["product:brand"]) ??
    nonEmpty(metadata["og:site_name"]) ?? fallbackBrand(sourceURL);
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
    .filter((value): value is string => value !== null);

  return {
    title: cleanText(title),
    brand: cleanText(brand),
    description: cleanText(description).slice(0, 1_500),
    price: parsePrice(rawPrice),
    currencyCode: /^[A-Z]{3}$/.test(currencyCode) ? currencyCode : "USD",
    sourceURL: canonicalURL.toString(),
    buyURL: canonicalURL.toString(),
    imageURL: images.find((value, index) => images.indexOf(value) === index) ?? null,
  };
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

function preferredJSONLDProduct(html: string): JSONLDProduct | null {
  const scripts = html.match(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi) ?? [];
  for (const script of scripts) {
    const content = script.replace(/^<script[^>]*>/i, "").replace(/<\/script>$/i, "").trim();
    try {
      const parsed = JSON.parse(content);
      const candidates = flattenJSONLD(parsed);
      const product = candidates.find((candidate) => {
        const type = candidate["@type"];
        return type === "Product" || (Array.isArray(type) && type.includes("Product"));
      });
      if (product) return product as JSONLDProduct;
    } catch {
      // One malformed JSON-LD block should not discard valid OpenGraph metadata.
    }
  }
  return null;
}

function flattenJSONLD(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) return value.flatMap(flattenJSONLD);
  if (!value || typeof value !== "object") return [];
  const object = value as Record<string, unknown>;
  return [object, ...flattenJSONLD(object["@graph"])];
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
  if (value && typeof value === "object") return imageValues((value as Record<string, unknown>).url);
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

function fallbackTitle(url: URL): string {
  const path = url.pathname.split("/").filter(Boolean).pop() ?? "";
  const decoded = decodeURIComponent(path).replace(/[-_]+/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase()).trim();
  return decoded || fallbackBrand(url) || "Linked Find";
}

function fallbackBrand(url: URL): string {
  return url.hostname.replace(/^www\./, "").split(".")[0].replace(/[-_]+/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
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
