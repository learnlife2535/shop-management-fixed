-- Terra Commerce POS: reviewable payroll withholding and social-security calculation settings.
-- This supports draft payroll calculations only; it does not submit any tax or social-security filing.

create table if not exists public.payroll_calculation_settings (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  effective_from date not null default date '2026-01-01',
  tax_expense_rate numeric(7,6) not null default 0.50 check (tax_expense_rate >= 0 and tax_expense_rate <= 1),
  tax_expense_cap numeric(14,2) not null default 100000 check (tax_expense_cap >= 0),
  personal_allowance numeric(14,2) not null default 60000 check (personal_allowance >= 0),
  tax_periods_per_year integer not null default 24 check (tax_periods_per_year between 1 and 366),
  social_security_rate numeric(7,6) not null default 0.05 check (social_security_rate >= 0 and social_security_rate <= 1),
  social_security_wage_ceiling numeric(14,2) not null default 17500 check (social_security_wage_ceiling >= 0),
  tax_brackets jsonb not null default '[
    {"up_to": 150000, "rate": 0},
    {"up_to": 300000, "rate": 0.05},
    {"up_to": 500000, "rate": 0.10},
    {"up_to": 750000, "rate": 0.15},
    {"up_to": 1000000, "rate": 0.20},
    {"up_to": 2000000, "rate": 0.25},
    {"up_to": 4000000, "rate": 0.30},
    {"up_to": null, "rate": 0.35}
  ]'::jsonb,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.payroll_tax_profiles (
  employee_id bigint primary key references public.employees_v2(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  annual_other_allowances numeric(14,2) not null default 0 check (annual_other_allowances >= 0),
  annual_estimated_extra_income numeric(14,2) not null default 0 check (annual_estimated_extra_income >= 0),
  social_security_enabled boolean not null default true,
  notes text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint payroll_tax_profiles_shop_employee_key unique (shop_id, employee_id)
);

create index if not exists payroll_tax_profiles_shop_idx on public.payroll_tax_profiles (shop_id, employee_id);

alter table public.payroll_calculation_settings enable row level security;
alter table public.payroll_tax_profiles enable row level security;

drop policy if exists payroll_calculation_settings_select_member on public.payroll_calculation_settings;
drop policy if exists payroll_calculation_settings_manage_manager on public.payroll_calculation_settings;
drop policy if exists payroll_tax_profiles_select_member on public.payroll_tax_profiles;
drop policy if exists payroll_tax_profiles_manage_manager on public.payroll_tax_profiles;

create policy payroll_calculation_settings_select_member
  on public.payroll_calculation_settings for select to authenticated
  using (private.is_shop_member(shop_id));

create policy payroll_calculation_settings_manage_manager
  on public.payroll_calculation_settings for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

create policy payroll_tax_profiles_select_member
  on public.payroll_tax_profiles for select to authenticated
  using (private.is_shop_member(shop_id));

create policy payroll_tax_profiles_manage_manager
  on public.payroll_tax_profiles for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

grant select, insert, update on public.payroll_calculation_settings to authenticated;
grant select, insert, update on public.payroll_tax_profiles to authenticated;
