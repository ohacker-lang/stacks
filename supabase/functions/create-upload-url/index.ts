import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, isUUID, serviceClient } from "../_shared/supabase.ts";

const bucket = "stack-media";
const contentTypes = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);
const extensions: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/heic": "heic",
  "image/webp": "webp",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;

    const body = await readJson(req);
    const stackID = String(body.stackID ?? "");
    const itemID = String(body.itemID ?? crypto.randomUUID());
    const contentType = String(body.contentType ?? "").toLowerCase();
    if (!isUUID(stackID) || !isUUID(itemID) || !contentTypes.has(contentType)) {
      return jsonResponse({ error: "A valid Stack, item, and image type are required." }, 400);
    }

    const { data: canEdit, error: accessError } = await context.client.rpc("can_edit_stack", {
      target_stack_id: stackID,
    });
    if (accessError || !canEdit) return jsonResponse({ error: "You cannot add media to this Stack." }, 403);

    const { data: stack, error: stackError } = await context.client
      .from("stacks")
      .select("id, owner_id")
      .eq("id", stackID)
      .single();
    if (stackError || !stack) return jsonResponse({ error: "That Stack is unavailable." }, 404);

    const path = `${stack.owner_id}/${stack.id}/${itemID}/original.${extensions[contentType]}`;
    const { data, error } = await serviceClient().storage.from(bucket).createSignedUploadUrl(path);
    if (error || !data?.signedUrl) return jsonResponse({ error: "Unable to prepare upload." }, 500);

    return jsonResponse({ itemID, path, signedUploadURL: data.signedUrl, token: data.token });
  } catch (error) {
    console.error("create-upload-url", error);
    return jsonResponse({ error: "Unable to prepare upload." }, 500);
  }
});
