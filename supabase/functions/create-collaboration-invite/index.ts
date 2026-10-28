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
    const permission = String(body.permission ?? "editor").trim();
    if (!isUUID(stackID) || !["viewer", "editor"].includes(permission)) {
      return jsonResponse({ error: "A valid Stack and permission are required." }, 400);
    }

    // Check ownership through the caller-scoped client. A service role client
    // is only used afterwards to create the opaque token.
    const { data: stack, error: stackError } = await context.client
      .from("stacks")
      .select("id, owner_id, collaboration_enabled")
      .eq("id", stackID)
      .maybeSingle();
    if (stackError || !stack || stack.owner_id !== context.user.id) {
      return jsonResponse({ error: "Only the Stack owner can invite collaborators." }, 403);
    }
    if (!stack.collaboration_enabled) {
      return jsonResponse({ error: "Turn on collaboration before inviting people." }, 409);
    }

    const admin = serviceClient();
    const { data: entitlement, error: entitlementError } = await admin
      .from("pro_entitlements")
      .select("expires_at, revoked_at")
      .eq("user_id", stack.owner_id)
      .maybeSingle();
    if (entitlementError) throw entitlementError;
    const isPro = entitlement && !entitlement.revoked_at &&
      new Date(entitlement.expires_at).getTime() > Date.now();
    if (!isPro) {
      const [{ count: collaborators, error: collaboratorsError }, { count: pendingInvites, error: invitesError }] =
        await Promise.all([
          admin.from("stack_collaborators").select("stack_id", { count: "exact", head: true }).eq("stack_id", stackID),
          admin.from("collaboration_invites").select("id", { count: "exact", head: true })
            .eq("stack_id", stackID).is("accepted_at", null).is("revoked_at", null)
            .gt("expires_at", new Date().toISOString()),
        ]);
      if (collaboratorsError || invitesError) throw collaboratorsError ?? invitesError;
      if ((collaborators ?? 0) + (pendingInvites ?? 0) >= 3) {
        return jsonResponse({ error: "Stacks Pro is required for more than 3 invited collaborators." }, 402);
      }
    }
    const { data: invite, error: inviteError } = await admin
      .from("collaboration_invites")
      .insert({ stack_id: stackID, invited_by: context.user.id, permission })
      .select("id, stack_id, token, permission, expires_at")
      .single();
    if (inviteError?.message?.includes("Stacks Pro is required")) {
      return jsonResponse({ error: inviteError.message }, 402);
    }
    if (inviteError || !invite) throw inviteError ?? new Error("Invite creation failed.");

    return jsonResponse({
      invite: {
        id: invite.id,
        stackId: invite.stack_id,
        token: invite.token,
        permission: invite.permission,
        expiresAt: invite.expires_at,
      },
    }, 201);
  } catch (error) {
    console.error("create-collaboration-invite", error);
    return jsonResponse({ error: "Unable to create this invite. Please try again." }, 500);
  }
});
