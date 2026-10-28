import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, isUUID, serviceClient } from "../_shared/supabase.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;

    const body = await readJson(req);
    const stackID = String(body.stackID ?? "").trim();
    const itemID = String(body.itemID ?? "").trim();
    const requestedStatus = body.status == null ? null : String(body.status).trim();
    if (!isUUID(stackID) || !isUUID(itemID) || ![null, "claimed", "purchased"].includes(requestedStatus)) {
      return jsonResponse({ error: "A valid Stack, item, and claim status are required." }, 400);
    }

    const admin = serviceClient();
    const { data: stack, error: stackError } = await admin
      .from("stacks")
      .select("id, owner_id, wishlist_mode")
      .eq("id", stackID)
      .maybeSingle();
    if (stackError) throw stackError;
    if (!stack?.wishlist_mode) return jsonResponse({ error: "This Stack is not a wishlist." }, 409);

    if (stack.owner_id === context.user.id) {
      return jsonResponse({ error: "The wishlist owner cannot view or change gift claims." }, 403);
    }
    const { data: activeClaim, error: claimError } = await admin
      .from("gift_claims")
      .select("id, claimer_id, status")
      .eq("stack_id", stackID)
      .eq("item_id", itemID)
      .in("status", ["claimed", "purchased"])
      .maybeSingle();
    if (claimError) throw claimError;
    if (!activeClaim) return jsonResponse({ status: null });

    if (activeClaim.claimer_id !== context.user.id) {
      return jsonResponse({ error: "Only the person who claimed this gift can change it." }, 403);
    }

    if (requestedStatus === null) {
      const { error } = await admin
        .from("gift_claims")
        .update({ status: "cancelled" })
        .eq("id", activeClaim.id);
      if (error) throw error;
      return jsonResponse({ status: null });
    }

    const { error } = await admin
      .from("gift_claims")
      .update({ status: requestedStatus })
      .eq("id", activeClaim.id);
    if (error) throw error;
    return jsonResponse({ status: requestedStatus });
  } catch (error) {
    console.error("update-gift-claim", error);
    return jsonResponse({ error: "Unable to update this claim. Please try again." }, 500);
  }
});
