-- PROPOSED REVIEW-ONLY PATCH. DO NOT RUN without checking existing grants,
-- triggers, policies and the app's account lifecycle in a staging database.
-- Existing project has RLS enabled for all 7 public tables, but profiles UPDATE
-- policy allows self-updates without a column restriction. If UPDATE(role) is granted,
-- a traveler could set their own role to 'admin' and is_admin() would trust it.
-- RECOMMENDED DEFENSE: remove table-level UPDATE from authenticated, and grant
-- column-specific UPDATE(settings) only. Ensure no inherited PUBLIC grants remain.
revoke update on public.profiles from public, anon, authenticated;
grant update(settings) on public.profiles to authenticated;
-- Existing SELECT + UPDATE RLS policies on profiles remain necessary.

-- Existing business_applications has SELECT and INSERT policies but no admin UPDATE.
-- Add explicit admin-only approval; verify is_admin() is secure and cannot be
-- influenced by user-controlled profile role changes before applying.
create policy application_admin_update on public.business_applications
 for update to authenticated
 using ((select public.is_admin()))
 with check ((select public.is_admin()));
-- To enable admin updates, check UPDATE privilege first; if absent:
grant update(status) on public.business_applications to authenticated;

-- Existing places UPDATE policy lets an owner change all fields while pending;
-- it should restrict owner-editable fields and forbid changing sponsored/status.
-- This requires a reviewed replacement policy or trusted trigger, not a blind patch.
-- IMPORTANT: existing is_owner() checks profiles.role; it does NOT itself check
-- approved business application. Add an approved-application check to the
-- owner listing creation policy before production launch.
-- Protect public.is_admin() and public.is_owner() SECURITY DEFINER functions:
-- verify EXECUTE privileges, explicit auth.uid checks, and fixed search_path.
-- Storage: create a private/public bucket and owner-scoped policies only after
-- deciding the upload paths; do not expose service_role to Flutter.
