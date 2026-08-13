import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, isUUID, serviceClient } from "../_shared/supabase.ts";

const bucket = "stack-media";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;

    const body = await readJson(req);
    const stackID = String(body.stackID ?? "");
    const path = String(body.path ?? "");
    const linkToken = String(body.linkToken ?? "");
    const expiresIn = Math.min(Math.max(Number(body.expiresIn ?? 300), 60), 600);
    if (!isUUID(stackID) || !path) return jsonResponse({ error: "A Stack and media path are required." }, 400);

    const { data: normallyAllowed, error: accessError } = await context.client.rpc("can_view_stack", {
      target_stack_id: stackID,
    });
    const { data: linkAllowed, error: linkError } = linkToken && isUUID(linkToken)
      ? await context.client.rpc("can_view_link_only_stack", { link_token: linkToken, target_stack_id: stackID })
      : { data: false, error: null };
    if (accessError || linkError || (!normallyAllowed && !linkAllowed)) {
      return jsonResponse({ error: "You cannot view this media." }, 403);
    }

    const attachmentFunction = normallyAllowed
      ? "can_access_stack_item_media"
      : "is_stack_item_media_path";
    const attachmentClient = normallyAllowed ? context.client : serviceClient();
    const { data: attachedToItem, error: itemError } = await attachmentClient.rpc(attachmentFunction, {
      target_stack_id: stackID,
      target_path: path,
    });
    if (itemError || !attachedToItem) {
      return jsonResponse({ error: "That media is not available to viewers." }, 403);
    }

    // Access was proven above with the caller's JWT. Use the server client for
    // the ownership lookup so token-authorized link-only viewers do not need a
    // broad table SELECT policy.
    const { data: stack, error: stackError } = await serviceClient()
      .from("stacks")
      .select("id, owner_id")
      .eq("id", stackID)
      .single();
    if (stackError || !stack || !isStackMediaPath(path, stack.owner_id, stack.id)) {
      return jsonResponse({ error: "That media path does not belong to this Stack." }, 400);
    }

    const { data, error } = await serviceClient().storage.from(bucket).createSignedUrl(path, expiresIn);
    if (error || !data?.signedUrl) return jsonResponse({ error: "The media is unavailable." }, 404);
    return jsonResponse({ signedURL: data.signedUrl, expiresIn });
  } catch (error) {
    console.error("media-url", error);
    return jsonResponse({ error: "Unable to prepare media." }, 500);
  }
});

function isStackMediaPath(path: string, ownerID: string, stackID: string): boolean {
  return path.startsWith(`${ownerID}/${stackID}/`) && !path.includes("..") && !path.startsWith("/");
}
