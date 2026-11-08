// Public browser/mobile client configuration. Access is enforced by Supabase RLS.
// Override with --dart-define for another environment. Never put secret keys here.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://dwpetlhrbxxeqmfdmqdv.supabase.co');
const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_4t0n2OFqpjPAvD5657W7vg_VfPamvrV');

const googleAuthEnabled = bool.fromEnvironment(
  'GOOGLE_AUTH_ENABLED',
  defaultValue: false,
);
