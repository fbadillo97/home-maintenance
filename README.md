# Badillo Home Maintenance

A small home maintenance app hosted on GitHub Pages, with private records in Supabase. Home, Equipment, Schedule and History share linked database tables. Documents belong to equipment. Forms save directly; conflicting edits stay visible for review. There is no JSON workflow, embedded chatbot, custom export, browser record recovery, calendar, completeness scoring or separate document library.

## Access

The public repository and Pages site contain generic code and a sign-in screen only. All equipment, history, follow-ups, receipts and member details are in Supabase. Signed-in users must have a verified email and active entry in `home_private.members`. This membership is independent from the wishlist app in the same project. Only the original wishlist owner was given initial maintenance access. Adding another person requires a separate explicit instruction. No invitations were sent.

The existing family email sign-in and session storage key are reused. No private records are stored in localStorage. Supabase Auth checks identity; database policies and checked functions enforce membership. Sign-out and failed access checks clear the page, dialogs and document blobs, and stale in-flight responses cannot restore them.

Public Supabase URL and publishable key belong in config.json. Never add privileged keys, auth sessions, real records, member emails, document bytes, PDFs or migration seeds to this repository or its Git history.

## Database

Tables: home_equipment, home_tasks, home_task_equipment, home_history, home_history_equipment, home_attention, home_documents and home_document_equipment. Ordinary records have typed columns; asset-specific evidence is preserved separately without adding universal fields. Private archived source material is retained for reference outside everyday navigation.

`backend/schema.sql` documents the schema already applied to the shared project; do not rerun it. Do not change the wishlist schema, roles, default Site URL, existing redirect URLs or SMTP settings. All ordinary client writes use revision-aware checked RPCs. Work logging has an operation ID so retrying an uncertain response cannot duplicate an entry. Completion is never inferred from status changes. AI requests are prepared locally for this chat; rough drafts are not saved and do not resolve anything.

The six migrated PDFs occupy less than 1 MB total. Their bytes are in a private document table and delivered through a membership-checked RPC; metadata links each file to its equipment. A single file is currently bounded to 1 MB. This deliberately small library has no upload/gallery feature. Review private object storage if requirements expand.

## Hosting and sign-in

GitHub Pages: deploy main from / (root). App address: https://fbadillo97.github.io/home-maintenance/ . Add that exact address, including the trailing slash, to Supabase Auth's allowed redirect URLs. Preserve the wishlist defaults. The app explicitly sets its own email-link return URL.

## Verification

`node --check app.js` and `node tests/frontend.cjs` run without installing dependencies. Frontend checks use simulated browser elements and fabricated records. `tests/database.sql` uses synthetic fixtures inside a rolled-back transaction to check membership, RLS, direct-write denial, edits, serial zeros, conflicts, task logging, idempotent retries and document access. Never run test fixtures without the final rollback.

Migration checks compared the 25 equipment records and 10 tasks with revision 6 of the previous Site, retained the two deduplicated history entries, and verified all six PDF hashes. The previous Site and local files remain preserved. Review the new app before retiring the old Site; after cutover, keep all current edits in Supabase.

Security advisors report informational RLS-without-policy notices for private tables whose direct client privileges are revoked; access is through checked functions. The existing project also reports disabled leaked-password protection. This app uses email links and adds no password flow. See https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy and https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection .

Actual email delivery and browser layout require a user sign-in check. Automated checks do not claim that physical-device review.
