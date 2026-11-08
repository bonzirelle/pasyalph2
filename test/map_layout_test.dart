import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pasyalph_supabase_flutter/app_state.dart';
import 'package:pasyalph_supabase_flutter/map_page.dart';
import 'package:pasyalph_supabase_flutter/ui.dart';

class OfflineTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      const AssetImage('assets/images/taal.jpg');
}

late List<JsonMap> catalog;
Future<AppState> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final client = SupabaseClient(
      'https://example.supabase.co', 'public-test-key',
      httpClient: MockClient(
          (request) async => http.Response('[]', 200, request: request)),
      authOptions: const AuthClientOptions(autoRefreshToken: false));
  return AppState(client, await SharedPreferences.getInstance())
    ..catalog = catalog
    ..places = [...catalog]
    ..loading = false;
}

Future<void> mountMap(WidgetTester tester, AppState app, Size size,
    {bool planning = false}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(AppScope(
      state: app,
      child: MaterialApp(
          theme: appTheme(false),
          home: MapPage(
              embedded: true,
              destination: planning ? catalog.first : null,
              tileProvider: OfflineTiles()))));
  await tester.pumpAndSettle();
}

Future<void> cleanup(WidgetTester tester, AppState app) async {
  await tester.pumpWidget(const SizedBox());
  app.dispose();
  await tester.runAsync(() => app.client.dispose());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    catalog =
        (jsonDecode(await rootBundle.loadString('assets/data/catalog.json'))
                as List)
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
    for (final font in {
      'Jakarta': 'assets/fonts/PlusJakartaSans.ttf',
      'Fraunces': 'assets/fonts/Fraunces.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf'
    }.entries) {
      final loader = FontLoader(font.key)..addFont(rootBundle.load(font.value));
      await loader.load();
    }
  });
  for (final size in [
    const Size(320, 480),
    const Size(430, 640),
    const Size(430, 780)
  ]) {
    testWidgets(
        'Search, filters and map controls do not overlap at ${size.width}x${size.height}',
        (tester) async {
      final app = (await tester.runAsync(fixture))!;
      await mountMap(tester, app, size);
      final search = tester.getRect(find.byKey(const ValueKey('map-search')));
      final filters =
          tester.getRect(find.byKey(const ValueKey('map-categories')));
      final controls =
          tester.getRect(find.byKey(const ValueKey('map-controls')));
      expect(search.top, 14);
      expect(search.bottom, lessThan(filters.top));
      expect(filters.bottom, lessThan(controls.top));
      expect(search.overlaps(controls), false);
      expect(controls.right, closeTo(size.width - 14, .1));
      expect(controls.bottom, lessThan(size.height - 22));
      final clusters = find.byWidgetPredicate((widget) =>
          widget is Tooltip &&
          (widget.message?.contains('places — zoom in') ?? false));
      final centers = clusters
          .evaluate()
          .map((element) => tester.getCenter(find.byWidget(element.widget)))
          .toList();
      for (var i = 0; i < centers.length; i++) {
        for (var j = i + 1; j < centers.length; j++)
          expect((centers[i] - centers[j]).distance, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
      await cleanup(tester, app);
    });
    testWidgets(
        'Route panel stays separate from controls at ${size.width}x${size.height}',
        (tester) async {
      final app = (await tester.runAsync(fixture))!;
      await mountMap(tester, app, size, planning: true);
      final panel =
          tester.getRect(find.byKey(const ValueKey('map-place-sheet')));
      final controls = find.byKey(const ValueKey('map-controls'));
      if (controls.evaluate().isNotEmpty)
        expect(tester.getRect(controls).bottom, lessThan(panel.top));
      expect(panel.bottom, closeTo(size.height - 30, .1));
      expect(panel.height, lessThanOrEqualTo(size.height * .52 + .1));
      expect(tester.takeException(), isNull);
      await cleanup(tester, app);
    });
  }
  testWidgets(
      'Map options keep layers and sharing accessible on a short screen',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await mountMap(tester, app, const Size(320, 480), planning: true);
    await tester.tap(find.byTooltip('Map options'));
    await tester.pumpAndSettle();
    expect(find.text('Streets'), findsOneWidget);
    expect(find.text('Satellite'), findsOneWidget);
    expect(find.text('Copy location link'), findsOneWidget);
    expect(find.text('Zoom in'), findsOneWidget);
    await tester.tap(find.text('Satellite'));
    await tester.pumpAndSettle();
    expect(tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
        contains('World_Imagery'));
    expect(tester.takeException(), isNull);
    await cleanup(tester, app);
  });
  testWidgets('Focusing search clears the side rail until search is dismissed',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await mountMap(tester, app, const Size(430, 640));
    await tester.tap(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-controls')), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'Tagaytay');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isEmpty);
    expect(tester.takeException(), isNull);
    await cleanup(tester, app);
  });
  testWidgets('Selected destination remains visible above the directions panel',
      (tester) async {
    final app = (await tester.runAsync(fixture))!;
    await mountMap(tester, app, const Size(430, 640), planning: true);
    final marker = find.byTooltip('Taal Vista Viewpoint');
    final panel = tester.getRect(find.byKey(const ValueKey('map-place-sheet')));
    expect(tester.getRect(marker).center.dy, lessThan(panel.top));
    await tester.tap(marker);
    await tester.pumpAndSettle();
    expect(find.text('Details'), findsOneWidget);
    expect(tester.getRect(find.byKey(const ValueKey('map-place-sheet'))).height,
        lessThanOrEqualTo(184));
    expect(tester.takeException(), isNull);
    await cleanup(tester, app);
  });
}
