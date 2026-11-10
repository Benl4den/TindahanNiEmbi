# TindaSari PH — project status

- Last reviewed: **2026-11-10** (Asia/Manila)
- Baseline: `main` at `89bba3c` (2026-10-14), plus the uncommitted work described below.
- Purpose: the starting point for future work, feature tracking, and recommendations.

## How to read this file

- **Present** means a working implementation exists in the repository; it does not promise every edge case is complete.
- **Partial / defect** means an implementation exists but has a verified gap.
- **Not implemented** means the specific capability is absent in the inspected code.
- **Recommendation** is a proposed next step, not an approved feature or product decision.
- **Source: code** means checked against the current repository. **Source: conversation** means discussed in this thread. Recheck both after later changes.

This initial review used the conversation available in this thread, the current files, tests, and Git history. It cannot recover requirements from separate chats that are not present here. Add any such requirements when they become available. The code and tests are the source of truth for implemented behavior; a conversation alone is not proof that something shipped.

## Current snapshot

- Flutter/Dart app with an Android project and local SQLite database at schema version 28 (`lib/database/app_database.dart`). No iOS or desktop project is in this repository.
- The Android UI supports both phones and tablets: the shell uses phone navigation below 900dp and a tablet sidebar at 900dp and above (`lib/features/shell/presentation/app_shell.dart`). Android-only describes the platform, not one device size. UI changes need checks at both widths when relevant.
- Main areas present: cash sales and transaction history; UTANG and customer accounts; GCash and Maya services; products, categories, stock, and restock; consignment and managed brands; supplier contacts; expenses and loans; reports and daily closing; owner/staff security and activity logs; backup/restore; Tindahan Profile. Source: `lib/features/` and corresponding repositories/services.
- The feature access layer defines Free/Pro boundaries and a development plan switch. Release builds currently grant Pro access through `OpenAccessPlanSource`; billing or a real entitlement source is absent (`lib/services/feature_access_service.dart`).
- The working tree contains uncommitted navigation and screen extraction work from the recent cleanup, plus a tablet Tindahan Profile navigation change already present in the user's tree. See **Work in the current tree**. Do not treat these as released or committed.
- Latest local verification: `flutter analyze --no-pub` found no issues, and the full `flutter test --no-pub --reporter compact` suite passed **318 tests** after the Tindahan Profile photo action and earlier fixes. These results cover the uncommitted working tree, not a release build.

## Requests traced from this conversation

| Discussion | Status at this review |
| --- | --- |
| Review the project and catch the owner up | Done in this thread; the findings are carried into the open-work table below. |
| Address behavioral findings before broad refactoring | SEC-01 and SEC-02 are resolved locally; integrity coverage remains open as DATA-01. |
| Refactor the largest screens | Partly done in the local cleanup through two dialog extractions; larger screens remain a recommendation, not a completed refactor. |
| Replace numeric navigation IDs | Done in the local, uncommitted navigation cleanup; confirm again after commit. |
| Show the store photo and name above tablet navigation with a smaller app brand header | Implemented locally in the expanded tablet sidebar; the collapsed rail stays compact and phone navigation is unchanged. |
| Make the Tindahan Profile camera badge work so an owner can set a store photo | Implemented locally. The profile photo opens camera/gallery choices and saves the selected photo directly; edit profile offers the same choices. Phone and tablet widget coverage passes. |
| Keep a project status, unimplemented-feature list, and future recommendations | This file establishes the baseline; `AGENTS.md` instructs future work to update it. |

No other explicit feature specification is visible in this thread. The open-work table also includes gaps found by code inspection; it does not imply the owner requested those features.

## Resolved in the current tree

| ID | Status | Change and evidence |
| --- | --- | --- |
| SEC-01 | Resolved locally, uncommitted | `InventoryRepository.adjust` now accepts only an explicit `OWNER` role; staff and missing roles cannot post a correction. The inventory menu shows **Correct Stock** only when the repository permits it. Repository and widget regression tests cover both boundaries (`lib/repositories/inventory_repository.dart`, `lib/features/inventory/presentation/inventory_screen.dart`, `test/repositories/inventory_repository_test.dart`, `test/features/inventory/inventory_plan_test.dart`). Full suite: 309 passed; analysis clean. |
| SEC-02 | Resolved locally, uncommitted | PIN retries and the 30-second lockout now live in the existing SQLite `app_settings` table and are updated in one transaction. Fresh `AuthService` instances, concurrent calls, and an app restart share the limit. The login screen reads the shared remaining count (`lib/services/auth_service.dart`, `lib/features/security/presentation/auth_gate.dart`, `test/services/auth_service_test.dart`). Full suite: 312 passed; analysis clean. |
| DATA-02 | Resolved locally, uncommitted | New backup format 2 includes the selected Tindahan Profile photo when its file exists, validates it, restores it under the destination device's `store_images` folder, and rewrites the saved path. Existing format 1 archives remain restorable; a missing legacy photo path is cleared. The backup screen reports photo inclusion (`lib/services/backup_service.dart`, `lib/features/backup/presentation/backup_screen.dart`, `test/services/backup_service_test.dart`, `test/features/backup/backup_screen_layout_test.dart`). Focused backup tests: 10 passed; phone/tablet layout test: 1 passed; full suite before that test: 315 passed; analysis clean. Format 2 backups require an updated app; format 1 backups cannot recover a photo they never contained. |

## Open work confirmed by code

| ID | Status | Item and evidence | Recommended next step |
| --- | --- | --- | --- |
| DATA-01 | Partial / defect | The integrity checker has checks for older sales, UTANG, consignment, expenses, and GCash data, but its required-table list and checks do not cover later Maya, loan, daily-closing, supplier, and managed-brand schema (`lib/services/data_integrity_service.dart`, `lib/database/migrations/`). A healthy result does not certify those newer areas. | Extend checks against schema v28 and add targeted corruption tests. |
| PLAN-01 | Not implemented | Production billing/entitlement is absent. `OpenAccessPlanSource` grants Pro in release while `DevelopmentPlanSource` simulates Free/Pro in debug (`lib/services/feature_access_service.dart`). This is not a decision to start charging. | Decide the commercial model first; if approved, implement an entitlement source and release tests. |
| REL-01 | Partial / defect | Android release still signs with the debug key; the application ID has a template TODO; `pubspec.yaml` remains at `1.0.0+1` with a template description (`android/app/build.gradle.kts`, `pubspec.yaml`). | Before distribution, choose the permanent ID, set up release signing and versioning, then verify a release build. |
| REL-02 | Not implemented | `README.md` remains the Flutter starter text, and no repository CI workflow is present. | Document setup, data model, backup recovery, and release steps; add a minimal analyze/test CI gate. |

## Work in the current tree

These entries describe local changes only. Check `git status` before changing or summarizing them.

| Item | State | Evidence / note |
| --- | --- | --- |
| Named navigation destinations | Implemented locally, uncommitted | `lib/features/shell/app_destination.dart` and edits in `app_shell.dart` / `dashboard_screen.dart` replace numeric section IDs and make the staff destination allowlist explicit. This was requested after the earlier behavioral review. |
| Screen extraction | Implemented locally, uncommitted | `consignment_dialogs.dart` and `sale_history_dialog.dart` were extracted from large screens. No broad redesign of all large screens has been done. |
| Tablet Tindahan Profile navigation | Present locally, uncommitted | Existing shell changes and `test/features/shell/tablet_profile_navigation_test.dart` were already in the user's working tree when cleanup began; preserve and verify them. |
| Tablet sidebar store identity | Implemented locally, uncommitted | `lib/features/shell/presentation/app_shell.dart` now uses a smaller TindaSari PH header and a compact photo/name card above navigation. It reads `SettingsService.storeProfile`, refreshes after profile edits, allows two name lines, and hides the card when collapsed. `test/features/shell/tablet_store_identity_test.dart` covers compact tablet, dark expanded/collapsed tablet, long name, photo/fallback, refresh, and phone layout. |
| Tindahan Profile photo action | Implemented locally, uncommitted | The view's camera badge now opens **Take photo** or **Choose from gallery**, persists the photo without editing other fields, refreshes the tablet sidebar, and removes the previous app-owned photo after saving. The edit form uses the same chooser. `StorePhotoService.capture` stores camera images in the existing `store_images` folder. `test/features/store_profile/tindahan_profile_test.dart` covers camera/gallery selection, replacement, cancellation, and phone/tablet widths. Native picker behavior still needs a device check. |

## Recommendations, not approved scope

1. **Extend integrity coverage (DATA-01)** after deciding which newer ledger invariants matter most. Source: code review.
2. **Decide backup protection.** `.tnebackup.zip` files contain the database and photos without encryption (`lib/services/backup_service.dart`). Encryption and password recovery need a product decision before implementation. Source: code review; encryption is a recommendation.
3. **Continue incremental screen refactoring after behavior fixes.** The recent extraction reduced `consignment_screen.dart`, but `cash_sale_screen.dart`, `loan_management_screen.dart`, `inventory_screen.dart`, and other screens remain large. Extract around one tested workflow at a time. Source: conversation request and current file sizes.
4. **Prepare a distribution checklist before shipping (REL-01/02).** Include signing, permanent application ID, versioning, documentation, and automated checks. Source: code review.
5. **Decide whether monetization is wanted at all (PLAN-01).** Free/Pro identifiers in code are not evidence of an approved pricing plan. Source: code and conversation review.

## Decisions to record when made

| Decision | Current state |
| --- | --- |
| Charge for Pro or keep release features open? | Undecided in this thread; release currently grants Pro. |
| Encrypt exported backups? If so, what is the password and recovery policy? | Undecided; current ZIP is unencrypted. |
| Android distribution channel, permanent package ID, and release signing owner? | Undecided; release configuration is incomplete. |
| Priority among the confirmed gaps above? | Recommendations above are suggested order, not an agreed schedule. |

## Change log

| Date | Change | Verification / source |
| --- | --- | --- |
| 2026-11-10 | Created this baseline from the available conversation, code, tests, and Git history. Recorded confirmed gaps separately from proposed work. | Read-only code and Git review; no app behavior changed by this documentation. |
| 2026-11-10 | Recent uncommitted cleanup replaced numeric navigation IDs and extracted consignment and sales dialog code. Tablet Tindahan Profile navigation was already present in the tree. | Earlier validation results are recorded in **Current snapshot**. |
| 2026-11-10 | SEC-01: restricted stock correction to explicit owner role in the repository, hid the menu action for staff, and added regression coverage. Updated owner fixtures that intentionally correct stock. | `flutter analyze --no-pub`: no issues. Focused tests: 18 passed. Full suite: 309 passed. Changes remain uncommitted. |
| 2026-11-10 | SEC-02: persisted PIN retry and lockout state in `app_settings` with transactional verification, synchronized the login remaining-attempt display, and added instance, restart, concurrency, expiry, and reset tests. | `flutter analyze --no-pub`: no issues. Focused authentication tests: 8 passed. Full suite: 312 passed. Changes remain uncommitted. |
| 2026-11-10 | DATA-02: added version 2 backup support for the selected Tindahan photo, safe path rewriting on restore, version 1 compatibility, inclusion text, and transfer/validation tests. | `flutter analyze --no-pub`: no issues. Focused backup tests: 10 passed. Full suite: 315 passed. Changes remain uncommitted. |
| 2026-11-10 | Clarified that the existing Android app supports phone and tablet layouts, added a future UI check rule to `AGENTS.md`, and added a backup-screen layout regression test. | Shell breakpoint checked at 900dp. Backup screen test passed at 280dp and 1200dp; `flutter analyze --no-pub` found no issues. No app behavior changed. |
| 2026-11-10 | Added a compact store photo/name card above tablet navigation and reduced the app brand header size; kept collapsed sidebar and phone layout compact. | `flutter analyze --no-pub`: no issues. Focused phone/tablet shell tests: 6 passed. Full suite: 317 passed. Changes remain uncommitted. |
| 2026-11-10 | Connected the Tindahan Profile camera badge to camera/gallery selection and direct photo saving; reused the picker in the edit form, refreshed store identity, and guarded photo cleanup after a successful save. | `flutter analyze --no-pub`: no issues. Focused profile/tablet tests: 6 passed. Full suite: 318 passed. Native picker not device tested. Changes remain uncommitted. |

## Update rule

For every future project change, update this file in the same work session: adjust affected statuses and evidence, add newly found gaps or decisions, record what changed and how it was verified in the change log, and refresh the review date. Mark work as **local/uncommitted** until it is committed. Keep recommendations visibly separate from approved work. If a change does not alter a feature status, still log the material change; a change to this tracker alone does not need a recursive log entry.
