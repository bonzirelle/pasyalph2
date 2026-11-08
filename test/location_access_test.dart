import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pasyalph_supabase_flutter/app_state.dart';
import 'package:pasyalph_supabase_flutter/location_service.dart';
import 'package:pasyalph_supabase_flutter/location_ui.dart';
import 'package:pasyalph_supabase_flutter/ui.dart';

Position position({double latitude = 14.5995, double longitude = 120.9842}) =>
    Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime(2026, 11, 8),
        accuracy: 50,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);

class FakeLocationPlatform extends GeolocatorPlatform {
  bool enabled = true, queryUnsupported = false;
  LocationPermission permission = LocationPermission.whileInUse,
      requested = LocationPermission.whileInUse;
  int positionCalls = 0,
      checkCalls = 0,
      requestCalls = 0,
      serviceCalls = 0,
      appSettingsCalls = 0,
      locationSettingsCalls = 0,
      cancelledWatches = 0;
  LocationSettings? settings;
  Future<Position> Function()? read;
  @override
  Future<bool> isLocationServiceEnabled() async {
    serviceCalls++;
    return enabled;
  }

  @override
  Future<LocationPermission> checkPermission() async {
    checkCalls++;
    if (queryUnsupported) throw UnsupportedError('Permissions API unavailable');
    return permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls++;
    return requested;
  }

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positionCalls++;
    settings = locationSettings;
    return read == null ? position() : await read!();
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    var cancelled = false;
    late StreamController<Position> controller;
    controller = StreamController<Position>(onListen: () {
      getCurrentPosition(locationSettings: locationSettings).then((value) {
        if (!cancelled) controller.add(value);
      }, onError: (Object error, StackTrace stack) {
        if (!cancelled) controller.addError(error, stack);
      });
    }, onCancel: () {
      cancelled = true;
      cancelledWatches++;
    });
    return controller.stream;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }
}

Matcher problem(LocationProblem type) => isA<LocationFailure>()
    .having((failure) => failure.problem, 'problem', type);
Future<AppState> stateFor(LocationService service) async {
  SharedPreferences.setMockInitialValues({});
  return AppState(
      SupabaseClient('https://example.supabase.co', 'test-public-key',
          httpClient: MockClient(
              (request) async => http.Response('[]', 200, request: request)),
          authOptions: const AuthClientOptions(autoRefreshToken: false)),
      await SharedPreferences.getInstance(),
      locationService: service);
}

Future<void> showRequest(WidgetTester tester, AppState state) async {
  await tester.binding.setSurfaceSize(const Size(430, 700));
  await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
          theme: appTheme(false),
          home: Scaffold(
              body: Builder(
                  builder: (context) => Center(
                      child: FilledButton(
                          onPressed: () => requestUserLocation(context),
                          child: const Text('Use location'))))))));
  await tester.runAsync(() async {
    await tester.tap(find.text('Use location'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  });
  for (var i = 0; i < 10 && find.byType(AlertDialog).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

void main() {
  test('Web requests position once without the unbounded permission helper',
      () async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.denied;
    final result =
        await LocationService(platform: platform, web: true).current();
    expect(result.latitude, 14.5995);
    expect(platform.positionCalls, 1);
    expect(platform.requestCalls, 0);
    expect(platform.checkCalls, 0);
    expect(platform.serviceCalls, 0);
    expect(platform.cancelledWatches, 1);
    expect(platform.settings!.accuracy, LocationAccuracy.medium);
  });
  test('Web still requests location when permission queries are unsupported',
      () async {
    final platform = FakeLocationPlatform()..queryUnsupported = true;
    await LocationService(platform: platform, web: true).current();
    expect(platform.positionCalls, 1);
    expect(platform.checkCalls, 0);
  });
  test('An unavailable position is not misclassified as blocked permission',
      () async {
    final platform = FakeLocationPlatform()
      ..read = () => Future.error(const PositionUpdateException('No fix'));
    await expectLater(LocationService(platform: platform, web: true).current(),
        throwsA(problem(LocationProblem.unavailable)));
    expect(platform.checkCalls, 0);
    expect(platform.requestCalls, 0);
  });
  test('Browser denial provides site-permission recovery', () async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.deniedForever
      ..read = () => Future.error(const PermissionDeniedException('Denied'));
    await expectLater(LocationService(platform: platform, web: true).current(),
        throwsA(problem(LocationProblem.blocked)));
    expect(platform.requestCalls, 0);
  });
  test('Browser grant with OS denial is identified as device blocking',
      () async {
    final platform = FakeLocationPlatform()
      ..read = () => Future.error(const PermissionDeniedException('OS denied'));
    await expectLater(LocationService(platform: platform, web: true).current(),
        throwsA(problem(LocationProblem.deviceBlocked)));
  });
  test('Permission-query failure does not hide a browser permission error',
      () async {
    final platform = FakeLocationPlatform()
      ..queryUnsupported = true
      ..read = () => Future.error(const PermissionDeniedException('Denied'));
    await expectLater(LocationService(platform: platform, web: true).current(),
        throwsA(problem(LocationProblem.denied)));
  });
  test('Browser position wait is bounded even when the plugin never returns',
      () async {
    final platform = FakeLocationPlatform()
      ..read = () => Completer<Position>().future;
    await expectLater(
        LocationService(
                platform: platform,
                web: true,
                positionTimeout: const Duration(milliseconds: 10))
            .current(),
        throwsA(problem(LocationProblem.timeout)));
    expect(platform.cancelledWatches, 1);
  });
  test('Insecure web pages do not attempt a permission request', () async {
    final platform = FakeLocationPlatform();
    await expectLater(
        LocationService(
            platform: platform,
            web: true,
            secureContext: () => false).current(),
        throwsA(problem(LocationProblem.insecure)));
    expect(platform.positionCalls, 0);
    expect(platform.requestCalls, 0);
  });
  test('Android-style first permission grant requests only once', () async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.denied;
    await LocationService(platform: platform, web: false).current();
    expect(platform.requestCalls, 1);
    expect(platform.positionCalls, 1);
    expect(platform.serviceCalls, 1);
  });
  test('Permanent native denial opens app settings without asking again',
      () async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.deniedForever;
    final service = LocationService(platform: platform, web: false);
    await expectLater(
        service.current(), throwsA(problem(LocationProblem.blocked)));
    expect(platform.requestCalls, 0);
    expect(platform.positionCalls, 0);
    expect(
        await service.openSettings(
            const LocationFailure(LocationProblem.blocked, 'Blocked')),
        true);
    expect(platform.appSettingsCalls, 1);
  });
  test('Disabled native services offer location settings', () async {
    final platform = FakeLocationPlatform()..enabled = false;
    final service = LocationService(platform: platform, web: false);
    await expectLater(
        service.current(), throwsA(problem(LocationProblem.serviceOff)));
    expect(platform.requestCalls, 0);
    expect(platform.positionCalls, 0);
    await service
        .openSettings(const LocationFailure(LocationProblem.serviceOff, 'Off'));
    expect(platform.locationSettingsCalls, 1);
  });
  test('Invalid coordinates do not become a current location', () async {
    final platform = FakeLocationPlatform()
      ..read = () async => position(latitude: double.nan);
    await expectLater(LocationService(platform: platform, web: true).current(),
        throwsA(problem(LocationProblem.unavailable)));
  });
  test('Concurrent requests share one position read and update app state',
      () async {
    final gate = Completer<Position>();
    final platform = FakeLocationPlatform()..read = () => gate.future;
    final state =
        await stateFor(LocationService(platform: platform, web: true));
    final first = state.locate(), second = state.locate();
    expect(identical(first, second), true);
    expect(state.locationBusy, true);
    gate.complete(position());
    await Future.wait([first, second]);
    expect(platform.positionCalls, 1);
    expect(state.location!.latitude, 14.5995);
    expect(state.locationLabel, 'Your current location');
    expect(state.locationBusy, false);
    state.dispose();
    await state.client.dispose();
  });
  testWidgets(
      'Blocked access shows recovery and can be dismissed without a fake position',
      (tester) async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.deniedForever
      ..read = () => Future.error(const PermissionDeniedException('Denied'));
    final state = (await tester.runAsync(
        () => stateFor(LocationService(platform: platform, web: true))))!;
    await showRequest(tester, state);
    expect(find.text('Location access is blocked'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(state.location, isNull);
    expect(state.locationBusy, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await tester.runAsync(() => state.client.dispose());
  });
  testWidgets('Retry succeeds after location permission is allowed',
      (tester) async {
    final platform = FakeLocationPlatform()
      ..permission = LocationPermission.deniedForever
      ..read = () => Future.error(const PermissionDeniedException('Denied'));
    final state = (await tester.runAsync(
        () => stateFor(LocationService(platform: platform, web: true))))!;
    await showRequest(tester, state);
    platform.permission = LocationPermission.whileInUse;
    platform.read = () async => position();
    await tester.runAsync(() async {
      await tester.tap(find.text('Try again'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(state.location!.latitude, 14.5995);
    expect(platform.positionCalls, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await tester.runAsync(() => state.client.dispose());
  });
}
