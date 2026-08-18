-- Terra Commerce POS: product types, stock movement history and payment attribution.
-- Sales and stock changes remain shop-scoped and validated server-side.

create table if not exists public.product_types (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name_th text,
  name_en text,
  name_my text,
  name_lo text,
  slug text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_types_name_present check (
    coalesce(btrim(name_th), '') <> ''
    or coalesce(btrim(name_en), '') <> ''
    or coalesce(btrim(name_my), '') <> ''
    or coalesce(btrim(name_lo), '') <> ''
  ),
  constraint product_types_shop_slug_key unique (shop_id, slug)
);

alter table public.product_types enable row level security;

drop policy if exists product_types_select_member on public.product_types;
drop policy if exists product_types_manage_manager on public.product_types;

create policy product_types_select_member
  on public.product_types for select to authenticated
  using (private.is_shop_member(shop_id));

create policy product_types_manage_manager
  on public.product_types for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

grant select, insert, update, delete on public.product_types to authenticated;

alter table public.products_v2
  add column if not exists product_type_id uuid references public.product_types(id) on delete set null;

create index if not exists products_v2_shop_product_type_idx
  on public.products_v2 (shop_id, product_type_id);

alter table public.stock_entries_v2
  add column if not exists movement_reason text,
  add column if not exists supplier_name text,
  add column if not exists unit_cost numeric(14,2),
  add column if not exists reference_number text,
  add column if not exists performed_by uuid references auth.users(id) on delete set null;

alter table public.stock_entries_v2
  drop constraint if exists stock_entries_v2_type_check;

alter table public.stock_entries_v2
  add constraint stock_entries_v2_type_check
  check (type in ('in', 'out', 'adjustment'));

alter table public.sales
  add column if not exists payer_name text,
  add column if not exists payment_reference text,
  add column if not exists payment_confirmed_at timestamptz;

create index if not exists sales_shop_payment_history_idx
  on public.sales (shop_id, created_at desc, payment_method);

create index if not exists stock_entries_v2_shop_history_idx
  on public.stock_entries_v2 (shop_id, created_at desc, type);

create or replace function public.adjust_stock(
  p_shop_id uuid,
  p_product_id bigint,
  p_quantity_delta integer,
  p_movement_type text,
  p_note text default null,
  p_supplier_name text default null,
  p_unit_cost numeric default null,
  p_reference_number text default null
)
returns integer
language plpgsql
set search_path = public, private
as $$
declare
  current_stock integer;
  new_stock integer;
begin
  if not private.is_shop_member(p_shop_id, array['owner', 'manager', 'staff']) then
    raise exception 'not_authorized';
  end if;

  if p_movement_type not in ('in', 'out', 'adjustment') then
    raise exception 'invalid_movement_type';
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    raise exception 'invalid_quantity';
  end if;

  if p_movement_type = 'in' and p_quantity_delta <= 0 then
    raise exception 'intake_requires_positive_quantity';
  end if;

  if p_movement_type = 'out' and p_quantity_delta >= 0 then
    raise exception 'deduction_requires_negative_quantity';
  end if;

  select stock into current_stock
  from public.products_v2
  where id = p_product_id and shop_id = p_shop_id
  for update;

  if not found then
    raise exception 'product_not_found';
  end if;

  new_stock := coalesce(current_stock, 0) + p_quantity_delta;
  if new_stock < 0 then
    raise exception 'insufficient_stock';
  end if;

  update public.products_v2
  set stock = new_stock, updated_at = now()
  where id = p_product_id and shop_id = p_shop_id;

  insert into public.stock_entries_v2 (
    shop_id, product_id, quantity, type, note, movement_reason,
    supplier_name, unit_cost, reference_number, performed_by
  ) values (
    p_shop_id, p_product_id, p_quantity_delta, p_movement_type, p_note,
    p_note, nullif(btrim(p_supplier_name), ''), p_unit_cost,
    nullif(btrim(p_reference_number), ''), auth.uid()
  );

  return new_stock;
end;
$$;

create or replace function public.complete_sale_with_payment_v2(
  p_shop_id uuid,
  p_sale_number text,
  p_total numeric,
  p_payment_method text,
  p_employee_name text,
  p_items jsonb,
  p_paid_amount numeric default null,
  p_change_amount numeric default null,
  p_payment_account text default null,
  p_slip_path text default null,
  p_slip_filename text default null,
  p_slip_mime text default null,
  p_slip_size bigint default null,
  p_payer_name text default null,
  p_payment_reference text default null
)
returns jsonb
language plpgsql
set search_path = public, private
as $$
declare
  sale_result jsonb;
  sale_id bigint;
begin
  sale_result := public.complete_sale_with_payment(
    p_shop_id, p_sale_number, p_total, p_payment_method, p_employee_name,
    p_items, p_paid_amount, p_change_amount, p_payment_account, p_slip_path,
    p_slip_filename, p_slip_mime, p_slip_size
  );

  sale_id := (sale_result ->> 'id')::bigint;
  update public.sales
  set
    payer_name = nullif(btrim(p_payer_name), ''),
    payment_reference = nullif(btrim(p_payment_reference), ''),
    payment_confirmed_at = now(),
    updated_at = now()
  where id = sale_id and shop_id = p_shop_id;

  return sale_result;
end;
$$;

grant execute on function public.adjust_stock(uuid, bigint, integer, text, text, text, numeric, text) to authenticated;
grant execute on function public.complete_sale_with_payment_v2(uuid, text, numeric, text, text, jsonb, numeric, numeric, text, text, text, text, bigint, text, text) to authenticated;
