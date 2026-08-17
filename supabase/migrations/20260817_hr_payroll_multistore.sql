-- Terra Commerce POS: multi-store HR, button-based attendance, payroll drafts,
-- benefits and employee-document expiry tracking. Statutory calculations remain
-- reviewable inputs/snapshots and are not tax filing automation.

create table if not exists public.employee_profiles (
  employee_id bigint primary key references public.employees_v2(id) on delete cascade,
  shop_id uuid not null references public.shops(id) on delete cascade,
  first_name_th text,
  last_name_th text,
  first_name_en text,
  last_name_en text,
  phone text,
  personal_email text,
  address text,
  nationality text,
  birth_date date,
  photo_path text,
  employment_start_date date,
  employment_end_date date,
  employment_status text not null default 'active' check (employment_status in ('active', 'inactive', 'on_leave', 'terminated')),
  employment_type text not null default 'monthly' check (employment_type in ('monthly', 'daily', 'hourly', 'contract')),
  base_monthly_salary numeric(14,2) not null default 0 check (base_monthly_salary >= 0),
  pay_cycle_days smallint[] not null default array[7, 22]::smallint[] check (pay_cycle_days <@ array[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31]::smallint[]),
  social_security_section text default '33' check (social_security_section in ('33', '39', '40', 'none')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_profiles_shop_employee_key unique (shop_id, employee_id),
  constraint employee_profiles_dates_check check (employment_end_date is null or employment_start_date is null or employment_end_date >= employment_start_date)
);

create table if not exists public.employee_benefits (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id bigint not null references public.employees_v2(id) on delete cascade,
  benefit_type text not null check (benefit_type in ('allowance', 'meal', 'transport', 'housing', 'commission', 'health', 'other')),
  description text,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  frequency text not null default 'monthly' check (frequency in ('monthly', 'per_payroll', 'one_time')),
  effective_from date not null default current_date,
  effective_to date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_benefits_dates_check check (effective_to is null or effective_to >= effective_from)
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id bigint not null references public.employees_v2(id) on delete cascade,
  work_date date not null default current_date,
  check_in_at timestamptz,
  check_out_at timestamptz,
  check_in_method text not null default 'button' check (check_in_method = 'button'),
  check_out_method text check (check_out_method is null or check_out_method = 'button'),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_records_one_open_shift_key unique (shop_id, employee_id, work_date),
  constraint attendance_records_sequence_check check (check_out_at is null or check_in_at is null or check_out_at >= check_in_at)
);

create table if not exists public.employee_document_records (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id bigint not null references public.employees_v2(id) on delete cascade,
  document_type text not null check (document_type in ('passport', 'work_permit', 'mou', 'visa', 'contract', 'other')),
  document_number text,
  issued_date date,
  expiry_date date,
  alert_days_before integer not null default 60 check (alert_days_before between 1 and 365),
  file_path text,
  verified_at timestamptz,
  verified_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employee_document_records_dates_check check (expiry_date is null or issued_date is null or expiry_date >= issued_date),
  constraint employee_document_records_shop_employee_type_number_key unique nulls not distinct (shop_id, employee_id, document_type, document_number)
);

create table if not exists public.payroll_periods (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  pay_cycle_day smallint not null check (pay_cycle_day in (7, 22)),
  status text not null default 'draft' check (status in ('draft', 'reviewed', 'approved', 'paid', 'locked')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_periods_dates_check check (period_end >= period_start),
  constraint payroll_periods_shop_cycle_pay_date_key unique (shop_id, pay_cycle_day, pay_date)
);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  payroll_period_id uuid not null references public.payroll_periods(id) on delete cascade,
  employee_id bigint not null references public.employees_v2(id) on delete restrict,
  gross_base_pay numeric(14,2) not null default 0 check (gross_base_pay >= 0),
  income_total numeric(14,2) not null default 0 check (income_total >= 0),
  deduction_total numeric(14,2) not null default 0 check (deduction_total >= 0),
  social_security_employee numeric(14,2) not null default 0 check (social_security_employee >= 0),
  social_security_employer numeric(14,2) not null default 0 check (social_security_employer >= 0),
  withholding_tax numeric(14,2) not null default 0 check (withholding_tax >= 0),
  net_pay numeric(14,2) not null default 0 check (net_pay >= 0),
  calculation_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft', 'reviewed', 'approved', 'paid', 'void')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payroll_runs_period_employee_key unique (payroll_period_id, employee_id)
);

create table if not exists public.payroll_line_items (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  payroll_run_id uuid not null references public.payroll_runs(id) on delete cascade,
  line_type text not null check (line_type in ('income', 'deduction', 'employer_contribution')),
  code text not null,
  label_th text,
  label_en text,
  label_my text,
  label_lo text,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists employee_profiles_shop_status_idx on public.employee_profiles (shop_id, employment_status, employment_start_date desc);
create index if not exists attendance_records_shop_date_idx on public.attendance_records (shop_id, work_date desc, employee_id);
create index if not exists employee_document_records_expiry_idx on public.employee_document_records (shop_id, expiry_date) where expiry_date is not null;
create index if not exists payroll_periods_shop_dates_idx on public.payroll_periods (shop_id, period_start desc, period_end desc);
create index if not exists payroll_runs_shop_period_idx on public.payroll_runs (shop_id, payroll_period_id, employee_id);
create index if not exists payroll_line_items_shop_run_idx on public.payroll_line_items (shop_id, payroll_run_id);

alter table public.employee_profiles enable row level security;
alter table public.employee_benefits enable row level security;
alter table public.attendance_records enable row level security;
alter table public.employee_document_records enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_runs enable row level security;
alter table public.payroll_line_items enable row level security;

-- Owner/manager can handle all HR records; staff members may only read their own
-- profile/benefits/documents/payroll and clock their own attendance using buttons.
drop policy if exists employee_profiles_select_authorized on public.employee_profiles;
drop policy if exists employee_profiles_write_manager on public.employee_profiles;
create policy employee_profiles_select_authorized on public.employee_profiles
  for select to authenticated using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = employee_profiles.shop_id)
  );
create policy employee_profiles_write_manager on public.employee_profiles
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists employee_benefits_select_authorized on public.employee_benefits;
drop policy if exists employee_benefits_write_manager on public.employee_benefits;
create policy employee_benefits_select_authorized on public.employee_benefits
  for select to authenticated using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = employee_benefits.shop_id)
  );
create policy employee_benefits_write_manager on public.employee_benefits
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists attendance_records_select_authorized on public.attendance_records;
drop policy if exists attendance_records_insert_self_or_manager on public.attendance_records;
drop policy if exists attendance_records_update_self_or_manager on public.attendance_records;
create policy attendance_records_select_authorized on public.attendance_records
  for select to authenticated using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = attendance_records.shop_id)
  );
create policy attendance_records_insert_self_or_manager on public.attendance_records
  for insert to authenticated with check (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = attendance_records.shop_id)
  );
create policy attendance_records_update_self_or_manager on public.attendance_records
  for update to authenticated
  using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = attendance_records.shop_id)
  )
  with check (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = attendance_records.shop_id)
  );

drop policy if exists employee_document_records_select_authorized on public.employee_document_records;
drop policy if exists employee_document_records_write_manager on public.employee_document_records;
create policy employee_document_records_select_authorized on public.employee_document_records
  for select to authenticated using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = employee_document_records.shop_id)
  );
create policy employee_document_records_write_manager on public.employee_document_records
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists payroll_periods_select_manager on public.payroll_periods;
drop policy if exists payroll_periods_write_manager on public.payroll_periods;
create policy payroll_periods_select_manager on public.payroll_periods
  for select to authenticated using (private.is_shop_member(shop_id, array['owner', 'manager']));
create policy payroll_periods_write_manager on public.payroll_periods
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists payroll_runs_select_authorized on public.payroll_runs;
drop policy if exists payroll_runs_write_manager on public.payroll_runs;
create policy payroll_runs_select_authorized on public.payroll_runs
  for select to authenticated using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (select 1 from public.employees_v2 e where e.id = employee_id and e.auth_user_id = auth.uid() and e.shop_id = payroll_runs.shop_id)
  );
create policy payroll_runs_write_manager on public.payroll_runs
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

drop policy if exists payroll_line_items_select_authorized on public.payroll_line_items;
drop policy if exists payroll_line_items_write_manager on public.payroll_line_items;
create policy payroll_line_items_select_authorized on public.payroll_line_items
  for select to authenticated using (
    private.is_shop_member(shop_id, array['owner', 'manager'])
    or exists (
      select 1
      from public.payroll_runs r
      join public.employees_v2 e on e.id = r.employee_id
      where r.id = payroll_run_id and e.auth_user_id = auth.uid() and r.shop_id = payroll_line_items.shop_id
    )
  );
create policy payroll_line_items_write_manager on public.payroll_line_items
  for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

grant select, insert, update, delete on public.employee_profiles to authenticated;
grant select, insert, update, delete on public.employee_benefits to authenticated;
grant select, insert, update on public.attendance_records to authenticated;
grant select, insert, update, delete on public.employee_document_records to authenticated;
grant select, insert, update, delete on public.payroll_periods to authenticated;
grant select, insert, update, delete on public.payroll_runs to authenticated;
grant select, insert, update, delete on public.payroll_line_items to authenticated;
