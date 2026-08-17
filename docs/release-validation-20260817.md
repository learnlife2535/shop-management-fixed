# Terra Commerce POS — Release Validation

**Validation date:** 17 August 2026

## Scope validated

The production Worker `terra-pos-point` was updated and the live entry point loaded the release cache version `20260817-1948-accounting-hotfix`. The live unauthenticated screen displayed normally after the final hotfix.

The JavaScript bundle passed both a Node syntax check and a Babel parse before the accounting release was deployed. The Terra POS Point marketing website also passed `tsc --noEmit` and a production build.

## Multi-store authorization regression check

The following tables have RLS enabled and policies that rely on shop membership: commercial-document settings, documents, document lines, print profiles and events, employee profiles, benefits, attendance, employee document records, payroll periods/runs/line items, chart of accounts, journal entries/lines, expenses, and tax-return drafts.

## Workflow constraints confirmed

| Workflow | Confirmed database control |
| --- | --- |
| Attendance | Check-in and check-out methods are restricted to `button`; one record per shop, employee, and work date; checkout cannot precede check-in. |
| Commercial documents | Document type and lifecycle status are constrained; number uniqueness is scoped by shop, type, and number. |
| Payroll | Pay cycles are constrained to days 7 and 22; periods cannot end before they start; lifecycle statuses are constrained. |
| Journal lines | A line must be exactly debit or credit, never both; line numbers are unique inside an entry. |
| Tax drafts | Allowed form types and review/export lifecycle statuses are constrained; period records are unique per store and form. |

## Remaining acceptance tests with real shop data

1. An owner should create a staff account and verify that the staff member only sees the permitted store scope.
2. A staff member should perform one check-in and one check-out on a test date, then confirm that a second open shift is rejected.
3. An owner or manager should create a trade-document draft, expense draft, and payroll period, then verify translations and print rendering on the intended thermal/A4/Bluetooth hardware.
4. Before exporting or filing any tax or social-security document, a qualified Thai accountant or tax professional must review the inputs, calculations, document format, and deadlines.

> This release prepares internal records and review workflows. It does not submit information to the Revenue Department or the Social Security Office and must not be relied upon as filing advice.
