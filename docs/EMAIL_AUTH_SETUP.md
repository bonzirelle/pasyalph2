# Email sign-in and Gmail delivery

The app sends email authentication requests through Supabase Auth. Gmail is not
configured in Flutter, and the app must never contain a Gmail password, SMTP
credential, or Google OAuth client secret. Configure delivery in the Supabase
Dashboard for project `pasyalph`.

## Configure Gmail SMTP

1. Use a dedicated Gmail sender account. Enable Google's 2-Step Verification
   and create an **App password** for mail. Do not use the account's normal
   password. Google Workspace administrators may disallow App passwords.
2. In Supabase Dashboard, open **Authentication → SMTP Settings** and enable
   custom SMTP. Enter:
   - Host: `smtp.gmail.com`
   - Port: `587` (STARTTLS)
   - Username: the full Gmail address
   - Password: the generated Google App password
   - Sender email: the same Gmail address
   - Sender name: `PasyalPH`
3. Save settings, then use Supabase's email test and confirm receipt in Gmail,
   including the spam folder. Never put the App password in Flutter config,
   `--dart-define`, source control, or a chat message.

Supabase's built-in mailer is for testing only; it limits recipients to project
team members and has a low hourly limit. Gmail also enforces sending limits, so
use a transactional SMTP provider and a verified sending domain for production
traffic.

## Configure the auth links and codes

In **Authentication → URL Configuration**:

- Set **Site URL** to the real HTTPS web app origin.
- Add each deployed web origin ending in `/` to **Redirect URLs**. The app
  redirects email flows to the current web origin, so the exact host and port
  need to be allowed. Local development uses
  `http://localhost:3000/`, `http://127.0.0.1:3000/`,
  `http://localhost:3001/`, and `http://127.0.0.1:3001/`.
- Add `com.pasyalph.app://login-callback/` for the Android callback.

In **Authentication → Email Templates**, keep the confirmation, magic-link and
password-reset templates' `{{ .ConfirmationURL }}` links intact. For confirmation
and magic-link emails, include `{{ .Token }}` if users should also be able to
enter the six-digit code in the app. A template can include both, for example:

```html
<h2>Sign in to PasyalPH</h2>
<p><a href="{{ .ConfirmationURL }}">Open the secure sign-in link</a></p>
<p>Or enter this one-time code in the app: <strong>{{ .Token }}</strong></p>
```

Use the **Confirm signup** template for account confirmation and the **Magic
Link** template for passwordless sign-in. Keep the password-reset template's
`{{ .ConfirmationURL }}` link; the app opens its password update screen after
Supabase returns the recovery session. Never send or log passwords or reusable
access tokens in an email template.

The login page offers password sign-in and a full-width email-link/code action.
After requesting a code, enter the six-digit code on the same screen, or open
the link on the device/browser where you want to sign in. The Google button is
hidden unless the app is built with `--dart-define=GOOGLE_AUTH_ENABLED=true`;
enable that only after configuring Google OAuth in Supabase and its redirect
URLs. Gmail SMTP delivery and Google OAuth sign-in are separate settings.

## Verify delivery

Test signup confirmation, passwordless sign-in, and password reset with a
non-team Gmail address. Confirm that:

- the sender is the configured PasyalPH Gmail address;
- both link and code appear in the intended templates;
- links return to the same web origin, or the Android app callback;
- the sign-in code verifies, and the reset link opens the new-password screen.

If delivery fails, check **Authentication → Logs**, Supabase SMTP settings,
Google App-password restrictions, the template variables, and the exact
redirect allowlist. Wait for the Auth email rate limit to clear before retrying.
