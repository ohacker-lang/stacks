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
  const title = String(body.title ?? "This find").trim();
  const brand = String(body.brand ?? "Stacks").trim();

  // Replace with your preferred AI provider. Keep the output short and editorial.
  return jsonResponse({
    description: `${title} by ${brand}, selected for the kind of visual charm that makes a Stack feel personal.`,
  });
});
