import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'app_state.dart';
import 'ui.dart';
import 'explore.dart';
import 'location_ui.dart';

Future<List<JsonMap>> geocodePH(String query) async {
  if (query.trim().length < 3)
    throw Exception(
        'Enter at least three characters, including a city or province.');
  final response = await http.get(
      Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query.trim(),
        'format': 'jsonv2',
        'countrycodes': 'ph',
        'limit': '5',
        'addressdetails': '1'
      }),
      headers: {
        'User-Agent': 'PasyalPH/0.3 (Philippines travel app)'
      }).timeout(const Duration(seconds: 15));
  if (response.statusCode != 200)
    throw Exception('Address search is unavailable. Try again later.');
  return (jsonDecode(response.body) as List)
      .map((r) => {
            'name': r['display_name'],
            'address': r['display_name'],
            'lat': number(r['lat']),
            'lng': number(r['lon']),
            'category': 'Search result'
          })
      .toList();
}

class MapPage extends StatefulWidget {
  const MapPage(
      {super.key, this.embedded = false, this.destination, this.tileProvider});
  final bool embedded;
  final JsonMap? destination;
  final TileProvider? tileProvider;
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final controller = MapController(),
      search = TextEditingController(),
      originText = TextEditingController();
  JsonMap? selected;
  LatLng? origin;
  List<JsonMap> results = [], steps = [], routeOptions = [];
  List<LatLng> route = [];
  String category = 'All', mode = 'Car';
  bool busy = false, planning = false, navigating = false;
  String? error;
  double meters = 0, seconds = 0;
  int step = 0, routeChoice = 0;
  String mapStyle = 'Streets';
  final searchFocus = FocusNode();
  double mapZoom = 12;
  double mapHeight = 600;
  StreamSubscription<Position>? tracking;
  @override
  void initState() {
    super.initState();
    selected = widget.destination;
    mapZoom = selected == null ? 12 : 14;
    planning = selected != null;
    searchFocus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    tracking?.cancel();
    controller.dispose();
    search.dispose();
    originText.dispose();
    searchFocus.removeListener(_focusChanged);
    searchFocus.dispose();
    super.dispose();
  }

  void choose(JsonMap p) {
    FocusScope.of(context).unfocus();
    tracking?.cancel();
    setState(() {
      navigating = false;
      selected = p;
      results = [];
      error = null;
      route = [];
      steps = [];
      planning = false;
    });
    controller.move(coordinates(p), 14,
        offset: Offset(0, -math.min(90.0, mapHeight * .16)));
  }

  Future<void> find() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    final local = AppScope.of(context)
        .publicPlaces
        .where((p) => '${p['name']} ${p['address']}'
            .toLowerCase()
            .contains(search.text.trim().toLowerCase()))
        .take(5)
        .toList();
    try {
      final found = await geocodePH(search.text);
      if (mounted) setState(() => results = [...local, ...found]);
    } catch (e) {
      if (mounted)
        setState(() {
          error = errorText(e);
          results = local;
        });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final point = await requestUserLocation(context);
      if (!mounted || point == null) return;
      setState(() {
        origin = point;
        originText.text = 'Your current location';
      });
      controller.move(point, 14,
          offset: Offset(
              0, selected == null ? 0 : -math.min(120.0, mapHeight * .18)));
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> calculate() async {
    if (selected == null || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (origin == null &&
          originText.text.trim().isNotEmpty &&
          originText.text != 'Your current location') {
        final points = await geocodePH(originText.text);
        if (points.isEmpty)
          throw Exception(
              'Starting address not found. Include the city and province.');
        if (!mounted) return;
        final picked = await showModalBottomSheet<JsonMap>(
            context: context,
            showDragHandle: true,
            builder: (c) => ListView(shrinkWrap: true, children: [
                  const ListTile(title: Text('Choose your starting point')),
                  for (final p in points)
                    ListTile(
                        title: Text('${p['name']}',
                            style: const TextStyle(fontSize: 12)),
                        onTap: () => Navigator.pop(c, p))
                ]));
        if (picked == null) return;
        origin = coordinates(picked);
      }
      origin ??= AppScope.of(context).location;
      if (origin == null)
        throw Exception(
            'Choose your current location or enter a starting address.');
      final end = coordinates(selected!);
      if (mode == 'Transit') {
        if (mounted)
          await openUrl(context,
              'https://www.google.com/maps/dir/?api=1&origin=${origin!.latitude},${origin!.longitude}&destination=${end.latitude},${end.longitude}&travelmode=${mode == 'Walking' ? 'walking' : 'transit'}');
        return;
      }
      final router = mode == 'Walking'
          ? 'https://routing.openstreetmap.de/routed-foot'
          : mode == 'Cycling'
              ? 'https://routing.openstreetmap.de/routed-bike'
              : 'https://router.project-osrm.org';
      final response = await http
          .get(Uri.parse(
              '$router/route/v1/driving/${origin!.longitude},${origin!.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true&alternatives=true'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200)
        throw Exception(
            'Routing is unavailable. Use external directions instead.');
      final body = jsonDecode(response.body);
      if (body['code'] != 'Ok' || (body['routes'] as List).isEmpty)
        throw Exception('No route found. Try a different starting point.');
      routeOptions = (body['routes'] as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      selectRoute(0);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void selectRoute(int index) {
    tracking?.cancel();
    final r = routeOptions[index];
    if (!mounted) return;
    setState(() {
      navigating = false;
      routeChoice = index;
      route = (r['geometry']['coordinates'] as List)
          .map((c) => LatLng(number(c[1]), number(c[0])))
          .toList();
      meters = number(r['distance']);
      seconds = number(r['duration']);
      steps = (r['legs'][0]['steps'] as List)
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
      step = 0;
    });
    controller.fitCamera(CameraFit.coordinates(
        coordinates: route,
        padding: EdgeInsets.fromLTRB(30, 125, 30,
            (MediaQuery.sizeOf(context).height * .45).clamp(100, 280))));
  }

  Future<void> navigate() async {
    try {
      final current = await requestUserLocation(context);
      if (!mounted || current == null) return;
      origin = current;
      originText.text = 'Your current location';
      await calculate();
      if (!mounted || error != null || route.isEmpty) return;
      setState(() => navigating = true);
      tracking = Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.high, distanceFilter: 10))
          .listen((p) {
        if (!mounted) return;
        final point = LatLng(p.latitude, p.longitude);
        setState(() {
          origin = point;
          if (step < steps.length - 1) {
            final m = steps[step + 1]['maneuver']['location'];
            if (distanceKm(point, LatLng(number(m[1]), number(m[0]))) < .04)
              step++;
          }
        });
        controller.move(point, 17,
            offset: Offset(0, -math.min(120.0, mapHeight * .18)));
      }, onError: (e) {
        tracking?.cancel();
        if (mounted)
          setState(() {
            navigating = false;
            error =
                'Live location stopped. Check location permission and try again.';
          });
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final manualOrigin =
        origin != null && originText.text != 'Your current location';
    final markerPosition = manualOrigin ? origin : (app.location ?? origin);
    final places = app.publicPlaces
        .where((p) => category == 'All' || p['category'] == category)
        .toList();
    return Scaffold(
      appBar:
          widget.embedded ? null : AppBar(title: const Text('Explore the map')),
      body: LayoutBuilder(builder: (context, constraints) {
        final height = constraints.maxHeight;
        mapHeight = height;
        final compact =
            MediaQuery.viewInsetsOf(context).bottom > 0 || height < 360;
        final controlsTop = compact ? 80.0 : 124.0;
        const footer = 22.0;
        final panelLimit = selected == null
            ? 0.0
            : math.min(planning ? height * .52 : 184.0,
                math.max(0.0, height - controlsTop - footer - 24));
        final controlSpace = height - controlsTop - footer - panelLimit - 20;
        return Stack(
            key: const ValueKey('map-viewport'),
            fit: StackFit.expand,
            children: [
              FlutterMap(
                mapController: controller,
                options: MapOptions(
                  onMapReady: () {
                    if (selected != null) {
                      final visibleCenter =
                          (controlsTop + height - panelLimit - footer - 8) / 2;
                      controller.move(coordinates(selected!), 14,
                          offset: Offset(
                              0,
                              (visibleCenter - height / 2)
                                  .clamp(-140.0, 0.0)
                                  .toDouble()));
                    }
                  },
                  initialCenter:
                      selected == null ? pilot : coordinates(selected!),
                  initialZoom: selected == null ? 12 : 14,
                  minZoom: 4,
                  maxZoom: 18,
                  onPositionChanged: (camera, gesture) {
                    if (camera.zoom.floor() != mapZoom.floor())
                      setState(() => mapZoom = camera.zoom);
                  },
                  onTap: (_, point) {
                    FocusScope.of(context).unfocus();
                    if (results.isNotEmpty) setState(() => results = []);
                  },
                ),
                children: [
                  TileLayer(
                    tileProvider: widget.tileProvider,
                    fallbackUrl:
                        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
                    urlTemplate: mapStyle == 'Satellite'
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : mapStyle == 'Terrain'
                            ? 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png'
                            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.pasyalph.app',
                  ),
                  if (route.isNotEmpty)
                    PolylineLayer(polylines: [
                      Polyline(
                          points: route,
                          color: accent,
                          strokeWidth: 6,
                          borderColor: Colors.white,
                          borderStrokeWidth: 2)
                    ]),
                  MarkerLayer(markers: [
                    ..._placeMarkers(places),
                    if (selected != null && selected!['id'] == null)
                      Marker(
                          point: coordinates(selected!),
                          width: 44,
                          height: 44,
                          child: const Icon(Icons.location_on,
                              color: Colors.red, size: 38)),
                    if (markerPosition != null)
                      Marker(
                          point: markerPosition,
                          width: 22,
                          height: 22,
                          child: Semantics(
                              label: manualOrigin
                                  ? 'Starting point'
                                  : app.locationLabel,
                              child: Container(
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.blue,
                                      border: Border.all(
                                          color: Colors.white, width: 3))))),
                  ]),
                ],
              ),
              Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        key: const ValueKey('map-search'),
                        height: 52,
                        child: Material(
                          elevation: 5,
                          shadowColor: Colors.black26,
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(18),
                          clipBehavior: Clip.antiAlias,
                          child: TextField(
                            controller: search,
                            focusNode: searchFocus,
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(fontSize: 13),
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => find(),
                            decoration: InputDecoration(
                              hintText: 'Search places or addresses',
                              hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .65)),
                              prefixIcon: const Icon(Icons.search, size: 21),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              fillColor: theme.cardColor,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 15),
                              suffixIcon: busy
                                  ? const Padding(
                                      padding: EdgeInsets.all(17),
                                      child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)))
                                  : IconButton(
                                      tooltip: search.text.isEmpty
                                          ? 'Search map'
                                          : 'Clear search',
                                      onPressed: search.text.isEmpty
                                          ? find
                                          : () => setState(() {
                                                search.clear();
                                                results = [];
                                                error = null;
                                              }),
                                      icon: Icon(
                                          search.text.isEmpty
                                              ? Icons.arrow_forward
                                              : Icons.close,
                                          size: 19),
                                    ),
                            ),
                          ),
                        )),
                    if (!compact) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                          key: const ValueKey('map-categories'),
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            separatorBuilder: (_, i) =>
                                const SizedBox(width: 7),
                            itemBuilder: (context, i) {
                              final active = category == categories[i];
                              return Material(
                                  color: active ? ink : theme.cardColor,
                                  elevation: 2,
                                  shadowColor: Colors.black12,
                                  borderRadius: BorderRadius.circular(24),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () => setState(
                                        () => category = categories[i]),
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 15),
                                        child: Center(
                                            child: Text(categories[i],
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: active
                                                        ? Colors.white
                                                        : theme.colorScheme
                                                            .onSurface)))),
                                  ));
                            },
                          )),
                    ],
                    if (results.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: math.max(
                                  50,
                                  math.min(230,
                                      height - controlsTop - footer - 12))),
                          child: Material(
                            color: theme.cardColor,
                            elevation: 5,
                            borderRadius: BorderRadius.circular(18),
                            clipBehavior: Clip.antiAlias,
                            child: ListView(
                                shrinkWrap: true,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 5),
                                children: [
                                  for (final place in results)
                                    ListTile(
                                      leading: const Icon(
                                          Icons.location_on_outlined,
                                          size: 20,
                                          color: accent),
                                      title: Text(value(place, 'name'),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12)),
                                      onTap: () => choose(place),
                                    )
                                ]),
                          )),
                    ],
                  ])),
              if (results.isEmpty &&
                  !searchFocus.hasFocus &&
                  controlSpace >= 44)
                Positioned(
                  key: const ValueKey('map-controls'),
                  top: controlsTop,
                  right: 14,
                  child: _controls(context, controlSpace),
                ),
              if (error != null && results.isEmpty)
                Positioned(
                    left: 14,
                    right: 72,
                    bottom: footer + panelLimit + 16,
                    child: Material(
                      color: theme.cardColor,
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 100),
                          child: SingleChildScrollView(
                              child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                            child: Row(children: [
                              const Icon(Icons.info_outline,
                                  size: 18, color: accent),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(error!,
                                      style: const TextStyle(fontSize: 11))),
                              IconButton(
                                  tooltip: 'Dismiss message',
                                  onPressed: () => setState(() => error = null),
                                  icon: const Icon(Icons.close, size: 16))
                            ]),
                          ))),
                    )),
              if (selected != null && panelLimit > 0 && results.isEmpty)
                Positioned(
                  key: const ValueKey('map-place-sheet'),
                  bottom: footer + 8,
                  left: 14,
                  right: 14,
                  child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: panelLimit),
                      child: Material(
                        color: theme.cardColor,
                        elevation: 8,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(22),
                        clipBehavior: Clip.antiAlias,
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                            child: _placePanel(context, app)),
                      )),
                ),
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Material(
                      color: theme.cardColor.withValues(alpha: .94),
                      child: InkWell(
                        onTap: () => openUrl(
                            context, 'https://www.openstreetmap.org/copyright'),
                        child: const SizedBox(
                            height: footer,
                            child: Center(
                                child: Text(
                                    '© OpenStreetMap · Esri / OpenTopoMap · OSRM',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        TextStyle(fontSize: 9, color: muted)))),
                      ))),
            ]);
      }),
    );
  }

  Widget _controls(BuildContext context, double space) {
    final showZoom = space >= 194;
    final showLocation = space >= 96;
    final showShare = space >= (showZoom ? 246 : 148);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Material(
          color: Theme.of(context).cardColor,
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
              width: 44,
              height: 44,
              child: PopupMenuButton<String>(
                tooltip: 'Map options',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.layers_outlined, size: 21),
                constraints: const BoxConstraints(minWidth: 210),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      enabled: false,
                      child: Text('MAP STYLE',
                          style: TextStyle(
                              fontSize: 10, letterSpacing: 1.2, color: muted))),
                  for (final style in ['Streets', 'Satellite', 'Terrain'])
                    PopupMenuItem(
                        value: style,
                        child: Row(children: [
                          Icon(
                              style == 'Satellite'
                                  ? Icons.satellite_alt_outlined
                                  : style == 'Terrain'
                                      ? Icons.terrain_outlined
                                      : Icons.map_outlined,
                              size: 18),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(style,
                                  style: const TextStyle(fontSize: 12))),
                          if (mapStyle == style)
                            const Icon(Icons.check, size: 17, color: accent)
                        ])),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      value: 'locate', child: Text('Use my location')),
                  const PopupMenuItem(
                      value: 'share', child: Text('Copy location link')),
                  if (!showZoom) ...[
                    const PopupMenuItem(
                        value: 'zoom-in', child: Text('Zoom in')),
                    const PopupMenuItem(
                        value: 'zoom-out', child: Text('Zoom out'))
                  ],
                ],
                onSelected: (value) {
                  if (value == 'locate') {
                    if (!busy) locate();
                  } else if (value == 'share') {
                    _shareLocation(context);
                  } else if (value == 'zoom-in') {
                    _zoom(1);
                  } else if (value == 'zoom-out') {
                    _zoom(-1);
                  } else {
                    setState(() => mapStyle = value);
                  }
                },
              ))),
      if (showZoom) ...[
        const SizedBox(height: 8),
        Material(
            color: Theme.of(context).cardColor,
            elevation: 4,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _controlButton('Zoom in', Icons.add, () => _zoom(1)),
              const SizedBox(width: 26, child: Divider(height: 1)),
              _controlButton('Zoom out', Icons.remove, () => _zoom(-1)),
            ])),
      ],
      if (showLocation) ...[
        const SizedBox(height: 8),
        _controlSurface(
            context, 'Use my location', Icons.my_location, busy ? null : locate,
            primary: true)
      ],
      if (showShare) ...[
        const SizedBox(height: 8),
        _controlSurface(context, 'Copy current location', Icons.share_outlined,
            () => _shareLocation(context))
      ],
    ]);
  }

  Widget _controlButton(String label, IconData icon, VoidCallback? callback,
          {Color? color}) =>
      SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
              tooltip: label,
              onPressed: callback,
              icon: Icon(icon, size: 21, color: color),
              padding: EdgeInsets.zero));
  Widget _controlSurface(BuildContext context, String label, IconData icon,
          VoidCallback? callback, {bool primary = false}) =>
      Material(
          color: primary ? ink : Theme.of(context).cardColor,
          elevation: 4,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: _controlButton(label, icon, callback,
              color: primary ? Colors.white : null));
  void _zoom(double amount) => controller.move(
      controller.camera.center, (controller.camera.zoom + amount).clamp(4, 18));
  Future<void> _shareLocation(BuildContext context) async {
    if (!await confirm(context, 'Share your location?',
            'Copy a map link of your current position to share with someone you choose.',
            action: 'Copy link') ||
        !context.mounted) return;
    await perform(context, () async {
      final point = await requestUserLocation(context);
      if (point == null) return;
      await Clipboard.setData(ClipboardData(
          text:
              'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=16/${point.latitude}/${point.longitude}'));
      if (context.mounted) toast(context, 'Location link copied.');
    });
  }

  Widget _placePanel(BuildContext context, AppState app) {
    final place = selected!;
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Container(
                  width: 30,
                  height: 3,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                      color: muted.withValues(alpha: .35),
                      borderRadius: BorderRadius.circular(3)))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!planning) ...[
              ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child:
                      PlacePhoto(value(place, 'image'), width: 56, height: 56)),
              const SizedBox(width: 12)
            ],
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (planning)
                    const Text('DIRECTIONS',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: accent)),
                  Text(value(place, 'name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.35)),
                  const SizedBox(height: 4),
                  Text(
                      planning
                          ? value(place, 'address')
                          : '${value(place, 'category')} · ${app.distance(place)} ${app.location == null ? 'from Tagaytay' : 'away'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: muted)),
                ])),
            SizedBox(
                width: 30,
                height: 30,
                child: IconButton(
                    tooltip: 'Close place',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      tracking?.cancel();
                      setState(() {
                        selected = null;
                        route = [];
                        steps = [];
                        navigating = false;
                        planning = false;
                        error = null;
                      });
                    })),
          ]),
          const SizedBox(height: 12),
          if (!planning)
            Row(children: [
              Expanded(
                  child: FilledButton.icon(
                      onPressed: () => setState(() => planning = true),
                      icon: const Icon(Icons.directions_outlined, size: 18),
                      label: const Text('Directions'))),
              if (place['id'] != null) ...[
                const SizedBox(width: 10),
                OutlinedButton(
                    onPressed: () => openPage(context, PlacePage(place: place)),
                    child:
                        const Text('Details', style: TextStyle(fontSize: 12)))
              ],
            ]),
          if (planning) ...[
            TextField(
                controller: originText,
                enabled: !busy,
                onChanged: (_) => origin = null,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                    hintText: 'Starting address or landmark',
                    prefixIcon: const Icon(Icons.trip_origin, size: 17),
                    suffixIcon: IconButton(
                        tooltip: 'Use current location',
                        onPressed: busy ? null : locate,
                        icon: const Icon(Icons.my_location, size: 18)))),
            if (value(app.settings, 'homeAddress').isNotEmpty ||
                value(app.settings, 'workAddress').isNotEmpty)
              Wrap(spacing: 8, children: [
                for (final key in ['homeAddress', 'workAddress'])
                  if (value(app.settings, key).isNotEmpty)
                    TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                  origin = null;
                                  originText.text = value(app.settings, key);
                                }),
                        icon: Icon(
                            key == 'homeAddress'
                                ? Icons.home_outlined
                                : Icons.work_outline,
                            size: 15),
                        label: Text(key == 'homeAddress' ? 'Home' : 'Work',
                            style: const TextStyle(fontSize: 11))),
              ]),
            const SizedBox(height: 12),
            SizedBox(
                height: 36,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 4,
                    separatorBuilder: (_, i) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final label = ['Car', 'Walking', 'Cycling', 'Transit'][i];
                      final icon = [
                        Icons.directions_car_outlined,
                        Icons.directions_walk,
                        Icons.directions_bike,
                        Icons.directions_transit_outlined
                      ][i];
                      return ChoiceChip(
                          showCheckmark: false,
                          avatar: Icon(icon, size: 16),
                          label:
                              Text(label, style: const TextStyle(fontSize: 10)),
                          selected: mode == label,
                          onSelected: busy
                              ? null
                              : (_) => setState(() {
                                    tracking?.cancel();
                                    navigating = false;
                                    mode = label;
                                    route = [];
                                    steps = [];
                                  }));
                    })),
            const SizedBox(height: 12),
            PrimaryButton(
                label: mode == 'Transit'
                    ? 'Open transit directions'
                    : 'Find route',
                icon: Icons.route_outlined,
                busy: busy,
                onPressed: calculate),
            if (route.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                  '${app.settings['distanceUnit'] == 'miles' ? '${(meters / 1609.344).toStringAsFixed(1)} mi' : '${(meters / 1000).toStringAsFixed(1)} km'} · ${(seconds / 60).round()} min ${mode.toLowerCase()}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
              const Text('Estimated by OSRM · traffic is not included',
                  style: TextStyle(fontSize: 10, color: muted)),
              if (routeOptions.length > 1)
                Wrap(
                    spacing: 6,
                    children: List.generate(
                        routeOptions.length,
                        (i) => ChoiceChip(
                            label: Text(
                                i == 0 ? 'Recommended' : 'Alternative $i',
                                style: const TextStyle(fontSize: 10)),
                            selected: routeChoice == i,
                            onSelected: busy ? null : (_) => selectRoute(i)))),
              if (navigating && steps.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(instruction(steps[step]),
                        style: const TextStyle(fontWeight: FontWeight.w800))),
              const SizedBox(height: 10),
              PrimaryButton(
                  label: navigating ? 'Stop navigation' : 'Start navigation',
                  icon: Icons.navigation_outlined,
                  busy: busy,
                  onPressed: navigating
                      ? () {
                          tracking?.cancel();
                          setState(() => navigating = false);
                        }
                      : navigate),
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Turn-by-turn steps',
                      style: TextStyle(fontSize: 12)),
                  children: [
                    for (final instructionStep in steps)
                      ListTile(
                          dense: true,
                          title: Text(instruction(instructionStep),
                              style: const TextStyle(fontSize: 11)),
                          subtitle: Text(
                              '${number(instructionStep['distance']).round()} m'))
                  ]),
            ],
          ],
        ]);
  }

  List<Marker> _placeMarkers(List<JsonMap> places) {
    final groups = <List<JsonMap>>[];
    final markers = <Marker>[];
    for (final place in places) {
      if (place['id'] == selected?['id']) {
        markers.add(_placeMarker(place, selected: true));
        continue;
      }
      groups.add([place]);
    }
    LatLng centerOf(List<JsonMap> group) => LatLng(
        group.fold<double>(
                0, (sum, place) => sum + coordinates(place).latitude) /
            group.length,
        group.fold<double>(
                0, (sum, place) => sum + coordinates(place).longitude) /
            group.length);
    // Merge nearby screen positions, including groups on either side of a grid
    // boundary, so the count circles themselves do not cover one another.
    final pixelsPerDegree = 256 * math.pow(2, mapZoom) / 360;
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        final a = centerOf(groups[i]), b = centerOf(groups[j]);
        final dx = (a.longitude - b.longitude) * pixelsPerDegree;
        final dy = (a.latitude - b.latitude) *
            pixelsPerDegree /
            math.cos((a.latitude + b.latitude) * math.pi / 360);
        if (math.sqrt(dx * dx + dy * dy) < 54) {
          groups[i].addAll(groups.removeAt(j));
          i = -1;
          break;
        }
      }
    }
    for (final group in groups) {
      if (group.length == 1) {
        markers.add(_placeMarker(group.single));
        continue;
      }
      final center = centerOf(group);
      markers.add(Marker(
          point: center,
          width: 44,
          height: 44,
          child: Tooltip(
              message: '${group.length} places — zoom in',
              child: Material(
                  color: ink,
                  elevation: 3,
                  shadowColor: Colors.black26,
                  shape: const CircleBorder(
                      side: BorderSide(color: Colors.white, width: 2.5)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      onTap: () async {
                        if (mapZoom < 17) {
                          controller.move(
                              center, math.min(18, controller.camera.zoom + 2));
                        } else {
                          final picked = await showModalBottomSheet<JsonMap>(
                              context: context,
                              showDragHandle: true,
                              builder: (context) =>
                                  ListView(shrinkWrap: true, children: [
                                    for (final place in group)
                                      ListTile(
                                          title: Text(value(place, 'name'),
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          subtitle:
                                              Text(value(place, 'category')),
                                          onTap: () =>
                                              Navigator.pop(context, place))
                                  ]));
                          if (picked != null && mounted) choose(picked);
                        }
                      },
                      child: Center(
                          child: Text('${group.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800))))))));
    }
    return markers;
  }

  Marker _placeMarker(JsonMap place, {bool selected = false}) => Marker(
      point: coordinates(place),
      width: 44,
      height: 44,
      child: IconButton(
          tooltip: value(place, 'name'),
          onPressed: () => choose(place),
          icon: Icon(Icons.location_on,
              size: selected ? 39 : 33,
              color: selected
                  ? const Color(0xffe49c25)
                  : place['category'] == 'Food'
                      ? const Color(0xffb85b27)
                      : ['Stay', 'Resort'].contains(place['category'])
                          ? const Color(0xff287c9d)
                          : ink)));

  String instruction(JsonMap s) {
    final maneuver = s['maneuver'] as Map? ?? {};
    return '${value(Map<String, dynamic>.from(maneuver), 'type', 'Continue')} ${maneuver['modifier'] ?? ''}${value(s, 'name').isEmpty ? '' : ' onto ${s['name']}'}'
        .trim();
  }
}
