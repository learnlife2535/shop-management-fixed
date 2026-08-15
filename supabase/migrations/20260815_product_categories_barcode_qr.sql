-- Terra Commerce POS: product categories, barcode uniqueness, and QR-first payment support
-- Safe rollout: keeps legacy PromptPay fields nullable for backward compatibility.

create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name_th text,
  name_en text,
  name_my text,
  name_lo text,
  slug text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_categories_name_present check (
    coalesce(btrim(name_th), '') <> ''
    or coalesce(btrim(name_en), '') <> ''
    or coalesce(btrim(name_my), '') <> ''
    or coalesce(btrim(name_lo), '') <> ''
  )
);

create unique index if not exists product_categories_shop_slug_uidx
  on public.product_categories (shop_id, slug);

create index if not exists product_categories_shop_created_idx
  on public.product_categories (shop_id, created_at desc);

create index if not exists products_v2_shop_category_idx
  on public.products_v2 (shop_id, category_id);

create unique index if not exists products_v2_shop_barcode_uidx
  on public.products_v2 (shop_id, btrim(barcode))
  where barcode is not null and btrim(barcode) <> '';

alter table public.product_categories enable row level security;

drop policy if exists product_categories_select_member on public.product_categories;
drop policy if exists product_categories_insert_manager on public.product_categories;
drop policy if exists product_categories_update_manager on public.product_categories;
drop policy if exists product_categories_delete_manager on public.product_categories;

create policy product_categories_select_member
  on public.product_categories
  for select to authenticated
  using (private.is_shop_member(shop_id));

create policy product_categories_insert_manager
  on public.product_categories
  for insert to authenticated
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

create policy product_categories_update_manager
  on public.product_categories
  for update to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

create policy product_categories_delete_manager
  on public.product_categories
  for delete to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']));

grant select on public.product_categories to authenticated;
grant insert, update, delete on public.product_categories to authenticated;
