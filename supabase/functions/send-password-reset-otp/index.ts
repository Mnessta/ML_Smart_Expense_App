import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const INTERNAL_SECRET = Deno.env.get("INTERNAL_OTP_MAIL_SECRET");
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL =
  Deno.env.get("OTP_FROM_EMAIL") ?? "ML Smart Expense <onboarding@resend.dev>";

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const incomingSecret = req.headers.get("x-internal-secret");
  if (!INTERNAL_SECRET || incomingSecret !== INTERNAL_SECRET) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  if (!RESEND_API_KEY) {
    return jsonResponse(
      { error: "RESEND_API_KEY is not set on the Edge Function" },
      500,
    );
  }

  let payload: { email?: string; otp?: string };
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const email = typeof payload.email === "string" ? payload.email.trim() : "";
  const otp = typeof payload.otp === "string" ? payload.otp.trim() : "";

  if (!email || !email.includes("@") || !/^\d{6}$/.test(otp)) {
    return jsonResponse({ error: "Missing or invalid email or otp" }, 400);
  }

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [email],
      subject: "Your password reset code",
      html: `<p>Your password reset code is: <strong>${otp}</strong></p><p>This code will expire in 10 minutes.</p><p>If you did not request this, you can ignore this email.</p>`,
    }),
  });

  if (!res.ok) {
    const errText = await res.text();
    console.error("Resend error:", res.status, errText);
    return jsonResponse(
      { error: "Failed to send email", detail: errText },
      502,
    );
  }

  return jsonResponse({ ok: true });
});
