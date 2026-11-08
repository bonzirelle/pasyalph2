import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pasyalph_supabase_flutter/main.dart';
import 'package:pasyalph_supabase_flutter/app_state.dart';
import 'package:pasyalph_supabase_flutter/assistant.dart';
import 'package:pasyalph_supabase_flutter/account.dart';
import 'package:pasyalph_supabase_flutter/ui.dart';

late List<JsonMap> seed;

Future<AppState> fixture({MockClient? transport}) async {
  SharedPreferences.setMockInitialValues({});
  final client = SupabaseClient(
      'https://example.supabase.co', 'public-test-key',
      httpClient:
          transport ?? MockClient((_) async => http.Response('[]', 200)),
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
      ));
  final state = AppState(client, await SharedPreferences.getInstance());
  state.catalog = seed.map((p) => Map<String, dynamic>.from(p)).toList();
  state.places = [...state.catalog];
  state.loading = false;
  return state;
}

Future<void> start(WidgetTester tester, AppState state,
    {Size size = const Size(430, 850)}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(PasyalPH(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Let’s explore'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    seed = (jsonDecode(await rootBundle.loadString('assets/data/catalog.json'))
            as List)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    for (final entry in {
      'Jakarta': 'PlusJakartaSans.ttf',
      'Fraunces': 'Fraunces.ttf'
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
  });
  test(
      'Original catalog has 45 unique sample IDs, valid coordinates and separate sample reviews',
      () async {
    final app = await fixture();
    expect(app.catalog.length, 45);
    expect(app.catalog.map((p) => p['id']).toSet().length, 45);
    for (final p in app.catalog) {
      expect(p['is_sample'], true);
      expect(number(p['lat']), inInclusiveRange(4.2, 21.5));
      expect(number(p['lng']), inInclusiveRange(116, 127));
      expect(p['image'], startsWith('assets/images/'));
      expect(app.rating(p), 'New');
    }
    app.dispose();
    await app.client.dispose();
  });
  test('Web deep links select their initial named route', () {
    expect(
        initialRouteFromUri(Uri.parse('https://example.test/admin')), '/admin');
    expect(initialRouteFromUri(Uri.parse('https://example.test/#/admin')),
        '/admin');
    expect(initialRouteFromUri(Uri.parse('https://example.test/')), '/');
  });
  test('Sample saves persist locally without creating Supabase rows', () async {
    final app = await fixture();
    final p = app.catalog.first;
    expect(await app.toggleSave(p), contains('this device'));
    expect(app.isSaved(p), true);
    expect(app.prefs.getStringList('sample-saves-guest'), contains(p['id']));
    await app.toggleSave(p);
    expect(app.isSaved(p), false);
    app.dispose();
    await app.client.dispose();
  });
  test('A sample saved before publication can still be removed', () async {
    final app = await fixture();
    final place = app.catalog.first;
    await app.toggleSave(place);
    app.remoteIds.add('${place['id']}');
    await app.toggleSave(place);
    expect(app.isSaved(place), false);
    expect(app.prefs.getStringList('sample-saves-guest'), isEmpty);
    app.dispose();
    await app.client.dispose();
  });
  test('Guest itineraries save locally without a cloud account', () async {
    final app = await fixture();
    expect(await app.savePlan('A day out', ['taal-view'], 'Pack water'), false);
    expect(app.hasLocalPlans, true);
    final stored = jsonDecode(app.prefs.getString('plans-guest')!) as List;
    expect(stored.single['title'], 'A day out');
    await app.deletePlan(app.plans.single);
    expect(jsonDecode(app.prefs.getString('plans-guest')!), isEmpty);
    app.dispose();
    await app.client.dispose();
  });
  test('Concurrent preference changes preserve both values', () async {
    final app = await fixture();
    await Future.wait([
      app.updateSettings({'distanceUnit': 'miles'}),
      app.updateSettings({'colorScheme': 'night'}),
    ]);
    expect(app.settings['distanceUnit'], 'miles');
    expect(app.settings['colorScheme'], 'night');
    final stored = jsonDecode(app.prefs.getString('settings-guest')!);
    expect(stored['distanceUnit'], 'miles');
    expect(stored['colorScheme'], 'night');
    app.dispose();
    await app.client.dispose();
  });
  test('An empty live catalog does not resurrect moderated samples', () async {
    var published = true;
    final app = await fixture(
        transport: MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/places') && published
                ? [seed.first]
                : []),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
            request: request)));
    await app.refresh();
    expect(app.loadError, isNull);
    expect(app.places.length, 1);
    published = false;
    await app.refresh();
    expect(app.places, isEmpty);
    expect(app.prefs.getBool('live-catalog-seen'), true);
    app.dispose();
    await app.client.dispose();
  });
  test('Finishing a refresh after disposal does not notify dead widgets',
      () async {
    final gate = Completer<void>();
    final app = await fixture(transport: MockClient((request) async {
      await gate.future;
      return http.Response('[]', 200, request: request);
    }));
    final pending = app.refresh();
    app.dispose();
    gate.complete();
    await pending;
    await app.client.dispose();
  });
  test('Device-only plans survive when cloud trip plans become available',
      () async {
    const uid = '11111111-1111-4111-8111-111111111111';
    var backendReady = false;
    final token =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({
                  'sub': uid,
                  'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
                }))).replaceAll('=', '')}.test-signature';
    final app = await fixture(transport: MockClient((request) async {
      if (request.url.path.endsWith('/token'))
        return http.Response(
            jsonEncode({
              'access_token': token,
              'refresh_token': 'test-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': uid,
                'aud': 'authenticated',
                'email': 'traveler@example.test',
                'created_at': '2026-01-01T00:00:00Z',
                'email_confirmed_at': '2026-01-01T00:00:00Z',
                'app_metadata': {},
                'user_metadata': {}
              },
            }),
            200,
            request: request);
      if (request.url.path.endsWith('/trip_plans')) {
        if (!backendReady)
          return http.Response(
              '{"code":"PGRST205","message":"Table missing"}', 404,
              request: request);
        return http.Response(
            '[{"id":"cloud-plan","title":"Cloud trip","place_ids":[],"notes":""}]',
            200,
            request: request);
      }
      if (request.url.path.endsWith('/profiles'))
        return http.Response(
            '[{"id":"$uid","role":"traveler","settings":{}}]', 200,
            request: request);
      return http.Response('[]', 200, request: request);
    }));
    await app.client.auth.signInWithPassword(
        email: 'traveler@example.test', password: 'test-password');
    expect(
        await app.savePlan('Device trip', ['taal-view'], 'Local notes'), false);
    backendReady = true;
    await app.refresh();
    expect(app.loadError, isNull);
    expect(app.plans.map((p) => p['title']),
        containsAll(['Device trip', 'Cloud trip']));
    expect(app.hasLocalPlans, true);
    final stored = jsonDecode(app.prefs.getString('plans-$uid')!) as List;
    expect(stored.length, 1);
    expect(stored.single['title'], 'Device trip');
    app.dispose();
    await app.client.dispose();
  });
  test('Nearby distances preserve fractions of a kilometer', () async {
    final app = await fixture();
    final p = app.catalog.first;
    final d = distanceKm(pilot, coordinates(p));
    expect(d, greaterThan(.1));
    expect(d, lessThan(.3));
    expect(app.distance(p), '0.2 km');
    app.dispose();
    await app.client.dispose();
  });
  test(
      'Nearby assistant requires a location and does not invent a nearby place',
      () async {
    final app = await fixture();
    final response = catalogAnswer(app, 'What is near me?');
    expect(response['place_ids'], isEmpty);
    expect(response['text'], contains('won’t assume'));
    app.selectLocation(pilot, 'Tagaytay');
    final located = catalogAnswer(app, 'Food near me');
    expect(located['place_ids'], isNotEmpty);
    expect(located['text'], contains('straight-line'));
    app.dispose();
    await app.client.dispose();
  });
  testWidgets(
      'Mobile Explore searches original catalog and opens place details',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await start(tester, app);
    expect(find.text('45 places to explore'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'Taal Vista');
    await tester.pumpAndSettle();
    expect(find.text('1 places to explore'), findsOneWidget);
    await tester.ensureVisible(find.text('Taal Vista Viewpoint').first);
    await tester.tap(find.text('Taal Vista Viewpoint').first);
    await tester.pumpAndSettle();
    expect(find.text('Original sample'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets('Guest can save a sample and find it in Saved', (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await start(tester, app);
    await tester.ensureVisible(find.byTooltip('Save place').first);
    await tester.tap(find.byTooltip('Save place').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved').last);
    await tester.pumpAndSettle();
    expect(app.localSaved, isNotEmpty);
    expect(find.text('Saved places'), findsOneWidget);
    expect(find.text('Taal Vista Viewpoint'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets(
      'Desktop frame renders Explore without overflow and exports preview',
      (tester) async {
    debugDisableShadows = false;
    final app = (await tester.runAsync(fixture))!;
    await tester.binding.setSurfaceSize(const Size(1100, 850));
    final key = GlobalKey();
    await tester
        .pumpWidget(RepaintBoundary(key: key, child: PasyalPH(state: app)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Let’s explore'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final bounds = tester.getSize(find.byType(Scaffold).first);
    expect(bounds.width, 430);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('artifacts').createSync(recursive: true);
      File('artifacts/explore-desktop.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets(
      'Sign-up form validates email and password before contacting Supabase',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await start(tester, app);
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter at least 12 characters.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets('Email sign-in sends a link/code request and offers code entry',
      (tester) async {
    final requests = <http.Request>[];
    final app = (await tester
        .runAsync(() => fixture(transport: MockClient((request) async {
              requests.add(request);
              if (request.url.path.endsWith('/otp'))
                return http.Response('{}', 200, request: request);
              return http.Response('[]', 200, request: request);
            }))))!;
    await start(tester, app);
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('account-email')), 'traveler@example.test');
    await tester.tap(find.text('Email me a sign-in link or code'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/auth/v1/otp'));
    final payload = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect(payload['email'], 'traveler@example.test');
    expect(payload['create_user'], false);
    expect(find.text('6-digit email code (if provided)'), findsOneWidget);
    expect(find.textContaining('Open its link to log in'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets('Email link request rejects an invalid address without sending',
      (tester) async {
    var otpRequests = 0;
    final app = (await tester
        .runAsync(() => fixture(transport: MockClient((request) async {
              if (request.url.path.endsWith('/otp')) otpRequests++;
              return http.Response('{}', 200, request: request);
            }))))!;
    await start(tester, app);
    await tester.tap(find.text('Log in').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('account-email')), 'not-an-email');
    await tester.tap(find.text('Email me a sign-in link or code'));
    await tester.pumpAndSettle();

    expect(otpRequests, 0);
    expect(find.text('Enter a valid email address first.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets('Guest trip plans remain accessible from Profile',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await app.savePlan('Weekend in Tagaytay', ['taal-view'], 'Bring water');
    await start(tester, app);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trip plans').first);
    await tester.pumpAndSettle();
    expect(find.text('Weekend in Tagaytay'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
  testWidgets('Profile refresh updates untouched fields and preserves edits',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    app.settings = {'name': 'Initial name', 'username': 'initial'};
    await tester.pumpWidget(AppScope(
        state: app,
        child: MaterialApp(
            theme: appTheme(false),
            home: const Scaffold(
                body: SingleChildScrollView(child: ProfileForm())))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Unsaved name');
    app.settings = {'name': 'Remote name', 'username': 'remote'};
    app.selectLocation(pilot, 'Refresh');
    await tester.pumpAndSettle();
    final fields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields[0].controller!.text, 'Unsaved name');
    expect(fields[1].controller!.text, 'remote');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await tester.runAsync(() => app.client.dispose());
  });
}
