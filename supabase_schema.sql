-- Supabase SQL Schema for ML Smart Expense Tracker
-- Run this in Supabase SQL Editor

-- Enable UUID extension
create extension if not exists "pgcrypto";

-- HTTP from Postgres (queue email to Edge Function). Enable in Dashboard → Database → Extensions if needed.
create extension if not exists pg_net;

-- Expenses table
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,                 -- supabase auth user id
  amount numeric not null,
  category text not null,
  payment text,
  note text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  synced boolean default true   -- server rows are synced
);

-- Budgets table
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  category text not null,
  limit_amount numeric not null,
  period_start date not null,
  period_end date not null,
  created_at timestamptz default now()
);

-- Finance table for dashboard values
create table public.finance (
  id integer primary key default 1,
  balance numeric not null default 0,
  daily_spending numeric not null default 0,
  savings numeric not null default 0,
  user_id uuid, -- Optional: can be null for global finance or linked to user
  updated_at timestamptz default now()
);

-- Create indexes for better query performance
create index idx_expenses_user_id on public.expenses(user_id);
create index idx_expenses_created_at on public.expenses(created_at);
create index idx_budgets_user_id on public.budgets(user_id);
create index idx_finance_user_id on public.finance(user_id);

-- Enable Row Level Security (RLS)
alter table public.expenses enable row level security;
alter table public.budgets enable row level security;
alter table public.finance enable row level security;

-- RLS Policies for expenses
-- Allow users to see only their own expenses
create policy "Users can view own expenses"
  on public.expenses for select
  using (auth.uid() = user_id);

-- Allow users to insert their own expenses
create policy "Users can insert own expenses"
  on public.expenses for insert
  with check (auth.uid() = user_id);

-- Allow users to update their own expenses
create policy "Users can update own expenses"
  on public.expenses for update
  using (auth.uid() = user_id);

-- Allow users to delete their own expenses
create policy "Users can delete own expenses"
  on public.expenses for delete
  using (auth.uid() = user_id);

-- RLS Policies for budgets
-- Allow users to see only their own budgets
create policy "Users can view own budgets"
  on public.budgets for select
  using (auth.uid() = user_id);

-- Allow users to insert their own budgets
create policy "Users can insert own budgets"
  on public.budgets for insert
  with check (auth.uid() = user_id);

-- Allow users to update their own budgets
create policy "Users can update own budgets"
  on public.budgets for update
  using (auth.uid() = user_id);

-- Allow users to delete their own budgets
create policy "Users can delete own budgets"
  on public.budgets for delete
  using (auth.uid() = user_id);

-- RLS Policies for finance
-- Allow authenticated users to view finance data
create policy "Users can view finance"
  on public.finance for select
  using (true);

-- Allow authenticated users to insert finance data
create policy "Users can insert finance"
  on public.finance for insert
  with check (true);

-- Allow authenticated users to update finance data
create policy "Users can update finance"
  on public.finance for update
  using (true);

-- Password reset OTP table
create table if not exists public.password_resets (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  otp_hash text not null,
  expires_at timestamptz not null,
  used boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_password_resets_email on public.password_resets(email);
create index if not exists idx_password_resets_expires_at on public.password_resets(expires_at);

alter table public.password_resets enable row level security;

-- Keep this table server-only. Access it through SECURITY DEFINER RPC functions.
drop policy if exists "No direct access to password_resets" on public.password_resets;
create policy "No direct access to password_resets"
  on public.password_resets
  for all
  using (false)
  with check (false);

create or replace function public.request_password_reset_otp(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_otp text;
  v_edge_url text;
  v_internal_secret text;
begin
  if p_email is null or btrim(p_email) = '' then
    raise exception 'Email is required.';
  end if;

  if not exists (select 1 from auth.users where email = lower(btrim(p_email))) then
    raise exception 'No account found for this email.';
  end if;

  v_otp := lpad((floor(random() * 1000000))::int::text, 6, '0');

  update public.password_resets
    set used = true
    where email = lower(btrim(p_email)) and used = false;

  insert into public.password_resets (email, otp_hash, expires_at, used)
  values (
    lower(btrim(p_email)),
    crypt(v_otp, gen_salt('bf')),
    now() + interval '10 minutes',
    false
  );

  -- Deliver OTP by email via Edge Function + Resend (see supabase/functions/send-password-reset-otp).
  -- 1) Deploy function and set secrets (RESEND_API_KEY, INTERNAL_OTP_MAIL_SECRET, OTP_FROM_EMAIL).
  -- 2) Store matching URL + secret in Vault (SQL Editor), e.g.:
  --    select vault.create_secret('https://YOUR_REF.supabase.co/functions/v1/send-password-reset-otp', 'otp_mail_edge_url');
  --    select vault.create_secret('same-value-as-INTERNAL_OTP_MAIL_SECRET', 'otp_mail_internal_secret');
  -- 3) Enable extension "pg_net" (Database → Extensions).
  begin
    select ds.decrypted_secret into v_edge_url
    from vault.decrypted_secrets ds
    where ds.name = 'otp_mail_edge_url'
    limit 1;

    select ds.decrypted_secret into v_internal_secret
    from vault.decrypted_secrets ds
    where ds.name = 'otp_mail_internal_secret'
    limit 1;

    if v_edge_url is null
       or length(btrim(v_edge_url)) = 0
       or v_internal_secret is null
       or length(btrim(v_internal_secret)) = 0 then
      raise exception 'OTP email delivery is not configured. Add Vault secrets otp_mail_edge_url + otp_mail_internal_secret and deploy send-password-reset-otp.';
    end if;

    -- Wrong URL (e.g. /auth/v1/recover) triggers Supabase Auth's link-based reset email, not our OTP.
    if position('/auth/v1/' in lower(btrim(v_edge_url))) > 0 then
      raise exception
        'otp_mail_edge_url must be your Edge Function (.../functions/v1/send-password-reset-otp), not an Auth API URL.';
    end if;
    if position('/functions/v1/' in lower(btrim(v_edge_url))) = 0 then
      raise exception
        'otp_mail_edge_url must include /functions/v1/ (deploy send-password-reset-otp first).';
    end if;

    perform net.http_post(
      url := btrim(v_edge_url),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-internal-secret', btrim(v_internal_secret)
      ),
      body := jsonb_build_object(
        'email', lower(btrim(p_email)),
        'otp', v_otp
      )
    );

    return jsonb_build_object('success', true, 'message', 'OTP sent.');
  exception
    when undefined_table then
      raise exception 'OTP email delivery is not configured: install pg_net and deploy send-password-reset-otp.';
    when undefined_function then
      raise exception 'OTP email delivery is not configured: install pg_net and deploy send-password-reset-otp.';
  end;
end;
$$;

create or replace function public.verify_password_reset_otp(p_email text, p_otp text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.password_resets%rowtype;
begin
  select *
  into v_row
  from public.password_resets
  where email = lower(btrim(p_email))
    and used = false
  order by created_at desc
  limit 1;

  if v_row.id is null then
    return jsonb_build_object('success', false, 'verified', false, 'message', 'No OTP found.');
  end if;

  if v_row.expires_at < now() then
    return jsonb_build_object('success', false, 'verified', false, 'message', 'OTP expired.');
  end if;

  if crypt(p_otp, v_row.otp_hash) <> v_row.otp_hash then
    return jsonb_build_object('success', false, 'verified', false, 'message', 'Invalid OTP.');
  end if;

  return jsonb_build_object('success', true, 'verified', true);
end;
$$;

create or replace function public.reset_password_with_otp(
  p_email text,
  p_otp text,
  p_new_password text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.password_resets%rowtype;
begin
  select *
  into v_row
  from public.password_resets
  where email = lower(btrim(p_email))
    and used = false
  order by created_at desc
  limit 1;

  if v_row.id is null then
    raise exception 'No active OTP found.';
  end if;

  if v_row.expires_at < now() then
    raise exception 'OTP expired.';
  end if;

  if crypt(p_otp, v_row.otp_hash) <> v_row.otp_hash then
    raise exception 'Invalid OTP.';
  end if;

  if p_new_password is null or length(p_new_password) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  update auth.users
    set encrypted_password = crypt(p_new_password, gen_salt('bf')),
        updated_at = now()
    where email = lower(btrim(p_email));

  update public.password_resets
    set used = true
    where id = v_row.id;

  return jsonb_build_object('success', true, 'message', 'Password reset successful.');
end;
$$;

grant execute on function public.request_password_reset_otp(text) to anon, authenticated;
grant execute on function public.verify_password_reset_otp(text, text) to anon, authenticated;
grant execute on function public.reset_password_with_otp(text, text, text) to anon, authenticated;









