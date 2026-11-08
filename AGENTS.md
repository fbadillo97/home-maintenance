# Home maintenance

Private household records live in Supabase. This public repository contains generic application code and schema only. Never add equipment data, serials, receipts, document bytes, member emails, auth tokens, private fixtures, or real-data seeds to Git. Public Supabase URL/publishable key are client configuration, never privileged keys.

The owner approved four views: Home, Equipment, Schedule (task list), History. Documents belong inside equipment. Save each form directly; keep conflicts visible without replacing edits. No JSON import/export/synchronization, browser record recovery, completeness scores, charts, calendar, separate document library, source archive navigation, stored rough drafts, detailed attention timelines, embedded AI, or background agents. Soft dark theme: charcoal surfaces, subdued blue accents and restrained status colors.

Equipment fields stay simple: name, manufacturer, category, model, serial, one purchase/ownership date, warranty information, manual and notes. Keep maintenance and modifications in linked history. Ownership date can be year/month/day and is not manufacture age. Keep useful asset-specific evidence without turning it into new universal fields. Do not invent service completion or coverage. Do not nag about DHCP, installation dates, manufacture age or the ChargePoint app setting.

AI review happens in chat: evidence/rough answer → proposed changes → specific owner approval → apply approved facts. Approval to change code is not approval of proposed equipment facts. Preserve IDs and evidence during migrations. Never overwrite the database with an old local snapshot.

The existing Supabase project is shared with a separate wishlist app. Maintenance membership is independent. Do not change wishlist tables, functions, members, default Site URL or existing redirect URLs. All protected requests check verified, active maintenance membership. Frontend hiding is not authorization. Writes use checked, revision-aware RPCs. Clear private records, dialogs and document blobs on sign-out or failed access checks; ignore stale in-flight results. Browser storage contains auth session only.

Passkeys were explicitly approved. Reuse the shared Supabase account and existing RP ID/origin. Never change the RP ID or grant maintenance access based only on successful passkey authentication. Enrollment and management require approved home access; email recovery stays available. Removal must explain that the shared account key also serves the wishlist. Cancel stale device operations on sign-out/account changes.
