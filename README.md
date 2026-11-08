# PasyalPH — Flutter + Supabase

Flutter implementation based on `bonzirelle/pasyalph` at source commit
`1537ec5adddf54ffb8a665714928c66264837f8d`. The original React UI is implemented
as Flutter widgets; Firebase is replaced by Supabase client integrations.

## Run the preview

### Deploy to Vercel

The root `vercel.json` builds Flutter Web with the pinned Flutter 3.47.9 SDK
and publishes `build/web`. Import this repository into Vercel with the project
root set to the repository root. The build downloads Flutter on first use; no
Vercel secret or service-role key is needed for the public client.

In VS Code, open `../PasyalPH.code-workspace`. It selects the active Flutter
project, uses the workspace-local Flutter SDK, and leaves the archived React
source outside the active project. The included F5 configuration debugs Chrome
on port 3001 so it can coexist with the background preview on port 3000.

From the workspace root, run `powershell -ExecutionPolicy Bypass -File .\start-preview.ps1`.
This starts a hidden background preview and reuses an existing PasyalPH server.
The regular preview serves the release build, avoiding Flutter debug WebSocket
connections. It rebuilds when source files are newer than the compiled app.
It does not stop unrelated services on port 3000. Startup logs and the launcher
process ID are stored in `pasyalph_supabase_flutter/artifacts/preview.*`.
Use `-Foreground` if you prefer to keep the server in your terminal.

For Flutter hot reload, run the development server from this folder (stop the
release preview first because both use port 3000):

```powershell
powershell -ExecutionPolicy Bypass -File .\start-web.ps1
```

Open http://localhost:3000/ and leave the terminal running. The launcher uses
Flutter on PATH or `../.tools/flutter`. The checked-in public client configuration
connects to the existing `pasyalph` project. No secret/service-role key is included.
Override using `-SupabaseUrl` / `-SupabasePublishableKey`, environment variables,
or Flutter `--dart-define` values.

## Included

- Original logo, four photos, Fraunces and Plus Jakarta Sans fonts.
- Intro, centered 430px desktop frame, mobile layout, hero, category filtering,
  place carousels, search, details, amenities, indicative fares, and nearby places.
- All 45 original sample listings. Sample reviews are separately labeled and do
  not inflate real traveler ratings. Confirm sample contact details before use.
- Supabase email/password auth, signup confirmation/resend, optional email codes,
  magic links, password recovery, and Google OAuth client flow.
- Saved places, profile editing, photo uploads, preferences, home/work addresses,
  owner applications, listing submission/editing, and admin moderation interfaces.
- Map search restricted to the Philippines, explicit location consent, street,
  satellite and terrain tiles, driving/walking/cycling alternatives and navigation
  steps. Transit opens external directions. Estimates do not include live traffic.
- Responsive web admin portal at `/#/admin` for live catalog analytics and CRUD of
  business listings, accommodations, and destinations. Its navigation links can
  open the overview, `/#/admin/listings`, `/#/admin/accommodations`,
  `/#/admin/destinations`, and `/#/admin/applications` directly; dashboard
  metrics and status rows link to their filtered catalog views. Admin access is
  enforced by the signed-in Supabase profile role and database RLS; it does not
  grant or provision administrator privileges.
- Catalog travel guide, optional server-side Gemini assistant, trip planning,
  copy/share actions, and a guarded account-deletion flow.
- Android project with network/location permissions and the auth callback intent.

## Backend release status

**Production schema/data/storage/functions have not been changed.** Automatic
approval review rejected the production migration. Review the concrete package in
[supabase/README.md](supabase/README.md) before approving its application.

The existing project has email auth enabled, Google disabled, and no published
places. Until the backend release is approved:

- Explore uses the original local sample catalog.
- Local sample saves are device-only. Published-place saves use Supabase.
- Real account/profile/business features use the existing tables and their RLS.
- New trip plans fall back to device storage and explicitly report that storage.
- Posting traveler reviews/reports on sample listings requires catalog import.
- Uploads, cloud trip plans, and Edge Functions need the prepared backend
  release. For live refresh on existing tables only, review and run
  `sql/05_enable_realtime_publication_only.sql` in Supabase; it changes
  publication membership without applying the broader release.
- Google needs provider credentials; email links need allowed redirects. A Gemini
  secret is optional and must remain server-side. Catalog mode needs no AI key.

No account is automatically granted owner/admin privileges. Business approval uses
the existing administrator RPC. Existing Firebase users/passwords are not imported.
The admin portal requires an account whose Supabase profile has the `admin` role,
and the reviewed backend policies in `sql/03_flutter_feature_parity.sql` must be
applied before catalog management is available. The portal does not use bundled
sample listings as editable production data.
For Gmail delivery, email templates, and auth redirect setup, see
[docs/EMAIL_AUTH_SETUP.md](docs/EMAIL_AUTH_SETUP.md).

## Verification

```powershell
..\.tools\flutter\bin\flutter.bat --no-version-check analyze --no-pub
..\.tools\flutter\bin\flutter.bat --no-version-check test --no-pub
node --test tools/functions.test.mjs
node --test tools/preview-server.test.mjs
```

Forty Flutter tests cover sample integrity, save persistence, precise nearby
distances, location requirements, Explore/details, Saved, signup validation and
the desktop frame, guest itineraries, profile refresh, concurrent preferences,
cloud/device plan coexistence, and disposal during refresh.
The map checks cover three phone sizes, separate search/filter/control regions,
compact directions, map options, search focus, and visible destination markers.
Fifteen location tests cover browser/native permission handling, timeouts,
single-flight requests, watch cleanup and recovery dialogs. See
[docs/LOCATION_ACCESS.md](docs/LOCATION_ACCESS.md) for device/browser setup.
Ten isolated Edge Function tests cover authentication, quota, catalog fallback
and deletion safeguards. `artifacts/explore-desktop.png` is
generated by the UI suite. Live public REST and route-service reads were checked.
Headless Chrome also rendered the running app without captured startup errors;
the actual browser capture is `artifacts/browser-preview.png`.
The release web build also compiles successfully with Material and Cupertino
icon fonts included. The prepared function entrypoints can be checked locally
with `..\.tools\deno\deno.exe check supabase/functions/travel-assistant/index.ts supabase/functions/delete-account/index.ts`.
These checks do not constitute an authenticated production end-to-end test.

## Android

The Android SDK is absent on this machine; no APK/device test has been performed.
After installing Android Studio/SDK and accepting Android licenses, run:

```powershell
..\.tools\flutter\bin\flutter.bat run
..\.tools\flutter\bin\flutter.bat build apk --release
```

Configure production signing before distribution; generated Gradle configuration
currently uses the Flutter development signing setup. Map/search/route services
are public services with their own usage policies and availability limits.

See [docs/MIGRATION_AUDIT.md](docs/MIGRATION_AUDIT.md) for verified scope and pending
operator configuration. Font licenses are in `assets/fonts/`.
