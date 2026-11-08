import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'app_state.dart';
import 'location_service.dart';
import 'ui.dart';

enum _LocationAction { retry, settings, browser }

Future<LatLng?> requestUserLocation(BuildContext context) async {
  final app = AppScope.of(context);
  while (context.mounted) {
    try {
      return await app.locate();
    } on LocationFailure catch (failure) {
      if (!context.mounted) return null;
      final service = app.locationService;
      final canOpenSettings = !service.isWeb &&
          [
            LocationProblem.blocked,
            LocationProblem.denied,
            LocationProblem.deviceBlocked,
            LocationProblem.serviceOff
          ].contains(failure.problem);
      final action = await showDialog<_LocationAction>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                icon: const Icon(Icons.location_on_outlined,
                    color: accent, size: 32),
                title: Text(failure.title),
                content: SingleChildScrollView(child: Text(failure.message)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Not now')),
                  if (service.isWeb && service.embedded)
                    TextButton(
                        onPressed: () => Navigator.pop(
                            dialogContext, _LocationAction.browser),
                        child: const Text('Open in browser')),
                  if (canOpenSettings)
                    TextButton(
                        onPressed: () => Navigator.pop(
                            dialogContext, _LocationAction.settings),
                        child: const Text('Open settings')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, _LocationAction.retry),
                      child: const Text('Try again')),
                ],
              ));
      if (!context.mounted || action == null) return null;
      if (action == _LocationAction.settings) {
        final opened = await service.openSettings(failure);
        if (context.mounted)
          toast(
              context,
              opened
                  ? 'Enable location in settings, then return and try again.'
                  : 'Open your device settings and allow location for PasyalPH.');
        return null;
      }
      if (action == _LocationAction.browser) {
        if (context.mounted) await openUrl(context, Uri.base.toString());
        return null;
      }
    }
  }
  return null;
}
