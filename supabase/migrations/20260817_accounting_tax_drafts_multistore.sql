-- Terra Commerce POS: multi-store accounting foundation and review-first tax drafts.
-- These tables support internal bookkeeping and export preparation only. They do
-- not calculate statutory liabilities automatically or submit returns to agencies.

create table if not exists public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  account_code text not null,
  name_th text not null,
  name_en text,
  account_type text not null check (account_type in ('asset', 'liability', 'equity', 'income', 'expense')),
  parent_account_id uuid references public.chart_of_accounts(id) on delete restrict,
  active boolean not null default true,
  system_account boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chart_of_accounts_shop_code_key unique (shop_id, account_code)
);

create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  entry_number text not null,
  entry_date date not null default current_date,
  source_type text not null default 'manual' check (source_type in ('manual', 'sale', 'stock', 'expense', 'payroll', 'trade_document', 'tax_draft')),
  source_id text,
  description text,
  status text not null default 'draft' check (status in ('draft', 'reviewed', 'posted', 'void')),
  created_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint journal_entries_shop_number_key unique (shop_id, entry_number)
);

create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  journal_entry_id uuid not null references public.journal_entries(id) on delete cascade,
  account_id uuid not null references public.chart_of_accounts(id) on delete restrict,
  line_no integer not null check (line_no > 0),
  memo text,
  debit numeric(14,2) not null default 0 check (debit >= 0),
  credit numeric(14,2) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  constraint journal_lines_entry_line_key unique (journal_entry_id, line_no),
  constraint journal_lines_one_sided_check check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create table if not exists public.expense_records (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  expense_date date not null default current_date,
  category text not null,
  description text,
  amount numeric(14,2) not null check (amount >= 0),
  currency text not null default 'THB',
  payment_method text,
  vendor_name text,
  receipt_path text,
  journal_entry_id uuid references public.journal_entries(id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'reviewed', 'posted', 'void')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tax_return_drafts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  tax_form text not null check (tax_form in ('vat_pp30', 'pnd1', 'pnd1a', 'social_security_33')),
  period_start date not null,
  period_end date not null,
  due_date date,
  status text not null default 'draft' check (status in ('draft', 'reviewed', 'approved_for_export', 'exported', 'void')),
  totals_snapshot jsonb not null default '{}'::jsonb,
  source_snapshot jsonb not null default '{}'::jsonb,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  export_filename text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tax_return_drafts_dates_check check (period_end >= period_start),
  constraint tax_return_drafts_shop_form_period_key unique (shop_id, tax_form, period_start, period_end)
);

create index if not exists chart_of_accounts_shop_type_idx on public.chart_of_accounts (shop_id, account_type, account_code);
create index if not exists journal_entries_shop_date_idx on public.journal_entries (shop_id, entry_date desc, created_at desc);
create index if not exists journal_lines_shop_entry_idx on public.journal_lines (shop_id, journal_entry_id, line_no);
create index if not exists expense_records_shop_date_idx on public.expense_records (shop_id, expense_date desc, category);
create index if not exists tax_return_drafts_shop_period_idx on public.tax_return_drafts (shop_id, tax_form, period_start desc);

alter table public.chart_of_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;
alter table public.expense_records enable row level security;
alter table public.tax_return_drafts enable row level security;

drop policy if exists chart_of_accounts_manager_only on public.chart_of_accounts;
create policy chart_of_accounts_manager_only on public.chart_of_accounts
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists journal_entries_manager_only on public.journal_entries;
create policy journal_entries_manager_only on public.journal_entries
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists journal_lines_manager_only on public.journal_lines;
create policy journal_lines_manager_only on public.journal_lines
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists expense_records_manager_only on public.expense_records;
create policy expense_records_manager_only on public.expense_records
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists tax_return_drafts_manager_only on public.tax_return_drafts;
create policy tax_return_drafts_manager_only on public.tax_return_drafts
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

grant select, insert, update, delete on public.chart_of_accounts to authenticated;
grant select, insert, update, delete on public.journal_entries to authenticated;
grant select, insert, update, delete on public.journal_lines to authenticated;
grant select, insert, update, delete on public.expense_records to authenticated;
grant select, insert, update, delete on public.tax_return_drafts to authenticated;
