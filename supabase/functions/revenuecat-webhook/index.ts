import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { jsonResponse } from "../_shared/http.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";

const products = new Set(["stacks.pro.monthly", "stacks.pro.annual"]);
const userIDPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type RevenueCatEvent = {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  transferred_from?: string[];
  transferred_to?: string[];
};

type RevenueCatSubscriber = {
  subscriber?: {
    entitlements?: Record<string, { expires_date?: string | null; product_identifier?: string }>;
  };
};

async function syncCustomer(userID: string, admin: ReturnType<typeof serviceClient>): Promise<void> {
  // Fetch current state instead of trusting the event snapshot: webhooks can
  // arrive out of order, and TRANSFER events have different purchase fields.
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userID)}`,
    {
      headers: {
        Authorization: `Bearer ${requiredEnv("REVENUECAT_SECRET_API_KEY")}`,
        Accept: "application/json",
      },
    },
  );
  if (!response.ok) throw new Error(`RevenueCat subscriber lookup failed (${response.status}).`);
  const payload = await response.json() as RevenueCatSubscriber;
  const entitlement = payload.subscriber?.entitlements?.stacks_pro;
  const productID = entitlement?.product_identifier ?? "";
  const expiresAt = entitlement?.expires_date ? new Date(entitlement.expires_date) : null;
  const isPro = products.has(productID) && expiresAt != null && expiresAt.getTime() > Date.now();

  if (isPro) {
    const { error } = await admin.from("pro_entitlements").upsert({
      user_id: userID,
      original_transaction_id: null,
      provider: "revenuecat",
      provider_customer_id: userID,
      product_id: productID,
      expires_at: expiresAt!.toISOString(),
      revoked_at: null,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id" });
    if (error) throw error;
  } else {
    const { error } = await admin.from("pro_entitlements").delete().eq("user_id", userID);
    if (error) throw error;
  }
}

serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  const expected = requiredEnv("REVENUECAT_WEBHOOK_AUTHORIZATION");
  if (req.headers.get("authorization") !== expected) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  try {
    const body = await req.json() as { event?: RevenueCatEvent };
    const event = body.event;
    if (!event?.id || !event.type) return jsonResponse({ error: "Invalid event." }, 400);

    const admin = serviceClient();
    const { data: processedEvent, error: lookupError } = await admin
      .from("revenuecat_webhook_events").select("id").eq("id", event.id).maybeSingle();
    if (lookupError) throw lookupError;
    if (processedEvent) return jsonResponse({ ok: true, duplicate: true });

    const candidateIDs = event.type === "TRANSFER"
      ? [...(event.transferred_from ?? []), ...(event.transferred_to ?? [])]
      : [event.app_user_id, event.original_app_user_id, ...(event.aliases ?? [])];
    const validIDs = candidateIDs
      .filter((value): value is string => Boolean(value))
      .filter((value) => userIDPattern.test(value));
    const userIDs = event.type === "TRANSFER" ? validIDs : validIDs.slice(0, 1);
    if (userIDs.length === 0) return jsonResponse({ ok: true, ignored: "No Stacks user ID." });
    for (const userID of new Set(userIDs)) {
      await syncCustomer(userID, admin);
    }

    // Record the event only after its entitlement update succeeds. RevenueCat
    // retries failed deliveries, so recording first would lose a grant forever.
    const { error: eventError } = await admin.from("revenuecat_webhook_events").insert({
      id: event.id,
      event_type: event.type,
    });
    if (eventError && eventError.code !== "23505") throw eventError;
    return jsonResponse({ ok: true });
  } catch (error) {
    console.error("revenuecat-webhook", error);
    return jsonResponse({ error: "Webhook processing failed." }, 500);
  }
});
