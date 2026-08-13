import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

import { corsHeaders, jsonResponse } from "../_shared/http.ts";
import { isUUID, serviceClient } from "../_shared/supabase.ts";

const bucket = "stack-media";

type PreviewItem = {
  id: string;
  title: string;
  brand: string;
  description: string;
  price: number | null;
  currency_code: string | null;
  size_text: string;
  buy_url: string | null;
  affiliate_url: string | null;
  original_image_path: string | null;
  removed_background_image_path: string | null;
  removal_status: string;
  placement_x: number;
  placement_y: number;
  placement_scale: number;
  rotation_degrees: number;
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "GET") return jsonResponse({ error: "Method not allowed." }, 405);

  try {
    const url = new URL(req.url);
    const stackID = url.searchParams.get("stackID")?.trim() ?? "";
    const linkToken = url.searchParams.get("token")?.trim() ?? "";
    if (!isUUID(stackID)) return jsonResponse({ error: "A valid Stack is required." }, 400);

    const admin = serviceClient();
    const stack = await loadSharedStack(admin, stackID, linkToken);
    if (!stack) return jsonResponse({ error: "This Stack is unavailable." }, 404);

    const { data: profile } = await admin
      .from("profiles")
      .select("display_name, username, avatar_path")
      .eq("id", stack.owner_id)
      .single();
    const { data: items, error: itemsError } = await admin
      .from("stack_items")
      .select("id, title, brand, description, price, currency_code, size_text, buy_url, affiliate_url, original_image_path, removed_background_image_path, removal_status, placement_x, placement_y, placement_scale, rotation_degrees")
      .eq("stack_id", stack.id)
      .order("created_at");
    if (itemsError) throw itemsError;

    const previewItems = await Promise.all((items ?? []).map((item) => toPreviewItem(admin, item as PreviewItem)));
    return jsonResponse({
      stack: {
        id: stack.id,
        title: stack.title,
        summary: stack.summary,
        wishlistMode: stack.wishlist_mode,
        author: profile ? {
          displayName: profile.display_name,
          username: profile.username,
          avatarPath: profile.avatar_path,
        } : null,
        items: previewItems,
      },
    });
  } catch (error) {
    console.error("web-preview", error);
    return jsonResponse({ error: "Unable to load this Stack." }, 500);
  }
});

async function loadSharedStack(
  admin: ReturnType<typeof serviceClient>,
  stackID: string,
  linkToken: string,
) {
  const { data: publicStack, error: publicError } = await admin
    .from("stacks")
    .select("id, owner_id, title, summary, wishlist_mode, visibility")
    .eq("id", stackID)
    .eq("visibility", "public")
    .maybeSingle();
  if (!publicError && publicStack) return publicStack;

  if (!isUUID(linkToken)) return null;
  const { data: linkOnlyStack, error: linkError } = await admin
    .from("stacks")
    .select("id, owner_id, title, summary, wishlist_mode, visibility")
    .eq("id", stackID)
    .eq("visibility", "link_only")
    .eq("public_link_token", linkToken)
    .maybeSingle();
  return linkError ? null : linkOnlyStack;
}

async function toPreviewItem(admin: ReturnType<typeof serviceClient>, item: PreviewItem) {
  const imagePath = item.removed_background_image_path ?? item.original_image_path;
  const imageURL = imagePath
    ? (await admin.storage.from(bucket).createSignedUrl(imagePath, 300)).data?.signedUrl ?? null
    : null;
  return {
    id: item.id,
    title: item.title,
    brand: item.brand,
    description: item.description,
    price: item.price,
    currencyCode: item.currency_code,
    sizeText: item.size_text,
    buyURL: item.affiliate_url ?? item.buy_url,
    imageURL,
    removalStatus: item.removal_status,
    placement: {
      x: item.placement_x,
      y: item.placement_y,
      scale: item.placement_scale,
      rotationDegrees: item.rotation_degrees,
    },
  };
}
