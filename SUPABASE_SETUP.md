# Supabase Setup Guide

Follow these steps to connect your Flutter app to Supabase:

## Step 1: Create a Supabase Project

1. Go to [https://supabase.com](https://supabase.com)
2. Sign up or log in
3. Click "New Project"
4. Fill in:
   - **Project Name**: ML Smart Expense Tracker (or any name)
   - **Database Password**: Choose a strong password (save it!)
   - **Region**: Choose closest to you
5. Click "Create new project"
6. Wait 2-3 minutes for project to be created

## Step 2: Get Your Supabase Credentials

1. In your Supabase dashboard, go to **Settings** → **API**
2. You'll see:
   - **Project URL**: `https://xxxxx.supabase.co`
   - **anon/public key**: A long string starting with `eyJ...`
3. Copy both values

## Step 3: Set Up Database Tables

1. In Supabase dashboard, go to **SQL Editor**
2. Click "New query"
3. Copy and paste the entire contents of `supabase_schema.sql`
4. Click "Run" (or press Ctrl+Enter)
5. You should see "Success. No rows returned"

## Step 4: Enable Authentication Providers (Optional)

### Email/Password (Already enabled by default)
- Go to **Authentication** → **Providers**
- Email is enabled by default

### Google OAuth (Required for "Continue with Google" feature)

**Step 1: Create Google OAuth Credentials**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Google+ API**:
   - Go to **APIs & Services** → **Library**
   - Search for "Google+ API" or "Google Identity"
   - Click **Enable**
4. Create OAuth 2.0 credentials:
   - Go to **APIs & Services** → **Credentials**
   - Click **Create Credentials** → **OAuth client ID**
   - If prompted, configure the OAuth consent screen:
     - Choose **External** (unless you have a Google Workspace)
     - Fill in app name, user support email, developer contact
     - Add scopes: `email`, `profile`, `openid`
     - Add test users if needed (for testing)
   - Application type: Choose **Web application**
   - Name: "ML Smart Expense Tracker" (or any name)
   - Authorized redirect URIs: Add these URLs:
     ```
     https://wqprcibamipkzjstkuaj.supabase.co/auth/v1/callback
     io.supabase.flutter://login-callback
     ```
   - Click **Create**
   - **IMPORTANT**: Copy the **Client ID** and **Client Secret** (you'll need these)

**Step 2: Enable Google Provider in Supabase**

1. Go to your Supabase dashboard: [https://supabase.com/dashboard](https://supabase.com/dashboard)
2. Select your project
3. Go to **Authentication** → **Providers**
4. Find **Google** in the list
5. Click the toggle to **Enable** Google provider
6. Enter your credentials:
   - **Client ID (for OAuth)**: Paste the Client ID from Google Cloud Console
   - **Client Secret (for OAuth)**: Paste the Client Secret from Google Cloud Console
7. **Redirect URL**: Should already be set to:
   ```
   https://wqprcibamipkzjstkuaj.supabase.co/auth/v1/callback
   ```
8. Click **Save**

**Step 3: Verify Configuration**

- The Google provider should now show as **Enabled** (green toggle)
- Make sure both redirect URLs are configured:
  - In Google Cloud Console: `https://wqprcibamipkzjstkuaj.supabase.co/auth/v1/callback`
  - In Supabase: Should be automatically set

**Troubleshooting Google OAuth:**

- **"Unsupported provider: provider is not enabled"**
  - ✅ Make sure Google provider is enabled in Supabase dashboard
  - ✅ Check that Client ID and Client Secret are correct
  - ✅ Verify redirect URLs match exactly

- **"redirect_uri_mismatch" error**
  - ✅ Ensure redirect URL in Google Cloud Console matches: `https://wqprcibamipkzjstkuaj.supabase.co/auth/v1/callback`
  - ✅ The redirect URL format must be exact (no trailing slashes)

- **"Access blocked: This app's request is invalid"**
  - ✅ Configure OAuth consent screen in Google Cloud Console
  - ✅ Add your email as a test user if app is in testing mode

## Step 5: Update Your Flutter App

1. Open `lib/main.dart`
2. Replace the placeholder values:
   ```dart
   await Supabase.initialize(
     url: 'https://your-project-id.supabase.co',  // Your Project URL
     anonKey: 'your-anon-key-here',                // Your anon key
   );
   ```

## Step 6: Test the Connection

Run your app and:
1. Try to sign up with email/password
2. Add an expense
3. Check Supabase dashboard → **Table Editor** → **expenses** to see your data

## Password reset OTP email (optional)

The app can email a 6-digit reset code using a Supabase Edge Function and Resend.

1. Run `supabase_schema.sql` (includes `password_resets` and RPCs).
2. Enable the **pg_net** extension (Dashboard → **Database** → **Extensions**).
3. Deploy the function and set secrets: see `supabase/functions/send-password-reset-otp/README.md`.
4. In the SQL Editor, store the function URL and shared secret in Vault (same secret as `INTERNAL_OTP_MAIL_SECRET`):

   ```sql
   select vault.create_secret('https://YOUR_REF.supabase.co/functions/v1/send-password-reset-otp', 'otp_mail_edge_url');
   select vault.create_secret('your-long-random-string', 'otp_mail_internal_secret');
   ```

5. Re-run the `create or replace function public.request_password_reset_otp` block from `supabase_schema.sql` if you already applied an older version without email.

**If the email still shows a reset link:** `otp_mail_edge_url` must be **`https://YOUR_REF.supabase.co/functions/v1/send-password-reset-otp`**, not any `/auth/v1/` URL. The latter triggers Supabase’s built-in link email.

## Troubleshooting

### "Invalid API key" error
- Double-check you copied the **anon key** (not service_role key)
- Make sure there are no extra spaces

### "Failed to connect" error
- Check your internet connection
- Verify the Project URL is correct
- Make sure Supabase project is active (not paused)

### Data not syncing
- Check if RLS policies are set up correctly
- Verify user is authenticated (check `auth.currentUser`)
- Check browser console or Flutter logs for errors

## Security Notes

- ✅ The **anon key** is safe to use in client apps
- ❌ Never expose the **service_role key** in client code
- ✅ RLS policies protect your data automatically
- ✅ Each user can only see their own data

## Next Steps

After setup:
1. Test authentication (sign up/login)
2. Test adding expenses
3. Test offline mode (add expense offline, then go online)
4. Check data appears in Supabase dashboard

## Step 7: Storage Setup (for Profile Images)

To enable profile picture syncing across devices:

1. Go to **Storage** in your Supabase dashboard
2. Click **"New bucket"**
3. Create a bucket named: `profile-images`
4. Make it **Public** (so images can be accessed via URL)
5. Click **Create bucket**

### Set up Storage Policies

Go to **Storage** → **Policies** → `profile-images` and add these policies:

**Policy 1: Allow authenticated users to upload profile images**
```sql
CREATE POLICY "Users can upload own profile images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile-images' AND
  (storage.foldername(name))[1] = 'profiles'
);
```

**Policy 2: Allow anyone to view profile images (public bucket)**
```sql
CREATE POLICY "Anyone can view profile images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'profile-images');
```

**Policy 3: Allow users to update their own profile images**
```sql
CREATE POLICY "Users can update own profile images"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'profile-images');
```

**Policy 4: Allow users to delete their own profile images**
```sql
CREATE POLICY "Users can delete own profile images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'profile-images');
```

**Note:** After creating the bucket and policies, users will be able to upload profile pictures that sync across all their devices!














