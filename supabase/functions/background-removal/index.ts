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
  const imageURL = String(body.imageURL ?? "").trim();

  if (!imageURL.startsWith("http")) {
    return jsonResponse({ error: "imageURL is required" }, 400);
  }

  // Apple Vision runs on-device for the iOS V1 path. A server-side fallback is
  // intentionally unavailable until an image-removal provider is configured;
  // returning a successful original URL here would make the UI falsely claim
  // that removal completed.
  return jsonResponse({
    status: "failed",
    imageURL,
    error: "server-side background removal is not configured",
  }, 503);
});
