import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";
import { authenticatedRequest, isResponse, isUUID, serviceClient } from "../_shared/supabase.ts";

const bucket = "stack-media";

type SourceStack = {
  id: string;
  owner_id: string;
  title: string;
  summary: string;
  wishlist_mode: boolean;
};

type SourceItem = {
  id: string;
  title: string;
  brand: string;
  description: string;
  price: number | null;
  currency_code: string | null;
  size_text: string;
  source_url: string | null;
  buy_url: string | null;
  original_image_path: string | null;
  removed_background_image_path: string | null;
  removal_status: string;
  placement_x: number;
  placement_y: number;
  placement_scale: number;
  rotation_degrees: number;
  has_custom_placement: boolean;
  source_type: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const context = await authenticatedRequest(req);
    if (isResponse(context)) return context;
    const body = await readJson(req);
    const sourceStackID = String(body.stackID ?? "");
    const linkToken = String(body.linkToken ?? "");
    const requestedTitle = String(body.title ?? "").trim();
    if (!isUUID(sourceStackID)) return jsonResponse({ error: "A valid Stack is required." }, 400);

    const source = await loadSource(context.client, sourceStackID, linkToken);
    if (!source) return jsonResponse({ error: "That Stack is unavailable or cannot be copied." }, 404);
    if (source.stack.owner_id === context.user.id) {
      return jsonResponse({ error: "This Stack already belongs to you." }, 400);
    }

    const destinationID = crypto.randomUUID();
    const title = requestedTitle || copiedTitle(source.stack.title);
    if (title.length > 80) return jsonResponse({ error: "Stack titles must be 80 characters or fewer." }, 400);

    const admin = serviceClient();
    const { error: stackError } = await admin.from("stacks").insert({
      id: destinationID,
      owner_id: context.user.id,
      title,
      summary: source.stack.summary,
      visibility: "private",
      wishlist_mode: source.stack.wishlist_mode,
      copied_from_stack_id: source.stack.id,
    });
    if (stackError) throw stackError;

    const copiedItemIDs: string[] = [];
    try {
      for (const item of source.items) {
        const destinationItemID = crypto.randomUUID();
        const originalPath = await copyMedia(admin, item.original_image_path, source.stack, context.user.id, destinationID, destinationItemID, "original");
        const removedPath = await copyMedia(admin, item.removed_background_image_path, source.stack, context.user.id, destinationID, destinationItemID, "removed");
        const { error: itemError } = await admin.from("stack_items").insert({
          id: destinationItemID,
          stack_id: destinationID,
          title: item.title,
          brand: item.brand,
          description: item.description,
          price: item.price,
          currency_code: item.currency_code,
          size_text: item.size_text,
          source_url: item.source_url,
          buy_url: item.buy_url,
          affiliate_url: null,
          original_image_path: originalPath,
          removed_background_image_path: removedPath,
          removal_status: removedPath ? item.removal_status : "failed",
          placement_x: item.placement_x,
          placement_y: item.placement_y,
          placement_scale: item.placement_scale,
          rotation_degrees: item.rotation_degrees,
          has_custom_placement: item.has_custom_placement,
          source_type: item.source_type,
        });
        if (itemError) throw itemError;
        copiedItemIDs.push(destinationItemID);
      }
    } catch (error) {
      await admin.from("stacks").delete().eq("id", destinationID);
      throw error;
    }

    return jsonResponse({ stackID: destinationID, copiedItemIDs });
  } catch (error) {
    console.error("copy-public-stack", error);
    return jsonResponse({ error: "Unable to copy this Stack. Please try again." }, 500);
  }
});

async function loadSource(client: ReturnType<typeof serviceClient>, stackID: string, linkToken: string): Promise<{ stack: SourceStack; items: SourceItem[] } | null> {
  const { data: publicStack, error: publicError } = await client
    .from("stacks")
    .select("id, owner_id, title, summary, wishlist_mode, visibility")
    .eq("id", stackID)
    .in("visibility", ["public"])
    .maybeSingle();
  if (!publicError && publicStack) {
    const { data: items, error: itemsError } = await client
      .from("stack_items")
      .select("id, title, brand, description, price, currency_code, size_text, source_url, buy_url, original_image_path, removed_background_image_path, removal_status, placement_x, placement_y, placement_scale, rotation_degrees, has_custom_placement, source_type")
      .eq("stack_id", stackID)
      .order("created_at");
    if (!itemsError) return { stack: publicStack as SourceStack, items: (items ?? []) as SourceItem[] };
  }

  if (!isUUID(linkToken)) return null;
  const { data: payload, error } = await client.rpc("get_link_only_stack", { link_token: linkToken });
  if (error || !payload || payload.stack?.id !== stackID) return null;
  return { stack: payload.stack as SourceStack, items: payload.items as SourceItem[] };
}

async function copyMedia(
  admin: ReturnType<typeof serviceClient>,
  sourcePath: string | null,
  sourceStack: SourceStack,
  destinationOwnerID: string,
  destinationStackID: string,
  destinationItemID: string,
  variant: string,
): Promise<string | null> {
  if (!sourcePath) return null;
  if (!sourcePath.startsWith(`${sourceStack.owner_id}/${sourceStack.id}/`)) {
    throw new Error("Source media path does not belong to the source Stack.");
  }
  const { data: file, error: downloadError } = await admin.storage.from(bucket).download(sourcePath);
  if (downloadError || !file) throw downloadError ?? new Error("Source media is unavailable.");

  const extension = sourcePath.split(".").pop()?.toLowerCase() || "png";
  const destinationPath = `${destinationOwnerID}/${destinationStackID}/${destinationItemID}/${variant}.${extension}`;
  const { error: uploadError } = await admin.storage.from(bucket).upload(destinationPath, file, {
    contentType: file.type || undefined,
    upsert: false,
  });
  if (uploadError) throw uploadError;
  return destinationPath;
}

function copiedTitle(sourceTitle: string): string {
  const suffix = " copy";
  return `${sourceTitle.slice(0, 80 - suffix.length)}${suffix}`;
}
