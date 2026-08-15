import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });

function normalizePhone(value: unknown) {
  const raw = String(value ?? "").trim().replace(/[^\d+]/g, "");
  if (!raw) return "";
  if (raw.startsWith("00")) return "+" + raw.slice(2);
  if (raw.startsWith("+")) return raw;
  if (raw.startsWith("0")) return "+66" + raw.slice(1);
  if (raw.startsWith("66")) return "+" + raw;
  return "+" + raw;
}

function phoneEmail(phone: string) {
  return `phone_${phone.replace(/\D/g, "")}@terra-pos-pion.local`;
}

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authorization = req.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "missing_authorization" }, 401);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData.user;
  if (userError || !user) return json({ error: "invalid_session" }, 401);

  let body: { phone?: unknown };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const phone = normalizePhone(body.phone);
  if (!/^\+[1-9]\d{7,14}$/.test(phone)) return json({ error: "invalid_phone" }, 400);
  const expectedEmail = phoneEmail(phone);
  if ((user.email ?? "").toLowerCase() !== expectedEmail) return json({ error: "identity_mismatch" }, 403);

  const { data: employee, error: employeeError } = await admin
    .from("employees_v2")
    .select("id,name,role,shop_id,auth_user_id,email,username")
    .eq("username", phone)
    .limit(1)
    .maybeSingle();
  if (employeeError) return json({ error: "employee_lookup_failed" }, 500);
  if (!employee) return json({ error: "phone_not_preprovisioned" }, 404);
  if (employee.auth_user_id && employee.auth_user_id !== user.id) return json({ error: "phone_already_claimed" }, 409);

  const { error: updateError } = await admin
    .from("employees_v2")
    .update({ auth_user_id: user.id, email: expectedEmail, password: null })
    .eq("id", employee.id);
  if (updateError) return json({ error: "employee_link_failed" }, 500);

  const { error: profileError } = await admin
    .from("profiles")
    .upsert({ user_id: user.id, full_name: employee.name }, { onConflict: "user_id" });
  if (profileError) return json({ error: "profile_link_failed" }, 500);

  const { error: memberError } = await admin
    .from("shop_members")
    .upsert({ shop_id: employee.shop_id, user_id: user.id, role: employee.role }, { onConflict: "shop_id,user_id" });
  if (memberError) return json({ error: "membership_link_failed" }, 500);

  return json({ ok: true, employee: { id: employee.id, name: employee.name, role: employee.role, shop_id: employee.shop_id, auth_user_id: user.id, username: phone, email: expectedEmail } });
});
