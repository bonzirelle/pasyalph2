Backend release package — prepared, NOT applied or deployed

Target: existing project `dwpetlhrbxxeqmfdmqdv` (pasyalph).

## Enable Realtime without the broader migration

To turn on Realtime publication for existing app tables without applying the
unrelated schema, RLS, storage, and function changes in the full feature
migration, review and run `../sql/05_enable_realtime_publication_only.sql` in
the Supabase SQL Editor. It is idempotent and only adds existing tables to the
`supabase_realtime` publication. It includes `trip_plans` only if that table
already exists.

The app's existing Realtime subscription refreshes its data when it receives
public-schema Postgres changes. Supabase still enforces the current table grants
and RLS policies; this script does not weaken or modify them. A change is
delivered only when the subscriber is permitted to read the affected row under
the project's existing policies. After running the script, verify membership:

```sql
select schemaname, tablename
from pg_publication_tables
where pubname = 'supabase_realtime'
  and schemaname = 'public'
order by tablename;
```

Running this publication-only script does not apply the broader backend feature
release described below.

1. Review and apply `../sql/03_flutter_feature_parity.sql` once as a migration.
   It adds sample metadata and private trip plans, scopes private authenticated
   rows to their owner/admin with restrictive RLS (while retaining public
   verified listings/reviews), limits profile edits to settings, validates form
   bounds in Postgres, requires approved owner applications, protects listing
   fields, moves privileged helpers into a private schema, enables Realtime, and
   creates the public image bucket with user-scoped writes (JPG/PNG/WebP, 5 MB).
   It does not grant admin access to any account.
2. Review and execute `../sql/04_original_sample_catalog.sql`. This inserts the
   45 original sample listings only when their source IDs do not already exist.
   Sample reviews are display-only metadata, separate from real traveler reviews.
3. Deploy `functions/travel-assistant` and `functions/delete-account`, retaining
   JWT verification. The functions independently validate the caller with Auth.
   The assistant has a 20-request daily quota. Add a server-side `GEMINI_API_KEY`
   (and optional `GEMINI_MODEL`) to enable AI; otherwise it returns catalog results.
   Set `APP_ALLOWED_ORIGINS` as a comma-separated list of exact browser origins
   (including local preview origins and the production origin) before deployment.
   Browser requests from any other origin are rejected; native requests without
   an `Origin` header still require a valid Supabase access token. Keep the service
   role key and Gemini key in Supabase Function secrets, never Flutter defines.
   No paid provider is configured by this package.
4. In Supabase Auth, allow `http://localhost:3000/`, `http://127.0.0.1:3000/`, the
   production origin, and `com.pasyalph.app://login-callback/` redirect URLs.
   Google OAuth additionally requires the operator's Google client credentials.
   Email signup, confirmation, reset, and optional codes use Supabase email
   templates. Custom SMTP and template configuration remain operator settings.
5. Run security/performance advisors. Test anonymous reads, traveler isolation,
   owner approval, protected columns, uploads, Realtime and destructive account
   deletion in a test environment before public launch.

The production migration attempt was rejected by automatic approval review.
No schema, data, bucket, function, or Auth configuration changes were made.
The Flutter client remains usable with the local, clearly labeled sample catalog.

## Hosted security controls still required

- Supabase Auth hashes passwords server-side. Configure a 12-character minimum,
  compromised-password checks where available, login/signup/reset rate limits,
  and a short recovery-link/code lifetime in the hosted Auth settings. The app
  enforces the same minimum for new and reset passwords, but hosted Auth must
  enforce it independently. Existing sign-in passwords remain accepted.
- The Flutter web client uses Supabase bearer tokens, not HttpOnly session
  cookies. CSRF defenses for cookie-authenticated requests are therefore not the
  current auth model; the Edge Functions now use an explicit origin allowlist.
  HttpOnly/Secure/SameSite cookies require a separately hosted backend-for-frontend
  and migration of browser API calls; they cannot be enabled by Flutter client code.
- Redirect HTTP to HTTPS and set HSTS, CSP and other response security headers at
  the production web host/CDN. Flutter assets cannot set those response headers.
  Supabase and all production API endpoints must use HTTPS.
- `03_flutter_feature_parity.sql` adds server-side bounds for profile settings,
  business forms, trip-plan shape, and protected listing updates. It remains a proposed,
  un-applied migration: review existing data and policies, then test in staging.
  Its restrictive policies compose with existing permissive policies, so test
  authenticated owner/admin isolation and public reads in staging before rollout.
- Listing `rates` are display text only. This app has no booking or payment
  checkout, so there is no server-authoritative transaction price to recheck.
  Any future booking flow must fetch and validate prices on a trusted server.

The Flutter client's Supabase publishable key is intentionally public and is
restricted by database RLS; it is not a service credential. Never put a
service-role, Gemini, SMTP, or OAuth client secret in the browser bundle.
Flutter presents user, catalog and assistant strings as text rather than
executable HTML, and database requests use Supabase's parameterized client API.
Do not add raw SQL concatenation or an HTML renderer for untrusted content.
