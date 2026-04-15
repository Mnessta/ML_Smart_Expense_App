Write-Host "=== Supabase OTP Email Setup ===" -ForegroundColor Cyan

# Ask for inputs
$resendApiKey = Read-Host "Enter your Resend API Key"
$senderEmail = Read-Host "Enter your sender email (e.g. noreply@example.com)"

# Generate random secret
$internalSecret = [guid]::NewGuid().ToString()

Write-Host ""
Write-Host "Saving to .env file..." -ForegroundColor Yellow

# Create or update .env
$envPath = ".env"

if (Test-Path $envPath) {
    Add-Content $envPath "`nRESEND_API_KEY=$resendApiKey"
    Add-Content $envPath "SENDER_EMAIL=$senderEmail"
    Add-Content $envPath "INTERNAL_SECRET=$internalSecret"
} else {
    @"
RESEND_API_KEY=$resendApiKey
SENDER_EMAIL=$senderEmail
INTERNAL_SECRET=$internalSecret
"@ | Out-File -Encoding UTF8 $envPath
}

Write-Host "Done saving .env file!" -ForegroundColor Green

# Show SQL instructions
Write-Host ""
Write-Host "=== NEXT STEP (DO THIS IN SUPABASE SQL EDITOR) ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "1. Enable pg_net extension:"
Write-Host "create extension if not exists pg_net;"

Write-Host ""
Write-Host "2. Add secrets to Vault (replace values):"
Write-Host "select vault.create_secret('RESEND_API_KEY', '$resendApiKey');"
Write-Host "select vault.create_secret('SENDER_EMAIL', '$senderEmail');"
Write-Host "select vault.create_secret('INTERNAL_SECRET', '$internalSecret');"

Write-Host ""
Write-Host "3. Run your OTP SQL function (from supabase_schema.sql)"

Write-Host ""
Write-Host "=== SETUP COMPLETE ===" -ForegroundColor Green