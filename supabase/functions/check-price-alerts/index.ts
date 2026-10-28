import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse } from "../_shared/http.ts";
import { requiredEnv, serviceClient } from "../_shared/supabase.ts";
import { verifyProductPrice } from "../_shared/price.ts";

type DueAlert = {
  id: string;
  user_id: string;
  stack_item_id: string;
  mode: "any_drop" | "target";
  target_price: number | null;
  currency_code: string;
  current_price: number;
  lowest_price: number;
  consecutive_failures: number;
  stack_items: { title: string; stack_id: string; buy_url: string | null; source_url: string | null };
};

serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);
  const expected = requiredEnv("PRICE_CHECK_SECRET");
  if (req.headers.get("Authorization") !== `Bearer ${expected}`) return jsonResponse({ error: "Unauthorized." }, 401);
  const admin = serviceClient();
  const now = new Date();
  const { data, error } = await admin.from("price_alerts")
    .select("*, stack_items!inner(title, stack_id, buy_url, source_url)")
    .in("status", ["active", "temporarily_unavailable"]).lte("next_check_at", now.toISOString())
    .order("next_check_at").limit(75);
  if (error) return jsonResponse({ error: "Unable to load due alerts." }, 500);

  const alerts = (data ?? []) as DueAlert[];
  const prices = new Map<string, Awaited<ReturnType<typeof verifyProductPrice>> | Error>();
  let triggered = 0;
  for (const alert of alerts) {
    const url = alert.stack_items.buy_url ?? alert.stack_items.source_url ?? "";
    if (!prices.has(url)) {
      try { prices.set(url, await verifyProductPrice(url)); }
      catch (failure) { prices.set(url, failure instanceof Error ? failure : new Error("Price check failed.")); }
    }
    const result = prices.get(url)!;
    if (result instanceof Error) {
      const failures = alert.consecutive_failures + 1;
      await admin.from("price_alerts").update({
        status: "temporarily_unavailable", consecutive_failures: failures,
        last_checked_at: now.toISOString(), last_error: result.message,
        next_check_at: retryDate(failures), updated_at: now.toISOString(),
      }).eq("id", alert.id);
      continue;
    }
    if (result.currencyCode !== alert.currency_code) {
      await admin.from("price_alerts").update({
        status: "temporarily_unavailable", consecutive_failures: alert.consecutive_failures + 1,
        last_checked_at: now.toISOString(), last_error: "The retailer changed currencies.",
        next_check_at: retryDate(alert.consecutive_failures + 1), updated_at: now.toISOString(),
      }).eq("id", alert.id);
      continue;
    }

    const previous = Number(alert.current_price);
    const current = Number(result.price);
    const lowest = Math.min(Number(alert.lowest_price), current);
    const shouldNotify = alert.mode === "any_drop"
      ? current < Number(alert.lowest_price)
      : previous > Number(alert.target_price) && current <= Number(alert.target_price);
    const update = {
      current_price: current, lowest_price: lowest, status: "active", consecutive_failures: 0,
      last_error: null, last_checked_at: now.toISOString(), last_success_at: now.toISOString(),
      next_check_at: nextDailyCheck(), updated_at: now.toISOString(),
      ...(shouldNotify ? { last_notified_price: current } : {}),
    };
    await admin.from("price_alerts").update(update).eq("id", alert.id);
    await admin.from("stack_items").update({ price: current, currency_code: result.currencyCode, updated_at: now.toISOString() })
      .eq("id", alert.stack_item_id);
    if (current !== previous) {
      await admin.from("price_observations").insert({ alert_id: alert.id, price: current, currency_code: result.currencyCode });
    }
    if (!shouldNotify) continue;

    const dedupeKey = `${alert.id}:${current.toFixed(2)}:${now.toISOString().slice(0, 10)}`;
    const { data: event, error: eventError } = await admin.from("price_alert_events").insert({
      alert_id: alert.id, user_id: alert.user_id, previous_price: previous, current_price: current,
      currency_code: result.currencyCode, dedupe_key: dedupeKey,
    }).select("id").maybeSingle();
    if (eventError || !event) continue;
    triggered += 1;
    const delivered = await notifyUser(alert, current, previous);
    if (delivered) await admin.from("price_alert_events").update({ delivered_at: new Date().toISOString() }).eq("id", event.id);
  }
  return jsonResponse({ checked: alerts.length, products: prices.size, triggered });
});

async function notifyUser(alert: DueAlert, current: number, previous: number): Promise<boolean> {
  const admin = serviceClient();
  const { data: preference } = await admin.from("notification_preferences").select("price_alerts_enabled")
    .eq("user_id", alert.user_id).maybeSingle();
  if (preference?.price_alerts_enabled === false) return false;
  const { data: tokens } = await admin.from("push_device_tokens").select("token, environment")
    .eq("user_id", alert.user_id).eq("enabled", true);
  let delivered = false;
  for (const row of tokens ?? []) {
    const response = await sendAPNS(row.token, row.environment, {
      aps: {
        alert: { title: "Price drop", body: `${alert.stack_items.title} dropped from ${money(previous, alert.currency_code)} to ${money(current, alert.currency_code)}.` },
        sound: "default",
      },
      type: "price_alert", stackID: alert.stack_items.stack_id, itemID: alert.stack_item_id,
    });
    delivered ||= response.ok;
    if (response.status === 410) await admin.from("push_device_tokens").update({ enabled: false }).eq("token", row.token);
  }
  return delivered;
}

async function sendAPNS(token: string, environment: string, payload: unknown): Promise<Response> {
  const jwt = await apnsJWT();
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  return fetch(`https://${host}/3/device/${token}`, {
    method: "POST",
    headers: { authorization: `bearer ${jwt}`, "apns-topic": requiredEnv("APNS_BUNDLE_ID"), "apns-push-type": "alert", "apns-priority": "10" },
    body: JSON.stringify(payload),
  });
}

let cachedJWT: { value: string; created: number } | null = null;
async function apnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.created < 45 * 60) return cachedJWT.value;
  const header = base64url(JSON.stringify({ alg: "ES256", kid: requiredEnv("APNS_KEY_ID") }));
  const claims = base64url(JSON.stringify({ iss: requiredEnv("APNS_TEAM_ID"), iat: now }));
  const keyBytes = pemBytes(requiredEnv("APNS_PRIVATE_KEY"));
  const key = await crypto.subtle.importKey("pkcs8", keyBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`));
  const value = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  cachedJWT = { value, created: now };
  return value;
}

function pemBytes(pem: string): ArrayBuffer {
  const binary = atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, ""));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0)).buffer;
}

function base64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function retryDate(failures: number): string {
  const hours = Math.min(24 * 7, Math.pow(2, Math.min(failures, 7)) * 3);
  return new Date(Date.now() + hours * 3_600_000).toISOString();
}
function nextDailyCheck(): string { return new Date(Date.now() + (21 + Math.random() * 3) * 3_600_000).toISOString(); }
function money(value: number, currency: string): string {
  try { return new Intl.NumberFormat("en-US", { style: "currency", currency }).format(value); }
  catch { return `${currency} ${value.toFixed(2)}`; }
}
