-- Harden legacy RPCs after unified app cutover.
-- RLS policies and private.is_shop_member enforce the same tenant/role checks.

create or replace function public.add_stock(
  p_shop_id uuid,
  p_product_id bigint,
  p_quantity integer,
  p_note text default null
)
returns integer
language plpgsql
security invoker
set search_path = public, private
as $$
declare
  new_stock integer;
begin
  if not private.is_shop_member(p_shop_id, array['owner', 'manager', 'staff']) then
    raise exception 'not_authorized';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'invalid_quantity';
  end if;
  update public.products_v2
  set stock = stock + p_quantity, updated_at = now()
  where id = p_product_id and shop_id = p_shop_id
  returning stock into new_stock;
  if new_stock is null then
    raise exception 'product_not_found';
  end if;
  insert into public.stock_entries_v2 (shop_id, product_id, quantity, type, note)
  values (p_shop_id, p_product_id, p_quantity, 'in', p_note);
  return new_stock;
end;
$$;

grant execute on function public.add_stock(uuid, bigint, integer, text) to authenticated;

create or replace function public.complete_sale(
  p_shop_id uuid,
  p_sale_number text,
  p_total numeric,
  p_payment_method text,
  p_employee_name text,
  p_items jsonb
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
begin
  if not private.is_shop_member(p_shop_id, array['owner', 'manager', 'staff']) then
    raise exception 'not_authorized';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'empty_cart';
  end if;

  insert into public.sales (shop_id, sale_number, total, payment_method, employee_name, status)
  values (p_shop_id, p_sale_number, p_total, p_payment_method, p_employee_name, 'completed')
  returning id into new_sale_id;

  for item in select value from jsonb_array_elements(p_items) loop
    item_product_id := (item ->> 'product_id')::bigint;
    item_quantity := (item ->> 'quantity')::integer;
    item_price := (item ->> 'price')::numeric;
    if item_quantity is null or item_quantity <= 0 then
      raise exception 'invalid_quantity';
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

  return jsonb_build_object('id', new_sale_id, 'sale_number', p_sale_number);
end;
$$;

grant execute on function public.complete_sale(uuid, text, numeric, text, text, jsonb) to authenticated;
