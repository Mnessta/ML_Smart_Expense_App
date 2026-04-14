# send-password-reset-otp

Sends the 6-digit password reset OTP by email (via [Resend](https://resend.com)).

## Deploy

From the project root (with [Supabase CLI](https://supabase.com/docs/guides/cli) installed and linked):

```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxx
supabase secrets set INTERNAL_OTP_MAIL_SECRET=your-long-random-string
supabase secrets set OTP_FROM_EMAIL="Your App <noreply@your-verified-domain.com>"
supabase functions deploy send-password-reset-otp --no-verify-jwt
```

Use the same `INTERNAL_OTP_MAIL_SECRET` value when you store the Vault secret `otp_mail_internal_secret` (see `supabase_schema.sql` comments).

## Troubleshooting: email still contains a “click this link” reset

That message is from **Supabase Auth**, not this function. Common causes:

- Vault secret **`otp_mail_edge_url`** points at an **Auth** URL (e.g. `/auth/v1/...`) instead of **`.../functions/v1/send-password-reset-otp`**.
- Something still calls **`resetPasswordForEmail`** in client code (this repo now uses OTP RPC only).

Re-check the Vault URL and re-run the `request_password_reset_otp` function from `supabase_schema.sql` so the URL validation runs.

## Test

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-password-reset-otp" \
  -H "Content-Type: application/json" \
  -H "x-internal-secret: YOUR_INTERNAL_OTP_MAIL_SECRET" \
  -d '{"email":"you@example.com","otp":"123456"}'
```
