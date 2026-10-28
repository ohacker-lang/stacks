import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, serviceClient } from "../_shared/supabase.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;
    const body = await readJson(req);
    const token = String(body.deviceToken ?? "").trim().toLowerCase();
    const environment = body.environment === "sandbox" ? "sandbox" : "production";
    if (!/^[0-9a-f]{64,256}$/.test(token)) return jsonResponse({ error: "Invalid device token." }, 400);

    const admin = serviceClient();
    const { error } = await admin.from("push_device_tokens").upsert({
      token,
      user_id: context.user.id,
      platform: "ios",
      environment,
      enabled: true,
      last_registered_at: new Date().toISOString(),
    }, { onConflict: "token" });
    if (error) throw error;
    return jsonResponse({});
  } catch (error) {
    console.error("register-push-token", error);
    return jsonResponse({ error: "Unable to register this device for notifications." }, 500);
  }
});
