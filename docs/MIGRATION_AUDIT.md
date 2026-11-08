# Migration status — November 8, 2026

Original source: `bonzirelle/pasyalph`, commit
`1537ec5adddf54ffb8a665714928c66264837f8d`. All original route files, shared UI,
store, seed data, styles, logo and photos were inspected. Reference source was
downloaded for inspection only; no GitHub files/history were changed.

| Area | Flutter implementation | Remaining external dependency |
| --- | --- | --- |
| Branding and Explore | Original assets/fonts; intro, mobile frame, hero, search, sections, details | Visual approximation, not a pixel-diff certification |
| Catalog | 45 original samples bundled; demo reviews labeled separately | Approval to import samples into Supabase |
| Auth | Email/password, signup/resend, code verification, magic link, recovery, Google client | Operator email/redirect and Google provider configuration; no Firebase password migration |
| Favorites/reviews/reports | Supabase CRUD and error handling; local sample saves explicitly identified | Real sample review/report mutations need catalog import |
| Profile | Name/username/phone/avatar, appearance, units, navigation labels, home/work | Image bucket release; role-column restriction in proposed SQL |
| Business | Application status, owner approval guard, geocoding, listing creation/editing | Existing admins and RLS; proposed owner-policy hardening |
| Admin | Application approval RPC, verify/reject/suspend, sponsorship, resolve reports | A trusted administrator account; no privilege self-assignment |
| Map | PH address search, GPS, share link, layers, alternatives, driving/walking/cycling, live step progression | Device permission and public service availability; no live traffic or background sharing |
| Assistant | Catalog search and optional Gemini Edge Function | Backend deployment and optional operator-supplied Gemini secret |
| Itineraries | Ordered stops/notes, copy/delete; explicit device fallback | New private `trip_plans` table for cloud persistence |
| Account deletion | Recent sign-in, verification safeguards, session revocation, photo cleanup and Auth deletion handler | Edge Function deployment and staging validation; never tested on a real user |
| Android | Native target, permissions, login callback | Android SDK, signing, emulator/device and release build |

## Verified

- Flutter web debug compilation and localhost HTTP responses.
- Release web compilation with both icon fonts; default local preview serves this
  release build without the Flutter debug WebSocket dependency.
- Headless Chrome renders the app; startup captured no runtime exceptions or failed requests.
- Static analyzer; forty Flutter tests and ten Edge Function handler tests.
- Map controls are separated from search and filters, place details use a compact
  bottom card, and crowded markers group into zoomable counts. Nine map tests
  cover 320px/430px layouts, directions, map options, focus and destination visibility.
- Location requests use one bounded browser read without the plugin's extra
  permission-position request. Temporary watches are cancelled after completion;
  blocked permissions, disabled device services, timeouts and insecure contexts
  have recovery guidance. Map, Profile and the assistant use the same flow.
- Preview-server test covering assets, routes, health, MIME types and path guards;
  Deno checks for both prepared function entrypoints.
- Public Supabase REST access with the recovered publishable key.
- Supabase public Auth settings: email enabled, Google disabled.
- Three routing services return `Ok` for original Tagaytay sample coordinates.
- Source data IDs remain unique; decimal distances do not round to whole km.
- Official Flutter/Dart and Deno VS Code extensions installed; the focused
  `PasyalPH.code-workspace` includes SDK paths and a separate Chrome debug profile.

## Pending backend approval

User decision: keep production unchanged and fix the local application only.
The fixes preserve device plans alongside cloud results, remove stale favorites,
serialize preference writes, protect unsaved profile edits, and prevent hidden live
listings from returning through the sample fallback. Guests can save and reopen
device-only itineraries. `../start-preview.ps1` provides a background launcher.

`sql/03_flutter_feature_parity.sql` is a one-time transactional migration against
the inspected existing schema. `sql/04_original_sample_catalog.sql` preserves
existing rows on ID conflicts. `supabase/functions/` contains two prepared services.
The migration attempt was rejected by automatic approval review; no production
schema/data/storage/function/Auth changes were made. SQL and deployed RLS behavior
remain unverified until an approved staging/production rollout is possible.

Existing advisor findings included public privileged RPC/helper execution and a
quota table with no policy. Proposed SQL moves privileged implementation into a
private schema, retains guarded callable RPCs, restricts settings-only profile
updates, checks owner approval, and gives the quota table an own-row read policy.

This is not a claim of complete production parity: provider setup, backend release,
authenticated end-to-end tests, policy/operator details, Android builds and device
navigation checks remain. Catalog mode is not presented as generative AI. Transit
uses external directions; the app does not book stays or invent real-time fares.
