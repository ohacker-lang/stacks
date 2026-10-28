import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, requiredEnv, serviceClient } from "../_shared/supabase.ts";

const entitlementID = "stacks_pro";
const products = new Set(["stacks.pro.monthly", "stacks.pro.annual"]);

type RevenueCatSubscriber = {
  subscriber?: {
    entitlements?: Record<string, { expires_date?: string | null; product_identifier?: string }>;
  };
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;

    const response = await fetch(
      `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(context.user.id)}`,
      {
        headers: {
          Authorization: `Bearer ${requiredEnv("REVENUECAT_SECRET_API_KEY")}`,
          Accept: "application/json",
        },
      },
    );
    if (!response.ok) throw new Error(`RevenueCat subscriber lookup failed (${response.status}).`);

    const payload = await response.json() as RevenueCatSubscriber;
    const entitlement = payload.subscriber?.entitlements?.[entitlementID];
    const productID = entitlement?.product_identifier ?? "";
    const expiresAt = entitlement?.expires_date ? new Date(entitlement.expires_date) : null;
    const isPro = products.has(productID) && expiresAt != null && expiresAt.getTime() > Date.now();
    const admin = serviceClient();

    if (products.has(productID) && expiresAt != null) {
      const { error } = await admin.from("pro_entitlements").upsert({
        user_id: context.user.id,
        original_transaction_id: null,
        provider: "revenuecat",
        provider_customer_id: context.user.id,
        product_id: productID,
        expires_at: expiresAt.toISOString(),
        revoked_at: isPro ? null : new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: "user_id" });
      if (error) throw error;
    } else {
      const { error } = await admin.from("pro_entitlements").delete().eq("user_id", context.user.id);
      if (error) throw error;
    }

    return jsonResponse({ isPro, expiresAt: expiresAt?.toISOString() ?? null });
  } catch (error) {
    console.error("sync-pro-entitlement", error);
    return jsonResponse({ error: "Unable to verify your Stacks Pro subscription right now." }, 503);
  }
});
