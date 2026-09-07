# APPYRA / DALEVENTAS PHASE 2 DESIGN SPEC

Status: Design only  
Date: 2026-09-06  
Scope: Appyra -> DaleVentas / FullPOS Cloud commercial plans, sales funnel, license control, CRM-lite, and reporting architecture.

Commercial source of truth: current public FullPOS Cloud website, `https://fullposcloud.fulltechrd.com`.  
Owner decisions confirmed: trial is 7 days, minimum activation/billing is 3 months, CRM/marketing data lives in Appyra, and technical license/entitlement enforcement remains in DaleVentas.

## 1. Final Funnel Model

Appyra DaleVentas must evolve from a license-control page into a lightweight commercial funnel plus licensing control system.

Target funnel:

1. Demo created
2. Contacted
3. Interested
4. Purchased
5. Active customer
6. Renewal due
7. Expired or lost

This funnel is commercial. It must not decide technical access by itself.

Recommended operator-facing groups:

- `DEMO_NUEVA`: trial started recently.
- `DEMO_POR_VENCER`: trial active and ending soon.
- `DEMO_VENCIDA_SIN_COMPRA`: trial expired and no purchase.
- `INTERESADO`: lead requires sales follow-up.
- `CLIENTE_ACTIVO`: purchased and license is active.
- `POR_RENOVAR`: paid active license near expiration.
- `VENCIDO`: paid license expired; renewal opportunity.
- `PERDIDO`: commercial opportunity closed/lost.

## 2. Commercial Status Model

Commercial status is a sales/marketing lifecycle field.

Recommended stable values:

- `DEMO`
- `CONTACTED`
- `INTERESTED`
- `PURCHASED`
- `ACTIVE_CUSTOMER`
- `RENEWAL_DUE`
- `LOST`

Display names:

- Demo
- Contactado
- Interesado
- Compro
- Cliente activo
- Renovacion
- Perdido

Commercial status examples:

- `commercialStatus = INTERESTED`, `licenseStatus = TRIAL`
- `commercialStatus = ACTIVE_CUSTOMER`, `licenseStatus = ACTIVE`
- `commercialStatus = RENEWAL_DUE`, `licenseStatus = ACTIVE`
- `commercialStatus = LOST`, `licenseStatus = EXPIRED`

## 3. License Status Separation

License status remains the technical authorization state.

Current DaleVentas source fields:

- `Company.licenseStatus`: `TRIAL`, `ACTIVE`, `BLOCKED`, `EXPIRED`
- `Company.status`: company operational status, currently used with license checks
- `User.blocked`: individual user auth block

Rules:

- Do not use `User.blocked` for the `Bloqueados` license filter.
- Do not use `commercialStatus` to grant or deny access.
- Do not mark a customer as blocked commercially when only one user is blocked.
- Technical access must continue to be resolved from license/company authorization logic.

## 4. Exact BASIC / BUSINESS / PRO Plan Architecture

The DaleVentas / FullPOS Cloud commercial catalog must use the three public plans from `https://fullposcloud.fulltechrd.com`.

| Code | Display name | Monthly equivalent | Minimum billing months | Minimum payment |
| --- | --- | ---: | ---: | ---: |
| `BASIC` | Básico | RD$1,000 | 3 | RD$3,000 |
| `BUSINESS` | Negocio | RD$1,500 | 3 | RD$4,500 |
| `PRO` | Pro | RD$2,500 | 3 | RD$7,500 |

Do not introduce `Professional` or `Enterprise` as DaleVentas commercial plan names. `ENTERPRISE` can remain as legacy/current DaleVentas code during migration only, but it should not be the new catalog identity.

Plan definitions must be editable later, but changing the catalog must not rewrite historical customer snapshots.

The public website does not currently publish exact product, user, warehouse, or device limits per plan. Do not invent those limits in code or migrations. They must be configurable in Appyra before enforcement is expanded.

## 5. Catalog Plan Schema

Recommended catalog entity: `commercial_plans` or an Appyra-compatible extension of `product_plans`.

Fields:

- `id`
- `projectId`
- `code`: `BASIC`, `BUSINESS`, `PRO`
- `displayName`: Básico, Negocio, Pro
- `description`
- `monthlyEquivalentPrice`
- `currency`: `DOP`
- `minimumBillingMonths`: default `3`
- `minimumPayment`
- `maxProducts`
- `maxUsers`
- `maxWarehouses`
- `maxDevices`, nullable until device limits are adopted
- `active`
- `sortOrder`
- `metadata`
- `createdAt`
- `updatedAt`

The first seed/configuration must match the published prices and 7-day trial policy. Entitlement limits are intentionally configurable because they are not published on the source-of-truth website.

## 6. License Snapshot Schema

Each customer license/commercial contract should store a plan reference plus immutable commercial snapshot. The snapshot records what the customer bought at assignment/conversion time.

Recommended fields on DaleVentas customer-license record or related contract table:

- `planId`
- `planCodeSnapshot`
- `planNameSnapshot`
- `currencySnapshot`
- `monthlyEquivalentPriceSnapshot`
- `minimumBillingMonthsSnapshot`
- `minimumPaymentSnapshot`
- `contractValueSnapshot`
- `maxProductsSnapshot`
- `maxUsersSnapshot`
- `maxWarehousesSnapshot`
- `maxDevicesSnapshot`
- `planAssignedAt`
- `convertedAt`
- `assignedBy`

Snapshots protect historical contracts when catalog prices or limits change.

## 7. Override Schema

Manual exceptions must be per customer, not global plan edits.

Recommended override fields:

- `overrideMaxUsers`
- `overrideMaxProducts`
- `overrideMaxWarehouses`
- `overrideMaxDevices`
- `overrideExpirationDate`
- `overrideAdditionalDays`
- `overrideNotes`
- `overrideReason`
- `overrideUpdatedAt`
- `overrideUpdatedBy`

Alternative for audit-heavy history: store overrides in a `license_entitlement_overrides` table with one row per change and keep the current effective override materialized on the customer/license record.

The administrator must be able to change an individual customer expiration date, extra days, max users, max products, max warehouses, future max devices, and notes without modifying the global `BASIC`, `BUSINESS`, or `PRO` plan definition.

## 8. Effective Entitlement Resolution

Effective limits must be resolved from:

BASE PLAN
+
CUSTOMER SNAPSHOT
+
CUSTOMER OVERRIDES
=
EFFECTIVE ENTITLEMENTS

Resolution order:

1. Per-customer override
2. Customer plan snapshot
3. Existing legacy DaleVentas fields
4. Conservative system default

Conceptually:

- effective users = override users, else snapshot users, else legacy `maxUsers`
- effective products = override products, else snapshot products, else legacy `maxProducts`
- effective warehouses = override warehouses, else snapshot warehouses, else null/not enforced
- effective devices = override devices, else snapshot devices, else null/not enforced

The UI must show both included and effective values.

Technical enforcement remains in DaleVentas. Appyra owns the commercial configuration and operator workflow; DaleVentas remains authoritative for access checks and runtime entitlement enforcement.

## 9. Demo-to-Purchase Flow

Target flow:

1. Customer creates account.
2. DaleVentas creates trial.
3. Customer appears in Appyra under Demo funnel.
4. Sales records source, contact, interest, notes, next follow-up.
5. Customer purchases.
6. Admin assigns `BASIC`, `BUSINESS`, or `PRO`.
7. Admin explicitly activates or renews the paid license.
8. Customer appears as active customer.

Plan assignment and license activation are distinct backend operations. A future UI may combine them into one guided workflow, but the API/audit trail should keep separate events.

Plan assignment must not automatically activate, block, extend, or expire a license.

## 10. Renewal Flow

Renewal should support:

- Paid license active and approaching expiration.
- Customer appears in `Por vencer` and `Renovacion`.
- Operator contacts customer and records follow-up.
- Payment is recorded when payment tracking is authoritative.
- Admin extends paid license days or sets a new expiration.
- Snapshot stays unchanged unless the plan is explicitly changed.
- Plan changes and license renewal/extension remain separate and auditable.

Business decisions required before implementation:

- Immediate upgrade or next-renewal upgrade.
- Downgrade timing.
- Proration policy.
- Whether renewal preserves old price snapshot or creates a new contract snapshot.

## 11. Filtering Architecture

Primary top-level filters:

- `Todos`: all DaleVentas companies visible to Appyra.
- `Demo`: companies currently in trial.
- `Compraron`: customers with a paid plan assignment or conversion date.
- `Activos`: paid customers whose technical license is active.
- `Por vencer`: active paid licenses expiring within configurable window.
- `Vencidos`: expired technical licenses.
- `Bloqueados`: `licenseStatus = BLOCKED` only.
- `Seguimiento`: `nextFollowUpAt` due or overdue.

Secondary filters:

- Plan: Básico, Negocio, Pro, Legacy/Custom.
- Expiration: Hoy, 7 dias, 15 dias, 30 dias.
- Commercial status: Demo, Contactado, Interesado, Compro, Renovacion, Perdido.
- Lead source: Web, WhatsApp, Facebook, Instagram, Referido, Directo, Otro.

Filters must be combinable. Default implementation should be server-side once fields exist. Client-side filtering is acceptable only as an interim small-data view.

## 12. CRM / Marketing Fields

CRM and marketing data live in Appyra.

Minimal useful CRM fields:

- `leadSource`: `WEB`, `WHATSAPP`, `FACEBOOK`, `INSTAGRAM`, `REFERRAL`, `DIRECT`, `OTHER`
- `commercialStatus`
- `demoStartedAt`
- `demoEndsAt`
- `firstContactAt`
- `lastContactAt`
- `nextFollowUpAt`
- `assignedTo`
- `commercialNotes`
- `lostReason`
- `convertedAt`

Optional flexible tags:

- Necesita llamada
- Sin respuesta
- Interesado
- Renovar
- WhatsApp
- Referido

Use tags only if they stay simple: text array or small tag table scoped to Appyra/DaleVentas, not a large CRM subsystem.

## 13. Dashboard Model

DaleVentas summary cards:

- Demos activas
- Demos por vencer
- Demos vencidas sin compra
- Clientes activos
- Por renovar
- Vencidos
- Bloqueados
- Seguimientos para hoy

Plan distribution:

- Básico
- Negocio
- Pro
- Legacy/Custom

Marketing source distribution:

- Web
- WhatsApp
- Facebook
- Instagram
- Referidos
- Other

Conversion metrics, only when data exists:

- Demos creadas
- Demos convertidas
- Tasa de conversion
- Tiempo promedio a conversion

Revenue labels:

- Monthly equivalent value
- 3-month contract value
- Actual payment received

Do not label monthly equivalent value as actual monthly cash revenue.

## 14. List View Specification

Future desktop list columns:

- Cliente / Empresa
- Plan
- Etapa comercial
- Licencia
- Vence
- Proximo seguimiento
- Acciones

Compact indicators:

- Productos
- Usuarios

The list should be scannable. Important sales and license status must be visible without opening each customer.

## 15. Customer Detail Specification

Sections:

- Customer: company, owner/contact, phone/email where appropriate, lead source.
- Sales funnel: commercial status, last contact, next follow-up, assigned salesperson, notes, lost reason.
- Plan: purchased plan, monthly equivalent, minimum billing months, 3-month payment, assigned date.
- Effective limits: included and effective products/users/warehouses/devices with override indicators.
- License: license status, trial start/end, activation date, expiration, license key where appropriate, notes.
- Actions: assign/change plan, customize limits, extend days, activate, renew/extend, block, reactivate, delete.

Destructive actions must remain visually separated.

## 16. Manual Customization UX

Add a distinct future action: `Customize customer`.

This action modifies only the selected customer overrides. It must not edit `BASIC`, `BUSINESS`, or `PRO`.

Examples:

- +30 days
- +1 user
- +100 products
- +1 warehouse
- Custom expiration date

UI must show:

- What the customer bought.
- What the plan includes.
- What the customer effectively has.
- Which values are customized.

## 17. Audit Logging Model

Significant actions:

- `DEMO_STARTED`
- `PLAN_ASSIGNED`
- `PLAN_CHANGED`
- `LIMIT_OVERRIDE_CHANGED`
- `LICENSE_ACTIVATED`
- `LICENSE_EXTENDED`
- `LICENSE_BLOCKED`
- `LICENSE_REACTIVATED`
- `COMMERCIAL_STATUS_CHANGED`
- `FOLLOW_UP_CHANGED`

Capture:

- admin
- timestamp
- old value
- new value
- company/customer
- reason/note

Use existing DaleVentas `CompanyLicenseAuditLog` where appropriate for DaleVentas license events. Appyra may need a corresponding commercial audit table only if CRM/funnel data is stored in Appyra instead of DaleVentas.

Because CRM/marketing data is confirmed to live in Appyra, Appyra needs its own commercial audit trail for commercial-status, follow-up, assignment, source, and notes changes. DaleVentas should continue to audit technical license actions.

## 18. Existing Customer Migration Strategy

Do not automatically map existing DaleVentas customers to `BASIC`, `BUSINESS`, or `PRO` based only on current limits.

Preferred migration:

1. Existing customer becomes `LEGACY` or `CUSTOM`.
2. Preserve `maxUsers`.
3. Preserve `maxProducts`.
4. Preserve expiration.
5. Preserve `licenseStatus`.
6. Preserve license key.
7. Preserve notes and audit history.
8. Admin may later manually assign a commercial plan.

Requirement: zero unexpected access changes.

## 19. Database Indexes Needed

Recommended indexes once fields exist:

- `projectId, planCode`
- `projectId, commercialStatus`
- `projectId, licenseStatus`
- `projectId, licenseExpiresAt`
- `projectId, trialEndsAt`
- `projectId, nextFollowUpAt`
- `projectId, leadSource`
- `projectId, convertedAt`
- `companyId`
- `customerId`

For Appyra bridge/list APIs, prefer compound indexes that match common filters:

- `licenseStatus + licenseExpiresAt`
- `commercialStatus + nextFollowUpAt`
- `planCode + licenseStatus`

## 20. API Changes Required

Future Appyra/DaleVentas API capabilities:

- List companies with server-side primary and secondary filters.
- Get company commercial/license detail.
- List plan catalog for DaleVentas.
- Create/update/activate/deactivate plan catalog entries.
- Assign plan to customer without activating license.
- Activate paid license.
- Renew/extend paid license.
- Extend demo.
- Change commercial status.
- Set follow-up fields.
- Customize customer limits.
- Block/reactivate license.
- Return audit history.
- Return dashboard aggregates.

API responses must expose both:

- base plan/snapshot entitlements
- effective entitlements after overrides

## 21. Final Trial Policy

Final confirmed policy:

- Trial duration: 7 days.
- Public website source of truth currently publishes 7 days.
- DaleVentas backend behavior previously found 7 days.
- Minimum activation/billing: 3 months.

There is no remaining trial-duration conflict for Phase 2 design. Implementation must align Appyra configuration, Appyra UI copy, and DaleVentas trial behavior to 7 days without changing runtime behavior until the implementation phase is explicitly approved.

Recommendation: Appyra should store the commercial trial policy as configuration for DaleVentas, while DaleVentas remains the runtime enforcement authority.

## 22. Exact Implementation Phases

Phase 2A: Confirm source of truth

- Source of truth confirmed: current public FullPOS Cloud website.
- Plan prices confirmed: `BASIC`, `BUSINESS`, `PRO` as listed in this spec.
- Trial duration confirmed: 7 days.
- CRM location confirmed: Appyra.
- Technical enforcement confirmed: DaleVentas.
- Remaining setup decision: initial configurable entitlement values for products/users/warehouses/devices.
- GO/NO-GO gate before schema work.

Phase 2B: Database foundation

- Add Appyra plan catalog, customer plan snapshot, override, commercial funnel, CRM, and commercial audit fields/tables.
- Add indexes.
- No access behavior changes.
- Rollback: reversible migrations or additive nullable fields.

Phase 2C: Backward-compatible migration

- Backfill existing customers as `LEGACY/CUSTOM`.
- Preserve all current access fields.
- No automatic BASIC/BUSINESS/PRO inference.

Phase 2D: API foundation

- Add read APIs for plans, detail, filters, dashboard aggregates.
- Add write APIs for plan assignment, commercial status, follow-up, overrides.
- Keep license activation/renewal explicit.
- Bridge technical license actions to DaleVentas without mixing them with Appyra commercial updates.

Phase 2E: Appyra UI

- Add funnel filters, secondary filters, list columns, detail sections, customize customer workflow.
- Show override indicators.
- Separate destructive actions.

Phase 2F: Audit and reporting

- Ensure all required actions log before/after.
- Add dashboard cards and conversion metrics only from real fields.

Phase 2G: Entitlement enforcement

- Only after owner approval and DaleVentas API support.
- Start with already enforced users/products.
- Warehouses/devices require explicit policy, schema support, and tests.

Phase 2H: UAT and rollout

- Test on non-production data or safe production snapshot.
- Verify existing customers remain operational.
- Deploy with rollback plan.

## 23. Rollback Strategy

- Keep Phase 2 schema additive where possible.
- Do not remove existing DaleVentas `Company.plan`, `licenseStatus`, `maxUsers`, `maxProducts`, or expiration fields in Phase 2.
- Feature-flag new Appyra filters/UI if deployed before data is complete.
- If a migration fails, leave old license behavior untouched.
- If a UI release fails, roll back Appyra frontend without changing DaleVentas license data.
- Never couple rollback to destructive customer/license deletes.

## 24. Tests Required

Required before implementation GO:

- Existing active customer remains active after migration.
- Existing expired customer remains expired.
- Existing blocked license remains blocked.
- Blocked user with active license still returns user-blocked, not license-blocked.
- Trial customer appears in Demo.
- Paid active customer appears in Compraron and Activos.
- Active paid customer near expiration appears in Por vencer.
- Expired paid customer appears in Vencidos.
- License blocked customer appears in Bloqueados only by license status.
- Due follow-up appears in Seguimiento.
- Plan assignment does not activate license by itself.
- License activation does not silently change commercial status unless explicitly designed.
- Plan catalog edit does not rewrite customer snapshot.
- Customer override changes effective limits without changing catalog plan.
- Audit log records old/new values for plan, overrides, license actions, commercial status, and follow-up.
- Dashboard aggregates match fixture data.
- Server-side filters combine correctly.

## 25. GO / NO-GO For Implementation

Design specification update: GO.

Implementation: NO-GO until these owner decisions are confirmed:

- Final entitlement limits for `BASIC`, `BUSINESS`, and `PRO`.
- Payment source of truth for actual payments received.
- Upgrade/downgrade/proration behavior.
- Whether warehouse/device limits will be technically enforced.

Implementation can begin after final entitlement defaults and rollout details are confirmed. The implementation must remain backward compatible and must not change existing customer access during schema foundation or backfill.

CODE MODIFIED: NO  
DATABASE MODIFIED: NO  
PRODUCTION DEPLOYED: NO
