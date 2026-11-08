import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'config.dart';
import 'ui.dart';
import 'business.dart';
import 'assistant.dart';
import 'location_ui.dart';

String get authRedirect =>
    kIsWeb ? '${Uri.base.origin}/' : 'com.pasyalph.app://login-callback/';

bool validEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

String authActionError(Object error) {
  if (error is AuthException) {
    final message = error.message;
    final lower = message.toLowerCase();
    if (lower.contains('email address not authorized')) {
      return 'Supabase is using its limited test email service. Configure custom SMTP in Supabase Auth to send to Gmail and other addresses.';
    }
    if (lower.contains('redirect') &&
        (lower.contains('allow') || lower.contains('not permitted'))) {
      return 'This app address is not on Supabase Auth’s redirect allowlist. Add $authRedirect in Authentication → URL Configuration.';
    }
    if (lower.contains('email') &&
        (lower.contains('rate limit') || lower.contains('too many'))) {
      return 'Too many email requests. Wait a few minutes before requesting another code or link.';
    }
    if (lower.contains('smtp') ||
        lower.contains('error sending') ||
        lower.contains('sending email')) {
      return 'Supabase could not send the email. Check the SMTP settings and Auth email template.';
    }
    return message;
  }
  return errorText(error);
}

Future<String?> uploadImage(AppState app) async {
  app.requireUser();
  final file = await FilePicker.pickFile(
      type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
  if (file == null) return null;
  final length = file.lengthSync();
  if (length != null && length > 5 * 1024 * 1024)
    throw Exception('Choose an image smaller than 5 MB.');
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) throw Exception('The image could not be read.');
  if (bytes.length > 5 * 1024 * 1024)
    throw Exception('Choose an image smaller than 5 MB.');
  final ext = (file.extension ?? '').toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext))
    throw Exception('Choose a JPG, PNG, or WebP image.');
  final path = '${app.user!.id}/${DateTime.now().microsecondsSinceEpoch}.$ext';
  await app.client.storage.from('pasyalph-media').uploadBinary(path, bytes,
      fileOptions: FileOptions(
          contentType:
              ext == 'jpg' || ext == 'jpeg' ? 'image/jpeg' : 'image/$ext'));
  return app.client.storage.from('pasyalph-media').getPublicUrl(path);
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final form = GlobalKey<FormState>(),
      email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      code = TextEditingController();
  bool signup = false, busy = false, accepted = false, showPassword = false;
  String? error, message;
  String? verifyEmail;
  OtpType otpType = OtpType.signup;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> action(Future<void> Function(AppState) fn) async {
    if (busy) return;
    final app = AppScope.of(context);
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      await fn(app);
    } catch (e) {
      if (mounted) setState(() => error = authActionError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (signup && !accepted) {
      setState(
          () => error = 'Please agree to the Terms of Use and Privacy Policy.');
      return;
    }
    await action((app) async {
      if (signup) {
        final response = await app.client.auth.signUp(
            email: email.text.trim(),
            password: password.text,
            data: {
              'name': name.text.trim(),
              'accepted_policies_at': DateTime.now().toUtc().toIso8601String()
            },
            emailRedirectTo: authRedirect);
        if (mounted)
          setState(() {
            if (response.session == null) {
              verifyEmail = email.text.trim();
              otpType = OtpType.signup;
              message =
                  'Check your inbox and open the confirmation link. If your email includes a code, you can enter it below.';
            } else {
              message = 'Welcome to PasyalPH!';
            }
          });
      } else {
        await app.client.auth.signInWithPassword(
            email: email.text.trim(), password: password.text);
        if (mounted) setState(() => message = 'Mabuhay! You are logged in.');
      }
      password.clear();
      await app.refresh();
    });
  }

  Future<void> forgot() async {
    if (!validEmail(email.text)) {
      setState(() => error = 'Enter your account email first.');
      return;
    }
    await action((app) async {
      await app.client.auth
          .resetPasswordForEmail(email.text.trim(), redirectTo: authRedirect);
      if (mounted)
        setState(() => message =
            'If this account exists, a secure reset link will arrive in your inbox.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('Your account')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            const BrandLogo(size: 48),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(signup ? 'Maligayang pagdating!' : 'Mabuhay!',
                      style: Theme.of(context).textTheme.headlineMedium),
                  Text(
                      signup
                          ? 'Gumawa ng iyong PasyalPH account'
                          : 'Mag-log in sa PasyalPH',
                      style: const TextStyle(fontSize: 11, color: muted))
                ]))
          ]),
          const SizedBox(height: 22),
          Surface(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    app.signedIn
                        ? 'Hi, ${app.name}!'
                        : 'Your next adventure starts here',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                    app.user?.email ??
                        'Log in or sign up to save places and post reviews.',
                    style: const TextStyle(color: muted, fontSize: 12))
              ])),
          const SizedBox(height: 18),
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (message != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Surface(
                    child:
                        Text(message!, style: const TextStyle(fontSize: 12)))),
          if (app.signedIn) ...[
            StatusPill(app.user!.emailConfirmedAt != null
                ? 'Email verified'
                : 'Email confirmation pending'),
            const SizedBox(height: 20),
            PrimaryButton(
                label: 'Open Profile',
                icon: Icons.person_outline,
                onPressed: () => openPage(context, const ProfilePage())),
            const SizedBox(height: 10),
            TextButton(
                onPressed: () => action((a) async {
                      await a.client.auth.signOut();
                    }),
                child: const Text('Log out')),
          ] else if (verifyEmail != null) ...[
            const SectionTitle('Check your email'),
            Text(verifyEmail!,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Field('6-digit email code (if provided)', code,
                key: const ValueKey('email-auth-code'),
                keyboard: TextInputType.number,
                hint: 'Enter the code from your email',
                maxLength: 6),
            PrimaryButton(
                label: 'Verify code',
                busy: busy,
                onPressed: () => action((a) async {
                      if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim()))
                        throw Exception(
                            'Enter the 6-digit code from your email.');
                      await a.client.auth.verifyOTP(
                          email: verifyEmail!,
                          token: code.text.trim(),
                          type: otpType);
                      await a.refresh();
                    })),
            TextButton(
                onPressed: busy
                    ? null
                    : () => action((a) async {
                          if (otpType == OtpType.signup) {
                            await a.client.auth.resend(
                                type: OtpType.signup,
                                email: verifyEmail,
                                emailRedirectTo: authRedirect);
                          } else {
                            await a.client.auth.signInWithOtp(
                                email: verifyEmail!,
                                emailRedirectTo: authRedirect,
                                shouldCreateUser: false);
                          }
                          if (mounted)
                            setState(() => message =
                                'A new email was requested. Check your inbox and spam folder. Use the email link, or enter its 6-digit code here.');
                        }),
                child: const Text('Resend email')),
            TextButton(
                onPressed: () => setState(() => verifyEmail = null),
                child: const Text('Back to login')),
          ] else
            Surface(
                child: Form(
                    key: form,
                    child: Column(children: [
                      SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Log in')),
                            ButtonSegment(value: true, label: Text('Sign up'))
                          ],
                          selected: {
                            signup
                          },
                          onSelectionChanged: busy
                              ? null
                              : (v) => setState(() {
                                    signup = v.first;
                                    error = null;
                                    accepted = false;
                                  })),
                      const SizedBox(height: 23),
                      if (signup)
                        Field('Full name', name,
                            required: true, maxLength: 100),
                      Field('Email address', email,
                          key: const ValueKey('account-email'),
                          keyboard: TextInputType.emailAddress,
                          validator: (v) => validEmail(v ?? '')
                              ? null
                              : 'Enter a valid email address.'),
                      Field('Password', password,
                          obscure: !showPassword,
                          required: true,
                          minLength: signup ? 12 : 1,
                          maxLength: 128),
                      Row(children: [
                        Checkbox(
                            value: showPassword,
                            onChanged: (v) =>
                                setState(() => showPassword = v!)),
                        const Text('Show password',
                            style: TextStyle(fontSize: 11)),
                        const Spacer(),
                        if (!signup)
                          Flexible(
                              child: TextButton(
                                  onPressed: busy ? null : forgot,
                                  child: const Text('Forgot password?',
                                      style: TextStyle(fontSize: 10))))
                      ]),
                      if (signup)
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: accepted,
                            onChanged: (v) => setState(() => accepted = v!),
                            title: const Text(
                                'I agree to the Terms of Use and Privacy Policy.',
                                style: TextStyle(fontSize: 11))),
                      PrimaryButton(
                          label: signup ? 'Create account' : 'Log in',
                          busy: busy,
                          onPressed: submit),
                      const SizedBox(height: 14),
                      const Text('or', style: TextStyle(color: muted)),
                      const SizedBox(height: 14),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => action((a) async {
                                        if (!validEmail(email.text))
                                          throw Exception(
                                              'Enter a valid email address first.');
                                        await a.client.auth.signInWithOtp(
                                            email: email.text.trim(),
                                            emailRedirectTo: authRedirect,
                                            shouldCreateUser: false);
                                        if (mounted)
                                          setState(() {
                                            verifyEmail = email.text.trim();
                                            otpType = OtpType.email;
                                            message =
                                                'We sent a sign-in email. Open its link to log in, or enter the 6-digit code below if your email contains one.';
                                          });
                                      }),
                              icon: const Icon(Icons.mark_email_read_outlined),
                              label: const Text(
                                  'Email me a sign-in link or code'))),
                      if (googleAuthEnabled) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => action((a) async {
                                          if (signup && !accepted) {
                                            final yes = await confirm(
                                                context,
                                                'Continue with Google?',
                                                'By continuing, you agree to the Terms of Use and Privacy Policy.',
                                                action: 'Agree and continue');
                                            if (!yes) return;
                                            accepted = true;
                                          }
                                          await a.client.auth.signInWithOAuth(
                                              OAuthProvider.google,
                                              redirectTo: authRedirect);
                                        }),
                                icon: const Icon(Icons.account_circle_outlined),
                                label: const Text('Continue with Google')))
                      ],
                    ]))),
          const SizedBox(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
                onPressed: () =>
                    openPage(context, const PolicyPage(privacy: false)),
                child:
                    const Text('Terms of Use', style: TextStyle(fontSize: 11))),
            TextButton(
                onPressed: () =>
                    openPage(context, const PolicyPage(privacy: true)),
                child: const Text('Privacy Policy',
                    style: TextStyle(fontSize: 11)))
          ]),
        ]));
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: !embedded, title: const Text('Profile')),
        body: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
                children: [
                  Surface(
                      child: Row(children: [
                    CircleAvatar(
                        radius: 29,
                        backgroundColor: ink,
                        backgroundImage: app.avatar.startsWith('https://')
                            ? NetworkImage(app.avatar)
                            : null,
                        child: app.avatar.isEmpty
                            ? Text(
                                app.name.isEmpty
                                    ? 'P'
                                    : app.name[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 24))
                            : null),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(app.signedIn ? app.name : 'Your next adventure',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(
                              app.user?.email ?? 'Explore, save, and discover.',
                              style:
                                  const TextStyle(fontSize: 11, color: muted)),
                          const SizedBox(height: 5),
                          StatusPill(app.signedIn ? app.role : 'Guest')
                        ]))
                  ])),
                  if (!app.signedIn) ...[
                    const SizedBox(height: 15),
                    PrimaryButton(
                        label: 'Log in or sign up',
                        onPressed: () =>
                            openPage(context, const AccountPage())),
                    const SizedBox(height: 12),
                    Surface(
                        padding: 4,
                        child: ListTile(
                          leading: const Icon(Icons.route_outlined),
                          title: const Text('Trip plans',
                              style: TextStyle(fontSize: 13)),
                          subtitle: const Text('Saved on this device',
                              style: TextStyle(fontSize: 10)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => openPage(context, const TripPlansPage()),
                        )),
                  ] else ...[
                    const SectionTitle('Account details'),
                    Surface(child: ProfileForm(key: ValueKey(app.user!.id))),
                    const SectionTitle('Your adventures'),
                    Surface(
                        padding: 4,
                        child: Column(children: [
                          ListTile(
                              leading: const Icon(Icons.route_outlined),
                              title: const Text('Trip plans',
                                  style: TextStyle(fontSize: 13)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () =>
                                  openPage(context, const TripPlansPage())),
                          ListTile(
                              leading: const Icon(Icons.storefront_outlined),
                              title: const Text('Business registration',
                                  style: TextStyle(fontSize: 13)),
                              subtitle: Text(
                                  app.applications
                                          .where((a) =>
                                              a['owner_id'] == app.user?.id)
                                          .firstOrNull?['status'] ??
                                      'Register as a business owner',
                                  style: const TextStyle(fontSize: 10)),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => openPage(
                                  context, const BusinessApplicationPage())),
                          if (['owner', 'admin'].contains(app.role))
                            ListTile(
                                leading:
                                    const Icon(Icons.business_center_outlined),
                                title: const Text('Your businesses',
                                    style: TextStyle(fontSize: 13)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    openPage(context, const OwnerPage())),
                          if (app.role == 'admin')
                            ListTile(
                                leading: const Icon(
                                    Icons.admin_panel_settings_outlined),
                                title: const Text('Admin portal',
                                    style: TextStyle(fontSize: 13)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    Navigator.of(context).pushNamed('/admin')),
                          if (app.role == 'admin')
                            ListTile(
                                leading: const Icon(Icons.fact_check_outlined),
                                title: const Text('Moderation queue',
                                    style: TextStyle(fontSize: 13)),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.of(context)
                                    .pushNamed('/moderation'))
                        ])),
                  ],
                  const SectionTitle('App preferences'),
                  Surface(
                      child: Column(children: [
                    _choice(context, app, 'Appearance', 'colorScheme',
                        'automatic', {
                      'automatic': 'Use device setting',
                      'day': 'Day',
                      'night': 'Night'
                    }),
                    _choice(
                        context,
                        app,
                        'Distance unit',
                        'distanceUnit',
                        'kilometers',
                        {'kilometers': 'Kilometers', 'miles': 'Miles'}),
                    _choice(context, app, 'Navigation labels', 'language', 'en',
                        {'en': 'English', 'fil': 'Filipino'}),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.home_outlined),
                        title: const Text('Home address',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                            value(app.settings, 'homeAddress',
                                'Add a starting point for routes'),
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => _address(
                            context, app, 'homeAddress', 'Home address')),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.work_outline),
                        title: const Text('Work address',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                            value(app.settings, 'workAddress',
                                'Add a starting point for routes'),
                            style: const TextStyle(fontSize: 11)),
                        onTap: () => _address(
                            context, app, 'workAddress', 'Work address')),
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.my_location),
                        title: const Text('Use current location',
                            style: TextStyle(fontSize: 12)),
                        subtitle: Text(
                            app.locationBusy
                                ? 'Waiting for your location…'
                                : 'Used for nearby distances in this session',
                            style: const TextStyle(fontSize: 10)),
                        onTap: app.locationBusy
                            ? null
                            : () async {
                                final point =
                                    await requestUserLocation(context);
                                if (point != null && context.mounted)
                                  toast(context, 'Location updated.');
                              }),
                  ])),
                  const SectionTitle('About PasyalPH'),
                  Surface(
                      padding: 4,
                      child: Column(children: [
                        ListTile(
                            leading: const Icon(Icons.description_outlined),
                            title: const Text('Terms of Use',
                                style: TextStyle(fontSize: 12)),
                            onTap: () => openPage(
                                context, const PolicyPage(privacy: false))),
                        ListTile(
                            leading: const Icon(Icons.privacy_tip_outlined),
                            title: const Text('Privacy Policy',
                                style: TextStyle(fontSize: 12)),
                            onTap: () => openPage(
                                context, const PolicyPage(privacy: true))),
                        const ListTile(
                            leading: BrandLogo(size: 28),
                            title: Text('PasyalPH for Flutter',
                                style: TextStyle(fontSize: 12)),
                            subtitle: Text(
                                'Version 0.3 · Philippine adventures',
                                style: TextStyle(fontSize: 10)))
                      ])),
                  if (app.signedIn) ...[
                    const SectionTitle('Security'),
                    Surface(
                        child: Column(children: [
                      PrimaryButton(
                          label: 'Change password',
                          icon: Icons.key_outlined,
                          onPressed: () => perform(
                              context,
                              () => app.client.auth.resetPasswordForEmail(
                                  app.user!.email!,
                                  redirectTo: authRedirect),
                              success:
                                  'Check your email for a secure reset link.')),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: () async {
                            if (await confirm(context, 'Log out of PasyalPH?',
                                    'Your saved account data will stay on your account.',
                                    action: 'Log out') &&
                                context.mounted)
                              await perform(
                                  context, () => app.client.auth.signOut());
                          },
                          icon: const Icon(Icons.logout, size: 17),
                          label: const Text('Log out')),
                      TextButton(
                          onPressed: () =>
                              openPage(context, const DeleteAccountPage()),
                          style: TextButton.styleFrom(
                              foregroundColor:
                                  Theme.of(context).colorScheme.error),
                          child: const Text('Delete Account'))
                    ])),
                  ],
                ])));
  }

  Widget _choice(BuildContext context, AppState app, String label, String key,
          String fallback, Map<String, String> options) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: InputDecorator(
              decoration: InputDecoration(labelText: label),
              child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                      isDense: true,
                      isExpanded: true,
                      value: options.containsKey(app.settings[key])
                          ? app.settings[key]
                          : fallback,
                      items: options.entries
                          .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value,
                                  style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (v) => perform(
                          context, () => app.updateSettings({key: v}))))));
  Future<void> _address(
      BuildContext context, AppState app, String key, String label) async {
    final input = TextEditingController(text: value(app.settings, key));
    final next = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(label),
                content: TextField(
                    controller: input,
                    maxLength: 250,
                    decoration: const InputDecoration(
                        hintText: 'Address, city, province')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, input.text.trim()),
                      child: const Text('Save'))
                ]));
    input.dispose();
    if (next != null && context.mounted)
      await perform(context, () => app.updateSettings({key: next}),
          success: 'Address saved.');
  }
}

class ProfileForm extends StatefulWidget {
  const ProfileForm({super.key});
  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final form = GlobalKey<FormState>(),
      name = TextEditingController(),
      username = TextEditingController(),
      phone = TextEditingController();
  bool initialized = false, busy = false;
  String lastName = '', lastUsername = '', lastPhone = '';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    if (!initialized || name.text == lastName) name.text = app.name;
    if (!initialized || username.text == lastUsername)
      username.text = value(app.settings, 'username');
    if (!initialized || phone.text == lastPhone)
      phone.text = value(app.settings, 'phone');
    lastName = app.name;
    lastUsername = value(app.settings, 'username');
    lastPhone = value(app.settings, 'phone');
    initialized = true;
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Form(
        key: form,
        child: Column(children: [
          Field('Full name', name, required: true, maxLength: 100),
          Field('Username', username, maxLength: 40),
          Field('Mobile number (optional)', phone,
              keyboard: TextInputType.phone, maxLength: 25),
          Text('Account created: ${app.user?.createdAt.split('T').first ?? ''}',
              style: const TextStyle(fontSize: 10, color: muted)),
          const SizedBox(height: 12),
          PrimaryButton(
              label: 'Save profile',
              busy: busy,
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                setState(() => busy = true);
                await perform(
                    context,
                    () => app.updateSettings({
                          'name': name.text.trim(),
                          'username': username.text.trim(),
                          'phone': phone.text.trim()
                        }),
                    success: 'Profile saved.');
                if (mounted) setState(() => busy = false);
              }),
          TextButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      await perform(context, () async {
                        final photo = await uploadImage(app);
                        if (photo != null)
                          await app.updateSettings({'avatar': photo});
                      });
                      if (mounted) setState(() => busy = false);
                    },
              icon: const Icon(Icons.photo_camera_outlined, size: 16),
              label: const Text('Upload profile photo',
                  style: TextStyle(fontSize: 11)))
        ]));
  }
}

class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key});
  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  final form = GlobalKey<FormState>(),
      password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Choose a new password')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Use the secure reset link from your email before setting a new password.'),
        const SizedBox(height: 20),
        Form(
            key: form,
            child: Column(children: [
              Field('New password', password,
                  obscure: true, required: true, minLength: 12, maxLength: 128),
              Field('Confirm password', confirmation,
                  obscure: true,
                  validator: (v) =>
                      v == password.text ? null : 'Passwords must match.'),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              PrimaryButton(
                  label: 'Save new password',
                  busy: busy,
                  onPressed: () async {
                    if (!form.currentState!.validate()) return;
                    final app = AppScope.of(context);
                    setState(() => busy = true);
                    try {
                      await app.client.auth
                          .updateUser(UserAttributes(password: password.text));
                      app.recovery = false;
                      if (context.mounted) {
                        toast(context, 'Password updated.');
                        Navigator.pop(context);
                      }
                    } catch (e) {
                      if (mounted) setState(() => error = errorText(e));
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  })
            ]))
      ]));
}

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});
  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('Delete Account')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Surface(
              child: Text(
                  'Permanently delete your sign-in, profile, reviews, reports, photos, and unverified listings. Verified business listings must be transferred first. This cannot be undone.')),
          const SizedBox(height: 20),
          if (app.user?.appMetadata['provider'] == 'email')
            Field('Current password', password, obscure: true),
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          PrimaryButton(
              label: 'Permanently delete account',
              busy: busy,
              onPressed: () async {
                if (!await confirm(context, 'Delete your PasyalPH account?',
                        'This permanently deletes your account and its private data.',
                        action: 'Delete account') ||
                    !context.mounted) return;
                setState(() => busy = true);
                try {
                  app.requireUser();
                  if (app.user!.appMetadata['provider'] == 'email') {
                    await app.client.auth.signInWithPassword(
                        email: app.user!.email!, password: password.text);
                  }
                  final r = await app.client.functions
                      .invoke('delete-account', body: {'confirm': 'DELETE'});
                  if (r.status != 200 || r.data['deleted'] != true)
                    throw Exception(
                        r.data['error'] ?? 'Deletion could not be completed.');
                  await app.client.auth.signOut(scope: SignOutScope.local);
                  await app.refresh();
                  if (context.mounted) {
                    toast(context, 'Your account was deleted.');
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) setState(() => error = errorText(e));
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              })
        ]));
  }
}

class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key, required this.privacy});
  final bool privacy;
  @override
  Widget build(BuildContext context) {
    final sections = privacy
        ? {
            'Information handled':
                'We use your account name and email. Optional username, phone, profile photo, saved places, preferences, reviews, trip plans, reports, and business registrations provide the app’s features.',
            'Location and maps':
                'Location is requested only when you use a location feature. It stays in the current app session. OpenStreetMap, Nominatim and OSRM process map, address-search and routing requests. A location link is copied only when you choose to share it.',
            'Storage and visibility':
                'Supabase Auth provides sign-in; Supabase Database and Storage hold account data and photos. Reviews and approved listings are public. Uploaded profile and listing photos have public URLs. Local sample saves and fallback trip plans stay on this device.',
            'Travel assistant':
                'Catalog mode searches the app’s sample and live listings on your device. When a configured AI service is available, your chat and relevant catalog information are sent to that service through a Supabase Edge Function. Do not include sensitive personal information.',
            'Your choices':
                'You may edit profile details, decline location access, remove reviews and saved places, sign out, and request account deletion. Verified businesses must first be transferred. These draft policies need the operator’s legal contact details before public launch.',
          }
        : {
            'Using PasyalPH':
                'PasyalPH helps people discover tourist spots, food places, stays, and routes. Provide accurate account information, protect your credentials, and use the service lawfully and respectfully.',
            'Places, reviews, and estimates':
                'Confirm rates, opening hours, transport, and availability with providers before traveling. The app does not make bookings or guarantee fares or outcomes. Original sample content is labeled and is not independently verified.',
            'Your contributions':
                'Post lawful, honest and relevant reviews and business information. Do not impersonate others or upload content you cannot share. Owner applications and listings require review before publishing.',
            'Account access and deletion':
                'Supabase email verification protects account features. Business tools depend on approved applications and database permissions. Verified listings must be transferred before account deletion.',
            'Draft for review':
                'The operator’s legal identity, contact details, governing law, and dispute process must be supplied before these terms are final.',
          };
    return Scaffold(
        appBar:
            AppBar(title: Text(privacy ? 'Privacy Policy' : 'Terms of Use')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const StatusPill('Draft for review'),
          const SizedBox(height: 14),
          const Text('Updated November 8, 2026',
              style: TextStyle(color: muted, fontSize: 11)),
          for (final section in sections.entries) ...[
            SectionTitle(section.key),
            Surface(child: Text(section.value))
          ]
        ]));
  }
}
