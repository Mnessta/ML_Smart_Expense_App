# Supabase OTP Email Setup Script
# Run from repo root: pwsh -File scripts/setup_otp_email.ps1

$ErrorActionPreference = "Stop"

Write-Host "================================" -ForegroundColor Cyan
Write-Host "Supabase OTP Email Setup Script" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check .env file
Write-Host "[1/5] Checking .env file..." -ForegroundColor Yellow
$envFile = ".env"
if (-not (Test-Path $envFile)) {
  Write-Host "ERROR: .env file not found. Copy .env.example to .env first." -ForegroundColor Red
  exit 1
}

# Extract SUPABASE_URL from .env
$supabaseUrl = $null
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^\s*SUPABASE_URL\s*=\s*(.+)\s*$') {
    $supabaseUrl = $Matches[1].Trim().Trim('"')
  }
}

if ([string]::IsNullOrWhiteSpace($supabaseUrl)) {
  Write-Host "ERROR: SUPABASE_URL not found in .env" -ForegroundColor Red
  exit 1
}

Write-Host "✓ Found SUPABASE_URL: $supabaseUrl" -ForegroundColor Green
Write-Host ""

# Step 2: Ask for secrets
Write-Host "[2/5] Gathering secrets..." -ForegroundColor Yellow
Write-Host "You will need:" -ForegroundColor Cyan
Write-Host "  - Resend API key (from https://resend.com/api-keys)"
Write-Host "  - Email domain (e.g., noreply@your-domain.com)"
Write-Host ""

$resendApiKey = Read-Host "Enter your Resend API key"
if ([string]::IsNullOrWhiteSpace($resendApiKey)) {
  Write-Host "ERROR: Resend API key cannot be empty" -ForegroundColor Red
  exit 1
}

$otpFromEmail = Read-Host "Enter the sender email (e.g., 'ML Smart Expense <noreply@your-domain.com>')"
if ([string]::IsNullOrWhiteSpace($otpFromEmail)) {
  $otpFromEmail = "ML Smart Expense <onboarding@resend.dev>"
}

# Generate a random internal secret
$internalSecret = ((1..32 | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) }) -join '')
Write-Host "✓ Generated INTERNAL_OTP_MAIL_SECRET" -ForegroundColor Green
Write-Host ""

# Step 3: Deploy Edge Function
Write-Host "[3/5] Deploying send-password-reset-otp Edge Function..." -ForegroundColor Yellow
try {
  supabase functions deploy send-password-reset-otp --no-verify-jwt
  Write-Host "✓ Edge Function deployed successfully" -ForegroundColor Green
} catch {
  Write-Host "ERROR: Failed to deploy Edge Function" -ForegroundColor Red
  Write-Host $_.Exception.Message
  exit 1
}
Write-Host ""

# Step 4: Set secrets
Write-Host "[4/5] Setting function secrets..." -ForegroundColor Yellow

Write-Host "  Setting RESEND_API_KEY..." -ForegroundColor Cyan
supabase secrets set RESEND_API_KEY=$resendApiKey

Write-Host "  Setting OTP_FROM_EMAIL..." -ForegroundColor Cyan
supabase secrets set OTP_FROM_EMAIL="$otpFromEmail"

Write-Host "  Setting INTERNAL_OTP_MAIL_SECRET..." -ForegroundColor Cyan
supabase secrets set INTERNAL_OTP_MAIL_SECRET=$internalSecret

Write-Host "✓ All function secrets set" -ForegroundColor Green
Write-Host ""

# Step 5: Display next steps
Write-Host "[5/5] Next manual steps in Supabase Dashboard..." -ForegroundColor Yellow
Write-Host ""
Write-Host "Go to: Supabase Dashboard → SQL Editor" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Enable pg_net extension:" -ForegroundColor Cyan
Write-Host @"
create extension if not exists pg_net;
"@ -ForegroundColor White

Write-Host "2. Add Vault secrets:" -ForegroundColor Cyan
$vaultSecret1 = @"
select vault.create_secret(
  '$($supabaseUrl.TrimEnd('/'))/functions/v1/send-password-reset-otp',
  'otp_mail_edge_url'
);
"@
Write-Host $vaultSecret1 -ForegroundColor White

$vaultSecret2 = @"
select vault.create_secret(
  '$internalSecret',
  'otp_mail_internal_secret'
);
"@
Write-Host $vaultSecret2 -ForegroundColor White

Write-Host "3. Re-run the request_password_reset_otp function:" -ForegroundColor Cyan
Write-Host "   Copy the entire 'create or replace function public.request_password_reset_otp...' block from supabase_schema.sql and run it." -ForegroundColor White
Write-Host ""

Write-Host "================================" -ForegroundColor Green
Write-Host "Setup almost complete!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "After you run the SQL steps above in Supabase Dashboard:" -ForegroundColor Cyan
Write-Host "  - Test the 'Forgot Password?' flow in the app" -ForegroundColor White
Write-Host "  - You should receive a 6-digit OTP email" -ForegroundColor White
Write-Host ""
Write-Host "Your Internal Secret (save this for reference):" -ForegroundColor Yellow
Write-Host $internalSecret -ForegroundColor White
Write-Host ""
