-- Public QR assets are payment destination information, not payment evidence.
-- Keep uploads tenant-scoped while allowing the POS to render the QR image.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'shop-assets',
  'shop-assets',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp']::text[]
)
on conflict (id) do update set
  name = excluded.name,
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists terra_shop_assets_insert_member on storage.objects;
drop policy if exists terra_shop_assets_update_manager on storage.objects;
drop policy if exists terra_shop_assets_delete_manager on storage.objects;
create policy terra_shop_assets_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'shop-assets'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name), array['owner','manager'])
  );
create policy terra_shop_assets_update_manager on storage.objects
  for update to authenticated
  using (
    bucket_id = 'shop-assets'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name), array['owner','manager'])
  )
  with check (
    bucket_id = 'shop-assets'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name), array['owner','manager'])
  );
create policy terra_shop_assets_delete_manager on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'shop-assets'
    and private.shop_id_from_storage_path(name) is not null
    and private.is_shop_member(private.shop_id_from_storage_path(name), array['owner','manager'])
  );
