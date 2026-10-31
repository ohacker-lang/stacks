import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { corsHeaders, jsonResponse, readJson } from "../_shared/http.ts";

// App Review can't read a sign-in email, so the review account signs in with a
// fixed code instead. Both the account's email and the code are Supabase
// secrets (REVIEW_EMAIL, REVIEW_CODE); without them this function refuses
// everything. The app only calls it after a normal email code fails.
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, 405);
  }

  const reviewEmail = Deno.env.get("REVIEW_EMAIL")?.trim().toLowerCase();
  const reviewCode = Deno.env.get("REVIEW_CODE")?.trim();
  const projectURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const invalid = jsonResponse({ msg: "Token has expired or is invalid" }, 403);
  if (!reviewEmail || !reviewCode || !projectURL || !anonKey || !serviceRoleKey) return invalid;

  const body = await readJson(req);
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  const code = typeof body.code === "string" ? body.code.replace(/\D/g, "") : "";
  if (!constantTimeEqual(email, reviewEmail) || !constantTimeEqual(code, reviewCode)) return invalid;

  const options = { auth: { autoRefreshToken: false, persistSession: false } };
  const admin = createClient(projectURL, serviceRoleKey, options);
  const anon = createClient(projectURL, anonKey, options);

  try {
    // A one-time code minted for the review account, redeemed straight away,
    // gives the same session a normal email sign-in would.
    let link = await admin.auth.admin.generateLink({ type: "magiclink", email: reviewEmail });
    if (link.error) {
      const created = await admin.auth.admin.createUser({ email: reviewEmail, email_confirm: true });
      if (created.error) throw created.error;
      link = await admin.auth.admin.generateLink({ type: "magiclink", email: reviewEmail });
      if (link.error) throw link.error;
    }

    const { data, error } = await anon.auth.verifyOtp({
      email: reviewEmail,
      token: link.data.properties.email_otp,
      type: "email",
    });
    if (error || !data.session) throw error ?? new Error("No session returned.");

    const { access_token, refresh_token, expires_in, user } = data.session;
    return jsonResponse({ access_token, refresh_token, expires_in, user });
  } catch (error) {
    console.error("Review sign-in failed", error);
    return jsonResponse({ error: "service is temporarily unavailable" }, 503);
  }
});

function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}
