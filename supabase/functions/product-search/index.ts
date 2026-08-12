import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";

type SerpApiShoppingResult = {
  title?: string;
  source?: string;
  price?: string;
  extracted_price?: number;
  link?: string;
  product_link?: string;
  thumbnail?: string;
  snippet?: string;
};

type SerpApiResponse = {
  error?: string;
  shopping_results?: SerpApiShoppingResult[];
};

const supportedCountries = new Set(["au", "ca", "gb", "us"]);

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405);
  }

  const body = await readJson(req);
  const query = String(body.query ?? "").trim();
  const country = String(body.country ?? "us").toLowerCase();
  const language = String(body.language ?? "en").toLowerCase();
  const requestedLimit = Number(body.limit ?? 12);
  const limit = Number.isFinite(requestedLimit)
    ? Math.max(1, Math.min(Math.floor(requestedLimit), 20))
    : 12;

  if (!query) {
    return jsonResponse({ error: "query is required" }, 400);
  }

  if (!supportedCountries.has(country)) {
    return jsonResponse({ error: "unsupported country" }, 400);
  }

  const apiKey = Deno.env.get("SERPAPI_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "product search is not configured" }, 503);
  }

  const searchURL = new URL("https://serpapi.com/search.json");
  searchURL.searchParams.set("engine", "google_shopping");
  searchURL.searchParams.set("q", query);
  searchURL.searchParams.set("gl", country);
  searchURL.searchParams.set("hl", language);
  searchURL.searchParams.set("num", String(limit));
  searchURL.searchParams.set("api_key", apiKey);

  try {
    const response = await fetch(searchURL, {
      headers: { Accept: "application/json" },
    });
    const payload = await response.json() as SerpApiResponse;

    if (!response.ok || payload.error) {
      console.error("SerpApi product search failed", {
        status: response.status,
        error: payload.error,
      });
      return jsonResponse({ error: "product search is temporarily unavailable" }, 502);
    }

    const currencyCode = currencyCodeFor(country);
    const results = (payload.shopping_results ?? [])
      .map((result) => normalizeResult(result, currencyCode))
      .filter((result): result is NonNullable<typeof result> => result !== null)
      .slice(0, limit);

    return jsonResponse({ results });
  } catch (error) {
    console.error("SerpApi request failed", error);
    return jsonResponse({ error: "product search is temporarily unavailable" }, 502);
  }
});

function normalizeResult(result: SerpApiShoppingResult, currencyCode: string) {
  const sourceURL = validURL(result.link) ?? validURL(result.product_link);
  const price = result.extracted_price ?? numericPrice(result.price);
  const title = result.title?.trim();

  if (!sourceURL || !title || price === null) {
    return null;
  }

  return {
    title,
    brand: result.source?.trim() ?? "",
    price,
    currencyCode,
    sourceURL,
    imageURL: validURL(result.thumbnail),
    shortDescription: result.snippet?.trim() ?? "",
  };
}

function validURL(value: string | undefined): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function numericPrice(value: string | undefined): number | null {
  if (!value) return null;
  const match = value.replace(/,/g, "").match(/\d+(?:\.\d+)?/);
  return match ? Number(match[0]) : null;
}

function currencyCodeFor(country: string): string {
  switch (country) {
    case "au": return "AUD";
    case "ca": return "CAD";
    case "gb": return "GBP";
    default: return "USD";
  }
}
