-- Terra Commerce POS: multi-store commercial documents and print configuration.
-- This schema stores business data and print audit records only. It does not claim
-- to produce a compliant e-Tax Invoice or submit any tax filing automatically.

create table if not exists public.trade_document_settings (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  legal_name text,
  tax_id text,
  branch_code text,
  vat_registered boolean not null default false,
  vat_rate numeric(5,2) not null default 0 check (vat_rate between 0 and 100),
  receipt_footer_th text,
  receipt_footer_en text,
  receipt_footer_my text,
  receipt_footer_lo text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trade_document_settings_tax_id_check check (
    tax_id is null or tax_id ~ '^[0-9]{13}$'
  )
);

create table if not exists public.trade_documents (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  document_type text not null check (document_type in (
    'goods_receipt', 'goods_issue', 'quotation', 'invoice', 'receipt', 'abbreviated_receipt'
  )),
  document_number text not null,
  status text not null default 'draft' check (status in ('draft', 'issued', 'cancelled', 'converted')),
  issue_date date not null default current_date,
  due_date date,
  reference_number text,
  source_sale_id bigint references public.sales(id) on delete set null,
  customer_name text,
  customer_tax_id text,
  customer_address text,
  currency text not null default 'THB',
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  discount_total numeric(14,2) not null default 0 check (discount_total >= 0),
  vat_rate numeric(5,2) not null default 0 check (vat_rate between 0 and 100),
  vat_amount numeric(14,2) not null default 0 check (vat_amount >= 0),
  grand_total numeric(14,2) not null default 0 check (grand_total >= 0),
  notes text,
  issued_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trade_documents_shop_type_number_key unique (shop_id, document_type, document_number),
  constraint trade_documents_customer_tax_id_check check (
    customer_tax_id is null or customer_tax_id ~ '^[0-9]{13}$'
  )
);

create table if not exists public.trade_document_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  document_id uuid not null references public.trade_documents(id) on delete cascade,
  product_id bigint references public.products_v2(id) on delete set null,
  line_no integer not null check (line_no > 0),
  description_th text,
  description_en text,
  description_my text,
  description_lo text,
  unit_label text,
  quantity numeric(14,3) not null default 0 check (quantity >= 0),
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  line_total numeric(14,2) not null default 0 check (line_total >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint trade_document_lines_document_line_key unique (document_id, line_no),
  constraint trade_document_lines_description_present check (
    coalesce(btrim(description_th), '') <> '' or coalesce(btrim(description_en), '') <> ''
  )
);

create table if not exists public.document_print_profiles (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null,
  paper_format text not null check (paper_format in ('thermal_58', 'thermal_80', 'a4_half', 'a4_full')),
  print_transport text not null default 'browser' check (print_transport in ('browser', 'bluetooth')),
  locale text not null default 'th' check (locale in ('th', 'en', 'my', 'lo')),
  is_default boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint document_print_profiles_shop_name_key unique (shop_id, name)
);

create unique index if not exists document_print_profiles_one_default_per_shop
  on public.document_print_profiles (shop_id)
  where is_default;

create table if not exists public.document_print_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  document_id uuid not null references public.trade_documents(id) on delete cascade,
  print_profile_id uuid references public.document_print_profiles(id) on delete set null,
  paper_format text not null check (paper_format in ('thermal_58', 'thermal_80', 'a4_half', 'a4_full')),
  print_transport text not null check (print_transport in ('browser', 'bluetooth')),
  requested_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists trade_documents_shop_issue_idx
  on public.trade_documents (shop_id, issue_date desc, created_at desc);
create index if not exists trade_documents_shop_type_status_idx
  on public.trade_documents (shop_id, document_type, status, created_at desc);
create index if not exists trade_document_lines_shop_document_idx
  on public.trade_document_lines (shop_id, document_id, line_no);
create index if not exists document_print_events_shop_document_idx
  on public.document_print_events (shop_id, document_id, created_at desc);

alter table public.trade_document_settings enable row level security;
alter table public.trade_documents enable row level security;
alter table public.trade_document_lines enable row level security;
alter table public.document_print_profiles enable row level security;
alter table public.document_print_events enable row level security;

drop policy if exists trade_document_settings_select_member on public.trade_document_settings;
drop policy if exists trade_document_settings_write_manager on public.trade_document_settings;
create policy trade_document_settings_select_member on public.trade_document_settings
  for select to authenticated using (private.is_shop_member(shop_id));
create policy trade_document_settings_write_manager on public.trade_document_settings
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists trade_documents_select_member on public.trade_documents;
drop policy if exists trade_documents_insert_staff_draft on public.trade_documents;
drop policy if exists trade_documents_update_staff_draft on public.trade_documents;
drop policy if exists trade_documents_update_manager on public.trade_documents;
drop policy if exists trade_documents_delete_manager on public.trade_documents;
create policy trade_documents_select_member on public.trade_documents
  for select to authenticated using (private.is_shop_member(shop_id));
create policy trade_documents_insert_staff_draft on public.trade_documents
  for insert to authenticated
  with check (status = 'draft' and private.is_shop_member(shop_id, array['owner', 'manager', 'staff']));
create policy trade_documents_update_staff_draft on public.trade_documents
  for update to authenticated
  using (status = 'draft' and private.is_shop_member(shop_id, array['owner', 'manager', 'staff']))
  with check (status = 'draft' and private.is_shop_member(shop_id, array['owner', 'manager', 'staff']));
create policy trade_documents_update_manager on public.trade_documents
  for update to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));
create policy trade_documents_delete_manager on public.trade_documents
  for delete to authenticated using (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists trade_document_lines_select_member on public.trade_document_lines;
drop policy if exists trade_document_lines_write_staff on public.trade_document_lines;
drop policy if exists trade_document_lines_delete_manager on public.trade_document_lines;
create policy trade_document_lines_select_member on public.trade_document_lines
  for select to authenticated using (private.is_shop_member(shop_id));
create policy trade_document_lines_write_staff on public.trade_document_lines
  for insert to authenticated with check (private.is_shop_member(shop_id, array['owner', 'manager', 'staff']));
create policy trade_document_lines_update_staff on public.trade_document_lines
  for update to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager', 'staff']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager', 'staff']));
create policy trade_document_lines_delete_manager on public.trade_document_lines
  for delete to authenticated using (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists document_print_profiles_select_member on public.document_print_profiles;
drop policy if exists document_print_profiles_write_manager on public.document_print_profiles;
create policy document_print_profiles_select_member on public.document_print_profiles
  for select to authenticated using (private.is_shop_member(shop_id));
create policy document_print_profiles_write_manager on public.document_print_profiles
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists document_print_events_select_member on public.document_print_events;
drop policy if exists document_print_events_insert_member on public.document_print_events;
create policy document_print_events_select_member on public.document_print_events
  for select to authenticated using (private.is_shop_member(shop_id));
create policy document_print_events_insert_member on public.document_print_events
  for insert to authenticated with check (private.is_shop_member(shop_id, array['owner', 'manager', 'staff']));

grant select, insert, update, delete on public.trade_document_settings to authenticated;
grant select, insert, update, delete on public.trade_documents to authenticated;
grant select, insert, update, delete on public.trade_document_lines to authenticated;
grant select, insert, update, delete on public.document_print_profiles to authenticated;
grant select, insert on public.document_print_events to authenticated;
