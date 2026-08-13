export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

export async function readJson(req: Request): Promise<Record<string, unknown>> {
  try {
    return await req.json();
  } catch {
    return {};
  }
}

export type AuthenticatedUser = {
  id: string;
  email?: string;
};

// The gateway also verifies JWTs for app-facing functions. This explicit
// check keeps local invocations and accidental config changes from turning a
// private endpoint into an anonymous one.
export async function requireAuthenticatedUser(req: Request): Promise<AuthenticatedUser | Response> {
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    return jsonResponse({ error: "authentication is required" }, 401);
  }

  const projectURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!projectURL || !anonKey) {
    console.error("Supabase function environment is missing auth configuration.");
    return jsonResponse({ error: "service is temporarily unavailable" }, 503);
  }

  try {
    const response = await fetch(`${projectURL}/auth/v1/user`, {
      headers: {
        Authorization: authorization,
        apikey: anonKey,
      },
      signal: AbortSignal.timeout(5_000),
    });

    if (!response.ok) return jsonResponse({ error: "authentication is required" }, 401);
    const user = await response.json() as AuthenticatedUser;
    return user?.id ? user : jsonResponse({ error: "authentication is required" }, 401);
  } catch (error) {
    console.error("Supabase auth verification failed", error);
    return jsonResponse({ error: "service is temporarily unavailable" }, 503);
  }
}
