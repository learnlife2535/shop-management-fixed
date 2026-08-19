-- Terra Commerce POS: employee certificate, employment confirmation, and payroll slip support.
-- Documents are generated from HR/payroll data and recorded as auditable print events.

alter table public.employee_profiles
  add column if not exists job_title text;

alter table public.shop_settings_v2
  add column if not exists hr_authorized_signatory text,
  add column if not exists hr_authorized_title text;

create table if not exists public.employee_generated_documents (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  employee_id bigint not null references public.employees_v2(id) on delete restrict,
  payroll_run_id uuid references public.payroll_runs(id) on delete set null,
  document_type text not null check (document_type in (
    'salary_certificate',
    'employment_certificate',
    'employee_status_confirmation',
    'payslip'
  )),
  issue_date date not null default current_date,
  document_snapshot jsonb not null default '{}'::jsonb,
  generated_by uuid references auth.users(id) on delete set null,
  printed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists employee_generated_documents_shop_employee_idx
  on public.employee_generated_documents (shop_id, employee_id, created_at desc);

alter table public.employee_generated_documents enable row level security;

drop policy if exists employee_generated_documents_select_member on public.employee_generated_documents;
drop policy if exists employee_generated_documents_manage_manager on public.employee_generated_documents;

create policy employee_generated_documents_select_member
  on public.employee_generated_documents for select to authenticated
  using (private.is_shop_member(shop_id));

create policy employee_generated_documents_manage_manager
  on public.employee_generated_documents for all to authenticated
  using (private.is_shop_member(shop_id, array['owner', 'manager']))
  with check (private.is_shop_member(shop_id, array['owner', 'manager']));

grant select, insert, update on public.employee_generated_documents to authenticated;
