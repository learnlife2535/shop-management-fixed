-- Terra unified security hardening
-- Keep tenant RLS behavior while removing exposed SECURITY DEFINER helpers.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create or replace function private.is_shop_member(
  target_shop_id uuid,
  allowed_roles text[] default array['owner', 'manager', 'staff', 'viewer']
)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select exists (
    select 1
    from public.shop_members sm
    where sm.shop_id = target_shop_id
      and sm.user_id = auth.uid()
      and sm.role = any(allowed_roles)
  );
$$;

grant execute on function private.is_shop_member(uuid, text[]) to authenticated;

create or replace function private.shop_id_from_storage_path(path text)
returns uuid
language plpgsql
stable
security definer
set search_path = public, private
as $$
begin
  return split_part(path, '/', 1)::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

grant execute on function private.shop_id_from_storage_path(text) to authenticated;

-- Repoint all public-schema policies that used the exposed helper.
do $$
declare
  p record;
  expression text;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and (coalesce(qual, '') like '%is_shop_member%' or coalesce(with_check, '') like '%is_shop_member%')
  loop
    if p.qual is not null then
      expression := replace(p.qual, 'is_shop_member', 'private.is_shop_member');
      execute format('alter policy %I on public.%I using (%s)', p.policyname, p.tablename, expression);
    end if;
    if p.with_check is not null then
      expression := replace(p.with_check, 'is_shop_member', 'private.is_shop_member');
      execute format('alter policy %I on public.%I with check (%s)', p.policyname, p.tablename, expression);
    end if;
  end loop;
end;
$$;

-- Storage policies are outside public schema and are recreated explicitly.
drop policy if exists terra_payment_slips_select_member on storage.objects;
drop policy if exists terra_payment_slips_insert_member on storage.objects;
drop policy if exists terra_payment_slips_delete_manager on storage.objects;
create policy terra_payment_slips_select_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'payment-slips'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name))
  );
create policy terra_payment_slips_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'payment-slips'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name), array['owner','manager','staff'])
  );
create policy terra_payment_slips_delete_manager on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'payment-slips'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name), array['owner','manager'])
  );

-- The new transaction RPC uses normal invoker privileges plus explicit RLS policies.
drop policy if exists sales_insert_staff_unified on public.sales;
drop policy if exists sale_items_insert_staff_unified on public.sale_items_v2;
drop policy if exists stock_entries_insert_staff_unified on public.stock_entries_v2;
create policy sales_insert_staff_unified on public.sales
  for insert to authenticated
  with check (private.is_shop_member(shop_id, array['owner','manager','staff']));
create policy sale_items_insert_staff_unified on public.sale_items_v2
  for insert to authenticated
  with check (private.is_shop_member(shop_id, array['owner','manager','staff']));
create policy stock_entries_insert_staff_unified on public.stock_entries_v2
  for insert to authenticated
  with check (private.is_shop_member(shop_id, array['owner','manager','staff']));

create or replace function public.complete_sale_with_payment(
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
  p_slip_size bigint default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, private
as $$
declare
  new_sale_id bigint;
  item jsonb;
  product_row record;
  item_product_id bigint;
  item_quantity integer;
  item_price numeric;
  expected_change numeric;
begin
  if not private.is_shop_member(p_shop_id, array['owner', 'manager', 'staff']) then
    raise exception 'not_authorized';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'empty_cart';
  end if;
  if p_total is null or p_total < 0 then
    raise exception 'invalid_total';
  end if;
  if p_paid_amount is null or p_paid_amount < p_total then
    raise exception 'invalid_paid_amount';
  end if;
  expected_change := round((p_paid_amount - p_total)::numeric, 2);
  if p_change_amount is null or p_change_amount < 0 or round(p_change_amount::numeric, 2) <> expected_change then
    raise exception 'invalid_change_amount';
  end if;
  if p_payment_method not in ('cash', 'qr', 'bank_transfer') then
    raise exception 'invalid_payment_method';
  end if;
  if p_slip_path is null or btrim(p_slip_path) = '' then
    raise exception 'slip_required';
  end if;
  if split_part(p_slip_path, '/', 1) <> p_shop_id::text then
    raise exception 'invalid_slip_path';
  end if;
  if not exists (
    select 1 from storage.objects so
    where so.bucket_id = 'payment-slips' and so.name = p_slip_path
  ) then
    raise exception 'slip_not_found';
  end if;

  insert into public.sales (
    shop_id, sale_number, total, payment_method, employee_name, status,
    paid_amount, change_amount, payment_account, slip_path, slip_filename,
    slip_mime, slip_size, currency, created_at, updated_at
  ) values (
    p_shop_id, p_sale_number, p_total, p_payment_method, p_employee_name, 'completed',
    p_paid_amount, p_change_amount, p_payment_account, p_slip_path, p_slip_filename,
    p_slip_mime, p_slip_size, 'THB', now(), now()
  ) returning id into new_sale_id;

  for item in select value from jsonb_array_elements(p_items) loop
    item_product_id := (item ->> 'product_id')::bigint;
    item_quantity := (item ->> 'quantity')::integer;
    item_price := (item ->> 'price')::numeric;
    if item_quantity is null or item_quantity <= 0 or item_price is null or item_price < 0 then
      raise exception 'invalid_item';
    end if;

    select id, stock into product_row
    from public.products_v2
    where id = item_product_id and shop_id = p_shop_id
    for update;
    if not found then
      raise exception 'product_not_found';
    end if;
    if coalesce(product_row.stock, 0) < item_quantity then
      raise exception 'insufficient_stock';
    end if;

    insert into public.sale_items_v2 (shop_id, sale_id, product_id, quantity, price)
    values (p_shop_id, new_sale_id, item_product_id, item_quantity, item_price);
    update public.products_v2
    set stock = stock - item_quantity, updated_at = now()
    where id = item_product_id and shop_id = p_shop_id;
    insert into public.stock_entries_v2 (shop_id, product_id, quantity, type, note)
    values (p_shop_id, item_product_id, -item_quantity, 'out', 'sale ' || p_sale_number);
  end loop;

  return jsonb_build_object('id', new_sale_id, 'sale_number', p_sale_number, 'paid_amount', p_paid_amount, 'change_amount', p_change_amount, 'slip_path', p_slip_path);
end;
$$;

grant execute on function public.complete_sale_with_payment(uuid, text, numeric, text, text, jsonb, numeric, numeric, text, text, text, text, bigint) to authenticated;

-- The old public helpers remain for backward compatibility of the fallback app,
-- but cannot be invoked through the signed-in REST role.
revoke all on function public.is_shop_member(uuid, text[]) from public, anon, authenticated;
revoke all on function public.shop_id_from_storage_path(text) from public, anon, authenticated;
