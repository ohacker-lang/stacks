import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, serviceClient } from "../_shared/supabase.ts";
import { PriceVerificationError, verifyProductPrice } from "../_shared/price.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
  const context = await authenticatedRequest(req);
  if (isResponse(context)) return context;
  const body = await readJson(req);
  const action = String(body.action ?? "list");
  const admin = serviceClient();

  try {
    await admin.rpc("reconcile_price_alert_entitlement", { target_user: context.user.id });
    if (action === "list") {
      const { data: alerts, error } = await admin.from("price_alerts")
        .select("*, stack_items!inner(title, brand, removed_background_image_path, original_image_path, buy_url, source_url)")
        .eq("user_id", context.user.id).order("created_at", { ascending: true });
      if (error) throw error;
      const { data: events, error: eventError } = await admin.from("price_alert_events")
        .select("*").eq("user_id", context.user.id).order("created_at", { ascending: false }).limit(50);
      if (eventError) throw eventError;
      const { data: preference } = await admin.from("notification_preferences")
        .select("price_alerts_enabled").eq("user_id", context.user.id).maybeSingle();
      return jsonResponse({ alerts: alerts ?? [], events: events ?? [], notificationsEnabled: preference?.price_alerts_enabled ?? true });
    }

    if (action === "set_notifications") {
      const enabled = body.enabled !== false;
      const { error } = await admin.from("notification_preferences").upsert({
        user_id: context.user.id, price_alerts_enabled: enabled, updated_at: new Date().toISOString(),
      });
      if (error) throw error;
      return jsonResponse({ enabled });
    }

    const alertID = String(body.alertID ?? "");
    if (action === "delete") {
      const { error } = await admin.from("price_alerts").delete().eq("id", alertID).eq("user_id", context.user.id);
      if (error) throw error;
      return jsonResponse({});
    }
    if (action === "set_status") {
      const status = body.paused === true ? "paused" : "active";
      const { error } = await admin.from("price_alerts").update({ status, updated_at: new Date().toISOString() })
        .eq("id", alertID).eq("user_id", context.user.id).neq("status", "pro_required");
      if (error) throw error;
      return jsonResponse({});
    }
    if (action === "mark_read") {
      const { error } = await admin.from("price_alert_events").update({ read_at: new Date().toISOString() })
        .eq("id", String(body.eventID ?? "")).eq("user_id", context.user.id);
      if (error) throw error;
      return jsonResponse({});
    }
    if (action !== "upsert") return jsonResponse({ error: "Unknown action." }, 400);

    const itemID = String(body.itemID ?? "");
    const { data: item, error: itemError } = await admin.from("stack_items")
      .select("id, stack_id, source_url, buy_url, title").eq("id", itemID).maybeSingle();
    if (itemError || !item) return jsonResponse({ error: "Product not found." }, 404);
    if (!await canViewItem(admin, context.user.id, item.stack_id, String(body.linkToken ?? ""))) {
      return jsonResponse({ error: "You cannot create an alert for this product." }, 403);
    }
    const sourceURL = String(item.buy_url ?? item.source_url ?? "");
    const verified = await verifyProductPrice(sourceURL);
    const mode = body.mode === "target" ? "target" : "any_drop";
    const target = mode === "target" ? Number(body.targetPrice) : null;
    if (mode === "target" && (!Number.isFinite(target) || Number(target) <= 0)) {
      return jsonResponse({ error: "Enter a target price greater than zero." }, 400);
    }

    const { data: entitlement } = await admin.from("pro_entitlements").select("expires_at, revoked_at")
      .eq("user_id", context.user.id).gt("expires_at", new Date().toISOString()).is("revoked_at", null).maybeSingle();
    const limit = entitlement ? 25 : 1;
    const { count } = await admin.from("price_alerts").select("id", { count: "exact", head: true })
      .eq("user_id", context.user.id).in("status", ["active", "temporarily_unavailable"])
      .neq("stack_item_id", itemID);
    if ((count ?? 0) >= limit) {
      return jsonResponse({ error: "Stacks Pro is required for more price alerts.", code: "pro_required", limit }, 402);
    }

    const now = new Date().toISOString();
    const { data: alert, error } = await admin.from("price_alerts").upsert({
      user_id: context.user.id, stack_item_id: itemID, mode, target_price: target,
      currency_code: verified.currencyCode, baseline_price: verified.price,
      current_price: verified.price, lowest_price: verified.price, status: "active",
      next_check_at: nextDailyCheck(), last_checked_at: now, last_success_at: now,
      consecutive_failures: 0, last_error: null, updated_at: now,
    }, { onConflict: "user_id,stack_item_id" }).select("*").single();
    if (error) throw error;
    await admin.from("price_observations").insert({ alert_id: alert.id, price: verified.price, currency_code: verified.currencyCode });
    await admin.from("stack_items").update({ price: verified.price, currency_code: verified.currencyCode, updated_at: now }).eq("id", itemID);
    return jsonResponse({ alert });
  } catch (error) {
    console.error("price-alerts", error);
    if (error instanceof PriceVerificationError) return jsonResponse({ error: error.message, code: error.code }, 422);
    return jsonResponse({ error: "Price alerts are temporarily unavailable." }, 500);
  }
});

async function canViewItem(admin: ReturnType<typeof serviceClient>, userID: string, stackID: string, linkToken: string): Promise<boolean> {
  const { data: stack } = await admin.from("stacks").select("owner_id, visibility, public_link_token").eq("id", stackID).maybeSingle();
  if (!stack) return false;
  if (stack.owner_id === userID || stack.visibility === "public") return true;
  if (stack.visibility === "link_only" && linkToken && stack.public_link_token === linkToken) return true;
  const { data: collaborator } = await admin.from("stack_collaborators").select("user_id")
    .eq("stack_id", stackID).eq("user_id", userID).not("accepted_at", "is", null).maybeSingle();
  return Boolean(collaborator);
}

function nextDailyCheck(): string {
  const jitterMinutes = Math.floor(Math.random() * 180);
  return new Date(Date.now() + (21 * 60 + jitterMinutes) * 60_000).toISOString();
}
