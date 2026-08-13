import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse, requireAuthenticatedUser } from "../_shared/http.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405);
  }

  const user = await requireAuthenticatedUser(req);
  if (user instanceof Response) return user;

  const projectURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!projectURL || !serviceRoleKey) {
    console.error("Account deletion cannot access its Supabase service client.");
    return jsonResponse({ error: "service is temporarily unavailable" }, 503);
  }

  const admin = createClient(projectURL, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    // Media storage does not cascade with database rows, so clear the private
    // user prefix before deleting the auth account and its cascaded profile.
    await removeUserMedia(admin, user.id);

    const { error } = await admin.auth.admin.deleteUser(user.id, true);
    if (error) throw error;

    return jsonResponse({ deleted: true });
  } catch (error) {
    console.error("Account deletion failed", error);
    return jsonResponse({ error: "We could not delete this account. Please try again." }, 500);
  }
});

async function removeUserMedia(admin: ReturnType<typeof createClient>, userID: string) {
  // Query the object table through the service-role client instead of using
  // Storage.list. list() is directory-scoped and would leave deeper paths
  // such as <user-id>/imports/originals/... behind.
  while (true) {
    const { data: objects, error } = await admin
      .schema("storage")
      .from("objects")
      .select("name")
      .eq("bucket_id", "stack-media")
      .like("name", `${userID}/%`)
      .limit(1_000);
    if (error) throw error;

    const paths = (objects ?? []).map((object) => object.name as string);
    if (paths.length === 0) return;

    const { error: removeError } = await admin.storage.from("stack-media").remove(paths);
    if (removeError) throw removeError;
  }
}
