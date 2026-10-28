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
  let destination: URL;
  try {
    destination = new URL(rawURL);
  } catch {
    return jsonResponse({ error: "valid url is required" }, 400);
  }
  if (!["http:", "https:"].includes(destination.protocol) ||
      !destination.hostname.includes(".") ||
      /^(localhost|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|::1$)/i.test(destination.hostname)) {
    return jsonResponse({ error: "public http(s) url is required" }, 400);
  }

  const fallback = { affiliateURL: destination.href, isCommissionable: false };
  const key = Deno.env.get("SOVRN_COMMERCE_API_KEY");
  if (!key) return jsonResponse(fallback);

  const countryCode = String(body.countryCode ?? "").trim().toUpperCase();
  const enabledCountries = new Set((Deno.env.get("SOVRN_ENABLED_COUNTRIES") ?? "")
    .split(",").map((value) => value.trim().toUpperCase()).filter(Boolean));
  // Monetization is opt-in per tested country. App availability is worldwide,
  // but an untested or unidentified viewer receives the ordinary retailer URL.
  if (!/^[A-Z]{2}$/.test(countryCode) || !enabledCountries.has(countryCode)) {
    return jsonResponse(fallback);
  }
  const checkURL = new URL("https://api.viglink.com/api/link/");
  checkURL.searchParams.set("out", destination.href);
  checkURL.searchParams.set("key", key);
  checkURL.searchParams.set("format", "json");
  checkURL.searchParams.set("geo", countryCode);

  try {
    const response = await fetch(checkURL, { signal: AbortSignal.timeout(5_000) });
    if (!response.ok) return jsonResponse(fallback);
    const result = await response.json() as { affiliatable?: boolean; optimized?: string };
    if (!result.affiliatable || !result.optimized) return jsonResponse(fallback);
    const affiliateURL = new URL(result.optimized);
    if (affiliateURL.protocol !== "https:" || affiliateURL.href === destination.href) {
      return jsonResponse(fallback);
    }
    return jsonResponse({ affiliateURL: affiliateURL.href, isCommissionable: true });
  } catch (error) {
    console.error("affiliate-link check failed", error);
    return jsonResponse(fallback);
  }
});
