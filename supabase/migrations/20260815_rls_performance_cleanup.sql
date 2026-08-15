-- RLS performance and safety cleanup for unified Terra app.
-- The old public-all policy on sales was a permissive test policy and must not remain.

drop policy if exists "public all sales" on public.sales;

alter policy profiles_select_self on public.profiles
  using (user_id = (select auth.uid()));
alter policy profiles_update_self on public.profiles
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
alter policy members_select_self_or_manager on public.shop_members
  using ((user_id = (select auth.uid())) or private.is_shop_member(shop_id, array['owner','manager']));
alter policy employees_select_self_or_manager on public.employees_v2
  using ((auth_user_id = (select auth.uid())) or private.is_shop_member(shop_id, array['owner','manager']));
