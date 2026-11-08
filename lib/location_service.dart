import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'location_environment_stub.dart'
    if (dart.library.js_interop) 'location_environment_web.dart' as environment;

enum LocationProblem {
  denied,
  blocked,
  deviceBlocked,
  serviceOff,
  insecure,
  timeout,
  unavailable
}

class LocationFailure implements Exception {
  const LocationFailure(this.problem, this.message);
  final LocationProblem problem;
  final String message;
  String get title => switch (problem) {
        LocationProblem.denied => 'Location permission needed',
        LocationProblem.blocked => 'Location access is blocked',
        LocationProblem.deviceBlocked => 'Enable device location',
        LocationProblem.serviceOff => 'Location services are off',
        LocationProblem.insecure => 'Open a secure connection',
        LocationProblem.timeout => 'Location took too long',
        LocationProblem.unavailable => 'Location is unavailable',
      };
  @override
  String toString() => message;
}

class LocationService {
  LocationService(
      {GeolocatorPlatform? platform,
      bool? web,
      bool Function()? secureContext,
      this.positionTimeout = const Duration(seconds: 20)})
      : _platform = platform,
        isWeb = web ?? kIsWeb,
        _secureContext =
            secureContext ?? (() => environment.locationContextIsSecure);
  final GeolocatorPlatform? _platform;
  GeolocatorPlatform get platform => _platform ?? GeolocatorPlatform.instance;
  final bool isWeb;
  final bool Function() _secureContext;
  final Duration positionTimeout;
  bool get embedded => isWeb && environment.locationContextIsEmbedded;

  Future<Position> current() async {
    try {
      if (isWeb) {
        if (!_secureContext())
          throw const LocationFailure(LocationProblem.insecure,
              'Open PasyalPH using HTTPS or http://localhost:3000/. Browsers cannot share location from an insecure network address.');
        // Reading position asks the browser for permission. The web plugin's
        // requestPermission also reads position and conflates GPS failures
        // with permanent denial. Avoid that extra, unbounded read.
      } else {
        if (!await platform
            .isLocationServiceEnabled()
            .timeout(const Duration(seconds: 5))) {
          throw const LocationFailure(LocationProblem.serviceOff,
              'Turn on Location Services on your device, then try again.');
        }
        var permission = await platform
            .checkPermission()
            .timeout(const Duration(seconds: 5));
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.unableToDetermine) {
          permission = await platform
              .requestPermission()
              .timeout(const Duration(seconds: 60));
        }
        if (permission == LocationPermission.deniedForever)
          throw const LocationFailure(LocationProblem.blocked,
              'Location permission is blocked for PasyalPH. Open app settings, allow location while using the app, then return and try again.');
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.unableToDetermine)
          throw const LocationFailure(LocationProblem.denied,
              'Allow location while using PasyalPH to show your position. Approximate location is enough to discover nearby places.');
      }
      final options = LocationSettings(
          accuracy: LocationAccuracy.medium, timeLimit: positionTimeout);
      // A one-result web stream clears its browser watch on success, denial or
      // timeout. An outer Future timeout on getCurrentPosition cannot cancel
      // the underlying browser read (whose timeout units vary by plugin version).
      final position = isWeb
          ? await platform
              .getPositionStream(locationSettings: options)
              .timeout(positionTimeout)
              .first
          : await platform
              .getCurrentPosition(locationSettings: options)
              .timeout(positionTimeout);
      if (!position.latitude.isFinite ||
          !position.longitude.isFinite ||
          position.latitude.abs() > 90 ||
          position.longitude.abs() > 180) {
        throw const LocationFailure(LocationProblem.unavailable,
            'The device returned an invalid position. Try again or enter a city manually.');
      }
      return position;
    } on LocationFailure {
      rethrow;
    } on PermissionDeniedException {
      LocationPermission permission = LocationPermission.unableToDetermine;
      try {
        permission = await platform
            .checkPermission()
            .timeout(const Duration(seconds: 2));
      } catch (_) {/* Some browsers do not support permission queries. */}
      if (isWeb &&
          [LocationPermission.always, LocationPermission.whileInUse]
              .contains(permission)) {
        throw const LocationFailure(LocationProblem.deviceBlocked,
            'Your browser has permission, but the device is blocking location. Turn on Location Services in your device settings and allow your browser or desktop apps to use it.');
      }
      if (isWeb)
        throw LocationFailure(
            permission == LocationPermission.deniedForever
                ? LocationProblem.blocked
                : LocationProblem.denied,
            'Open the site controls beside the browser address, set Location to Allow, then try again. If you are using an embedded preview, open PasyalPH directly in Chrome or Edge.');
      throw const LocationFailure(LocationProblem.denied,
          'Location permission was not granted. Allow location in app settings or try again.');
    } on LocationServiceDisabledException {
      throw const LocationFailure(LocationProblem.serviceOff,
          'Turn on Location Services on your device, then try again.');
    } on TimeoutException {
      throw const LocationFailure(LocationProblem.timeout,
          'We could not get a position in time. Check that device location is on, then retry. You can also enter a city or starting address manually.');
    } on UnsupportedError {
      throw const LocationFailure(LocationProblem.unavailable,
          'This preview cannot provide device location. Open the app directly in Chrome or Edge, or enter a city manually.');
    } catch (_) {
      throw const LocationFailure(LocationProblem.unavailable,
          'Your device could not determine a position. Turn on Location Services, check your connection, and retry. You can also enter a city manually.');
    }
  }

  Future<bool> openSettings(LocationFailure failure) async {
    if (isWeb) return false;
    try {
      return failure.problem == LocationProblem.serviceOff ||
              failure.problem == LocationProblem.deviceBlocked
          ? await platform.openLocationSettings()
          : await platform.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
