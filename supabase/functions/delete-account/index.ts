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
    // Swift's UUID.uuidString uses uppercase hex, while Supabase Auth returns
    // lowercase UUIDs. Existing uploads therefore live under uppercase paths.
    const userPrefixes = [...new Set([user.id.toUpperCase(), user.id.toLowerCase()])];
    for (const prefix of userPrefixes) {
      await removeUserMedia(admin, prefix, "stack-media");
      await removeUserMedia(admin, prefix, "profile-media");
    }

    // Soft deletion retains the auth row and does not run profile cascades.
    const { error } = await admin.auth.admin.deleteUser(user.id);
    if (error) throw error;

    return jsonResponse({ deleted: true });
  } catch (error) {
    console.error("Account deletion failed", error);
    return jsonResponse({ error: "We could not delete this account. Please try again." }, 500);
  }
});

async function removeUserMedia(
  admin: ReturnType<typeof createClient>,
  userID: string,
  bucket: string,
) {
  // Storage.list is folder-scoped. Traverse every nested folder under the
  // user's namespace, and delete through the Storage API so file bytes and
  // metadata are both removed. PostgREST does not normally expose `storage`.
  async function removeFolder(path: string): Promise<void> {
    const files: string[] = [];
    const folders: string[] = [];
    for (let offset = 0; ; offset += 1_000) {
      const { data: entries, error } = await admin.storage.from(bucket).list(path, {
        limit: 1_000,
        offset,
      });
      if (error) throw error;
      if (!entries?.length) break;
      for (const entry of entries) {
        const child = `${path}/${entry.name}`;
        if (entry.id === null) folders.push(child);
        else files.push(child);
      }
      if (entries.length < 1_000) break;
    }
    for (const folder of folders) await removeFolder(folder);
    for (let index = 0; index < files.length; index += 1_000) {
      const { error } = await admin.storage.from(bucket).remove(files.slice(index, index + 1_000));
      if (error) throw error;
    }
  }
  await removeFolder(userID);
}
