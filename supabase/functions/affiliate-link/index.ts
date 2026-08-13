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
  const url = String(body.url ?? "").trim();

  if (!url.startsWith("http")) {
    return jsonResponse({ error: "valid url is required" }, 400);
  }

  // Until Sovrn Commerce credentials are configured, preserve the original
  // destination rather than routing people through a placeholder domain.
  return jsonResponse({
    affiliateURL: url,
    isCommissionable: false,
  });
});
