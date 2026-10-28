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
    const token = String(body.token ?? "").trim();
    if (!isUUID(token)) return jsonResponse({ error: "This invitation is invalid." }, 400);

    const admin = serviceClient();
    const { data: invite, error: inviteError } = await admin
      .from("collaboration_invites")
      .select("stack_id, permission, expires_at, accepted_at, revoked_at")
      .eq("token", token)
      .maybeSingle();
    if (inviteError) throw inviteError;
    if (!invite || invite.revoked_at || invite.accepted_at || new Date(invite.expires_at) <= new Date()) {
      return jsonResponse({ error: "This invitation is unavailable or has expired." }, 404);
    }

    const { data: stack, error: stackError } = await admin
      .from("stacks")
      .select("id, title, owner_id, collaboration_enabled")
      .eq("id", invite.stack_id)
      .maybeSingle();
    if (stackError) throw stackError;
    if (!stack || !stack.collaboration_enabled) {
      return jsonResponse({ error: "Collaboration is no longer enabled for this Stack." }, 409);
    }

    const { data: owner, error: ownerError } = await admin
      .from("profiles")
      .select("id, display_name, username, avatar_path")
      .eq("id", stack.owner_id)
      .maybeSingle();
    if (ownerError || !owner) throw ownerError ?? new Error("Stack owner unavailable.");

    return jsonResponse({
      stackID: stack.id,
      stackTitle: stack.title,
      permission: invite.permission,
      expiresAt: invite.expires_at,
      ownerID: owner.id,
      ownerName: owner.display_name,
      ownerUsername: owner.username,
      ownerAvatarPath: owner.avatar_path,
    });
  } catch (error) {
    console.error("preview-collaboration-invite", error);
    return jsonResponse({ error: "Unable to open this invitation. Please try again." }, 500);
  }
});
