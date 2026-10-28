import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, isUUID } from "../_shared/supabase.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;

    const body = await readJson(req);
    const token = String(body.token ?? "").trim();
    if (!isUUID(token)) return jsonResponse({ error: "This invitation is invalid." }, 400);

    const { data, error } = await context.client.rpc("accept_collaboration_invite", { invite_token: token });
    if (error) {
      const status = error.code === "P0002" ? 404 : 400;
      return jsonResponse({ error: error.message || "This invitation is unavailable." }, status);
    }
    const result = Array.isArray(data) ? data[0] : data;
    if (!result?.stack_id) return jsonResponse({ error: "The invitation could not be completed." }, 500);
    return jsonResponse({ accepted: true, stackID: result.stack_id });
  } catch (error) {
    console.error("accept-collaboration-invite", error);
    return jsonResponse({ error: "Unable to accept this invite. Please try again." }, 500);
  }
});
