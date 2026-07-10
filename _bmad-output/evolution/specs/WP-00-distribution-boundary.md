# WP-00 distribution-boundary decision record

Status: **provisional recommendation approved by product owner**

## What the repository supports today

- The app is a native macOS target with automatic code signing configured and bundle identifier `com.aeroshot`.
- No root software license was found in the indexed working copy.
- The product direction requires local-first operation, portable project files, and no mandatory account or upload.
- Customer interviews, willingness-to-pay evidence, support-cost estimates, dependency-license review, notarization/update cost, and entitlement design are not yet available.

## Reversible Phase 0 recommendation

Proceed architecturally as **paid signed distribution with source available**, while keeping capture, project, rendering, and export cores free of licensing checks and hosted-service dependencies. This is a product-architecture recommendation, not a legal license grant and not a final pricing decision.

Why this is the safest reversible boundary now:

- It permits testing a commercially credible signed Mac product without making cloud infrastructure mandatory.
- It preserves the option to move to open core or fully open source after dependency and customer evidence is gathered.
- It keeps entitlement and update infrastructure outside the local project/capture/rendering model.

## Options intentionally not selected yet

| Option | Upside | Evidence needed before selection |
|---|---|---|
| Fully open source | Maximum inspectability and contributor access | Sustainable signing/update/support model; dependency and contributor-governance review |
| Open core | Clear portable core with paid distribution/services | Exact core boundary, license compatibility, maintenance economics, user trust testing |
| Paid signed, source available | Fastest route to a supported native release while retaining inspectability | License text, update channel, purchase/entitlement UX, refund/support policy, willingness-to-pay |

## Hard boundaries regardless of decision

- No account is required for capture, editing, project reopen, or local export.
- Original media and editable project data remain user-owned and portable.
- Licensing checks do not enter capture, project schema, rendering, privacy review, or export correctness paths.
- Telemetry remains opt-in, aggregate, content-free, and non-blocking.
- A final license or price is not approved by this record.

## Approval record

On 2026-07-10, Owl approved this recommendation as the initial reversible boundary. Final license text and pricing remain later evidence-based decisions.
