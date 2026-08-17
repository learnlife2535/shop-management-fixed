# Regulatory Source Notes — Terra Commerce POS

## Thailand VAT and commercial tax-invoice design

The Revenue Department states that a VAT registrant must issue a tax invoice when the tax point arises. The official requirements include prominent tax-invoice wording, issuer name/address/taxpayer ID, purchaser name/address, serial number, goods or services description/quantity/value, separately shown VAT, and issue date. The system therefore stores issuer, customer, document-number, line-item, VAT-rate, VAT-amount, and review status fields. It does **not** assert e-Tax Invoice compliance or submit documents electronically.

Source: [Thailand Revenue Department, Revenue Code Section 85/86](https://www.rd.go.th/english/37741.html).

The Revenue Department also describes VAT registration and monthly VAT-return context. Tax-sensitive workflows must remain review-first and must not be treated as filing automation.

Source: [Thailand Revenue Department, Value Added Tax](https://www.rd.go.th/english/6043.html).

## Payroll withholding and statutory forms

The Revenue Department publishes P.N.D.1 and its attachment as withholding-income-tax forms. Terra Commerce POS therefore stores payroll and tax-return data as drafts, snapshots, and reviewed/export states rather than automatically calculating or filing an official return.

Source: [Thailand Revenue Department, Withholding Tax forms](https://www.rd.go.th/english/42379.html).
