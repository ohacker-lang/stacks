export type VerifiedPrice = {
  price: number;
  currencyCode: string;
  canonicalURL: string;
};

export class PriceVerificationError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
  }
}

export function isAmazonURL(value: string): boolean {
  try {
    const host = new URL(value).hostname.toLowerCase().replace(/^www\./, "");
    return host === "amzn.to" || host === "amazon.com" || host.endsWith(".amazon.com") ||
      /^amazon\.[a-z.]+$/.test(host) || /^smile\.amazon\.[a-z.]+$/.test(host);
  } catch {
    return false;
  }
}

export async function verifyProductPrice(rawURL: string): Promise<VerifiedPrice> {
  const url = safeURL(rawURL);
  if (isAmazonURL(url.toString())) {
    throw new PriceVerificationError("amazon_unsupported", "Amazon products are not eligible for price alerts.");
  }

  const response = await fetch(url, {
    redirect: "follow",
    signal: AbortSignal.timeout(15_000),
    headers: {
      "Accept": "text/html,application/xhtml+xml",
      "Accept-Language": "en-US,en;q=0.9",
      "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1",
    },
  });
  if (isAmazonURL(response.url)) {
    throw new PriceVerificationError("amazon_unsupported", "Amazon products are not eligible for price alerts.");
  }
  if (response.status === 403 || response.status === 429) {
    throw new PriceVerificationError("retailer_blocked", "This retailer blocks automatic price checks.");
  }
  if (!response.ok) throw new PriceVerificationError("unavailable", `The retailer returned ${response.status}.`);
  const html = await response.text();
  if (/captcha|cf-chl-|dduser-challenge|access denied|just a moment/i.test(html.slice(0, 20_000))) {
    throw new PriceVerificationError("retailer_blocked", "This retailer requires browser verification.");
  }

  const jsonLD = jsonLDValues(html);
  const offer = firstOffer(jsonLD);
  const meta = metadata(html);
  const rawPrice = scalar(offer?.price) ?? scalar(offer?.lowPrice) ??
    meta["product:price:amount"] ?? meta["og:price:amount"] ?? meta["twitter:data1"];
  const price = parsePrice(rawPrice);
  if (price === null || price <= 0) {
    throw new PriceVerificationError("price_unavailable", "A verified current price is not available for this product.");
  }
  const currency = (scalar(offer?.priceCurrency) ?? meta["product:price:currency"] ??
    meta["og:price:currency"] ?? currencyFrom(rawPrice) ?? "USD").toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) {
    throw new PriceVerificationError("currency_unavailable", "The retailer did not provide a valid currency.");
  }
  return { price, currencyCode: currency, canonicalURL: response.url || url.toString() };
}

function safeURL(value: string): URL {
  let url: URL;
  try { url = new URL(value); } catch { throw new PriceVerificationError("invalid_url", "A valid product link is required."); }
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password) {
    throw new PriceVerificationError("invalid_url", "That product link cannot be checked.");
  }
  const host = url.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".local") || /^(127|10|192\.168)\./.test(host) ||
      /^172\.(1[6-9]|2\d|3[0-1])\./.test(host)) {
    throw new PriceVerificationError("invalid_url", "That product link cannot be checked.");
  }
  return url;
}

function metadata(html: string): Record<string, string> {
  const values: Record<string, string> = {};
  for (const match of html.matchAll(/<meta\s+[^>]*>/gi)) {
    const tag = match[0];
    const key = attribute(tag, "property") ?? attribute(tag, "name") ?? attribute(tag, "itemprop");
    const content = attribute(tag, "content");
    if (key && content && !values[key.toLowerCase()]) values[key.toLowerCase()] = decode(content);
  }
  return values;
}

function attribute(tag: string, name: string): string | null {
  const match = tag.match(new RegExp(`${name}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`, "i"));
  return match ? (match[1] ?? match[2] ?? match[3] ?? null) : null;
}

function jsonLDValues(html: string): unknown[] {
  const values: unknown[] = [];
  for (const match of html.matchAll(/<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { values.push(JSON.parse(decode(match[1].trim()))); } catch { /* malformed merchant data */ }
  }
  return values;
}

function firstOffer(values: unknown[]): Record<string, unknown> | null {
  const queue = [...values];
  while (queue.length) {
    const value = queue.shift();
    if (Array.isArray(value)) { queue.push(...value); continue; }
    if (!value || typeof value !== "object") continue;
    const object = value as Record<string, unknown>;
    const type = String(object["@type"] ?? "").toLowerCase();
    if (type.includes("offer") && (object.price != null || object.lowPrice != null)) return object;
    if (object.offers) queue.unshift(object.offers);
    if (object["@graph"]) queue.push(object["@graph"]);
  }
  return null;
}

function scalar(value: unknown): string | null {
  if (typeof value === "string" || typeof value === "number") return String(value).trim();
  return null;
}

function parsePrice(value: string | null): number | null {
  if (!value) return null;
  const cleaned = value.replace(/[^0-9.,-]/g, "");
  const normalized = cleaned.includes(",") && !cleaned.includes(".")
    ? cleaned.replace(",", ".") : cleaned.replace(/,/g, "");
  const result = Number(normalized);
  return Number.isFinite(result) ? Math.round(result * 100) / 100 : null;
}

function currencyFrom(value: string | null): string | null {
  if (!value) return null;
  if (/€/.test(value)) return "EUR";
  if (/£/.test(value)) return "GBP";
  if (/\bCAD\b/i.test(value)) return "CAD";
  if (/\bAUD\b/i.test(value)) return "AUD";
  if (/\bUSD\b|\$/.test(value)) return "USD";
  return null;
}

function decode(value: string): string {
  return value.replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">");
}
