-- Terra Commerce POS: tables products and stock_logs have no shop_id/owner key.
-- The current production workers use products_v2 and stock_entries_v2, so legacy
-- client access is disabled rather than retaining an unsafe cross-shop policy.

alter table public.products enable row level security;
alter table public.stock_logs enable row level security;

drop policy if exists "public all" on public.products;
drop policy if exists "public all logs" on public.stock_logs;

revoke all on table public.products from anon, authenticated;
revoke all on table public.stock_logs from anon, authenticated;
