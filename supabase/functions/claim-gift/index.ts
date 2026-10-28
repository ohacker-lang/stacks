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
    const stackID = String(body.stackID ?? "").trim();
    const itemID = String(body.itemID ?? "").trim();
    const claimerName = String(body.claimerName ?? "").trim();
    const linkToken = body.linkToken == null ? null : String(body.linkToken).trim();
    if (!isUUID(stackID) || !isUUID(itemID) || !claimerName || claimerName.length > 80) {
      return jsonResponse({ error: "A Stack, item, and claimant name are required." }, 400);
    }
    if (linkToken !== null && !isUUID(linkToken)) {
      return jsonResponse({ error: "That private link is invalid." }, 400);
    }

    // The database function checks normal access or exact link possession,
    // locks the item, and inserts the claim in one transaction.
    const { data, error: claimError } = await context.client.rpc("claim_wishlist_item", {
      target_stack_id: stackID,
      target_item_id: itemID,
      link_token: linkToken,
      claim_name: claimerName,
    });

    if (claimError?.code === "23505" || claimError?.message?.includes("already been claimed")) {
      // Do not disclose who claimed the item or when.
      return jsonResponse({ error: "This item has already been claimed." }, 409);
    }
    if (claimError) {
      if (claimError.code === "42501") return jsonResponse({ error: "You cannot claim this item." }, 403);
      if (claimError.code === "P0001") return jsonResponse({ error: claimError.message }, 400);
      throw claimError;
    }

    const claim = Array.isArray(data) ? data[0] : data;
    if (!claim) throw new Error("Claim creation failed.");

    return jsonResponse({
      claim: {
        id: claim.id,
        stackID: claim.stack_id,
        itemID: claim.item_id,
        claimerName: claim.claimer_name,
        privateMessage: claim.private_message,
        status: claim.status,
        createdAt: claim.created_at,
      },
    }, 201);
  } catch (error) {
    console.error("claim-gift", error);
    return jsonResponse({ error: "Unable to claim this item. Please try again." }, 500);
  }
});
