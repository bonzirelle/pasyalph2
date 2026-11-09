import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'location_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef JsonMap = Map<String, dynamic>;
const categories = ['All', 'Tourist Spot', 'Food', 'Resort', 'Stay', 'Shop'];
const pilot = LatLng(14.1005, 120.957);
String value(JsonMap row, String key, [String fallback = '']) =>
    '${row[key] ?? fallback}';
double number(dynamic n) =>
    n is num ? n.toDouble() : double.tryParse('$n') ?? 0;
LatLng coordinates(JsonMap p) => LatLng(number(p['lat']), number(p['lng']));
bool sample(JsonMap p) => p['is_sample'] == true;
double distanceKm(LatLng a, LatLng b) =>
    const Distance(roundResult: false).as(LengthUnit.Kilometer, a, b);
String errorText(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  if (e is StorageException) return e.message;
  if (e is FunctionException)
    return '${e.details ?? e.reasonPhrase ?? 'Service unavailable'}';
  if (e is TimeoutException)
    return 'The request took too long. Check your connection and try again.';
  return e.toString().replaceFirst('Exception: ', '');
}

class AppState extends ChangeNotifier {
  AppState(this.client, this.prefs, {LocationService? locationService})
      : locationService = locationService ?? LocationService();
  final LocationService locationService;
  Future<LatLng>? _locationRequest;
  bool locationBusy = false;
  final SupabaseClient client;
  final SharedPreferences prefs;
  List<JsonMap> places = [],
      reviews = [],
      promotions = [],
      applications = [],
      reports = [],
      plans = [];
  List<JsonMap> catalog = [];
  Set<String> remoteIds = {}, saved = {}, localSaved = {};
  JsonMap settings = {}, profile = {};
  LatLng? location;
  String locationLabel = 'Tagaytay City, Cavite';
  bool loading = true, refreshing = false, recovery = false;
  bool plansOnDevice = false;
  String? loadError;
  int _generation = 0;
  bool _disposed = false;
  bool _liveCatalogSeen = false;
  int _settingsRevision = 0;
  Future<void> _settingsWrites = Future<void>.value();
  StreamSubscription<AuthState>? _auth;
  RealtimeChannel? _channel;
  Timer? _refreshTimer;
  User? get user => client.auth.currentUser;
  bool get signedIn => user != null;
  bool get hasLocalPlans => plans.any(_isLocalPlan);
  bool _isLocalPlan(JsonMap plan) => value(plan, 'id').startsWith('local-');
  List<JsonMap> _devicePlans(String? uid) =>
      _storedRows('plans-${uid ?? 'guest'}').where(_isLocalPlan).toList();
  Future<void> _persistLocalPlans(String? uid) => prefs.setString(
      'plans-${uid ?? 'guest'}',
      jsonEncode(plans.where(_isLocalPlan).toList()));
  String get role => value(profile, 'role', 'traveler');
  String get name => value(settings, 'name',
      '${user?.userMetadata?['name'] ?? user?.userMetadata?['full_name'] ?? user?.email?.split('@').first ?? 'Traveler'}');
  String get avatar =>
      value(settings, 'avatar', '${user?.userMetadata?['avatar_url'] ?? ''}');
  bool get dark => settings['colorScheme'] == 'night';
  bool get filipino => settings['language'] == 'fil';
  List<JsonMap> get publicPlaces =>
      places.where((p) => p['status'] == 'Verified').toList();
  List<JsonMap> reviewsFor(JsonMap p) =>
      reviews.where((r) => r['place_id'] == p['id']).toList();
  List<JsonMap> promotionsFor(JsonMap p) =>
      promotions.where((r) => r['place_id'] == p['id']).toList();
  List<JsonMap> sampleReviews(JsonMap p) =>
      ((p['sample_reviews'] as List?) ?? [])
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
  String rating(JsonMap p) {
    final list = reviewsFor(p);
    if (list.isEmpty) return 'New';
    return (list.fold<double>(0, (v, r) => v + number(r['rating'])) /
            list.length)
        .toStringAsFixed(1);
  }

  bool isSaved(JsonMap p) =>
      saved.contains('${p['id']}') || localSaved.contains('${p['id']}');
  String distance(JsonMap p) {
    final d = distanceKm(location ?? pilot, coordinates(p));
    final miles = settings['distanceUnit'] == 'miles';
    final n = miles ? d * .621371 : d;
    return '${n < 10 ? n.toStringAsFixed(1) : n.round()} ${miles ? 'mi' : 'km'}';
  }

  Future<void> initialize() async {
    catalog =
        (jsonDecode(await rootBundle.loadString('assets/data/catalog.json'))
                as List)
            .map((p) => Map<String, dynamic>.from(p))
            .toList();
    settings = _storedMap('settings-${user?.id ?? 'guest'}');
    localSaved =
        prefs.getStringList('sample-saves-${user?.id ?? 'guest'}')?.toSet() ??
            {};
    _liveCatalogSeen = prefs.getBool('live-catalog-seen') ?? false;
    plans = _devicePlans(user?.id);
    _auth = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) recovery = true;
      if (event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.initialSession) {
        profile = {};
        saved = {};
        applications = [];
        reports = [];
        settings = _storedMap('settings-${user?.id ?? 'guest'}');
        localSaved = prefs
                .getStringList('sample-saves-${user?.id ?? 'guest'}')
                ?.toSet() ??
            {};
        plans = _devicePlans(user?.id);
        plansOnDevice = plans.isNotEmpty || user == null;
        recovery = false;
        ++_settingsRevision;
        _subscribe();
        unawaited(refresh());
      }
      notifyListeners();
    });
    _subscribe();
    await refresh();
  }

  JsonMap _storedMap(String key) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode(prefs.getString(key) ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  List<JsonMap> _storedRows(String key) {
    try {
      return (jsonDecode(prefs.getString(key) ?? '[]') as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _subscribe() {
    if (_channel != null) unawaited(client.removeChannel(_channel!));
    _channel = client
        .channel('app-${user?.id ?? 'guest'}')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            callback: (_) {
              _refreshTimer?.cancel();
              _refreshTimer = Timer(const Duration(milliseconds: 450),
                  () => unawaited(refresh()));
            })
        .subscribe();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    final settingsRevision = _settingsRevision;
    refreshing = true;
    notifyListeners();
    try {
      final data = await Future.wait([
        client.from('places').select().order('name').limit(1000),
        client
            .from('reviews')
            .select()
            .order('created_at', ascending: false)
            .limit(1000),
        _loadPromotions(),
      ]).timeout(const Duration(seconds: 20));
      if (generation != _generation) return;
      final remote = List<JsonMap>.from(data[0]);
      remoteIds = remote.map((p) => '${p['id']}').toSet();
      if (remote.isNotEmpty) {
        _liveCatalogSeen = true;
        await prefs.setBool('live-catalog-seen', true);
        if (generation != _generation) return;
      }
      // Once a live catalog has been seen, never resurrect hidden listings
      // from the bundled sample data when RLS or moderation removes them.
      places = _liveCatalogSeen ? remote : [...catalog];
      reviews = List<JsonMap>.from(data[1]);
      promotions = List<JsonMap>.from(data[2] as List);
      loadError = null;
      if (user != null) {
        final uid = user!.id;
        final privateData = await Future.wait<dynamic>([
          client.from('profiles').select().eq('id', uid).maybeSingle(),
          client.from('saved_places').select('place_id').eq('user_id', uid),
          client
              .from('business_applications')
              .select()
              .order('created_at', ascending: false),
          client.from('reports').select().order('created_at', ascending: false),
        ]).timeout(const Duration(seconds: 20));
        if (generation != _generation) return;
        profile = Map<String, dynamic>.from(privateData[0] as Map? ?? {});
        final remoteSettings = profile['settings'];
        if (remoteSettings is Map && settingsRevision == _settingsRevision)
          settings = {
            ...settings,
            ...Map<String, dynamic>.from(remoteSettings)
          };
        saved = (privateData[1] as List).map((r) => '${r['place_id']}').toSet();
        applications = List<JsonMap>.from(privateData[2] as List);
        reports = List<JsonMap>.from(privateData[3] as List);
        try {
          final remotePlans = await client
              .from('trip_plans')
              .select()
              .eq('user_id', uid)
              .order('created_at', ascending: false);
          if (generation != _generation) return;
          plans = [...List<JsonMap>.from(remotePlans), ..._devicePlans(uid)];
          plansOnDevice = false;
        } on PostgrestException catch (e) {
          if (!['PGRST205', '42P01'].contains(e.code)) rethrow;
          plansOnDevice = true;
        }
      }
    } catch (e) {
      if (generation != _generation) return;
      loadError = errorText(e);
      if (places.isEmpty && !_liveCatalogSeen) places = [...catalog];
    } finally {
      if (generation == _generation) {
        loading = false;
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<List<JsonMap>> _loadPromotions() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await client
          .from('promotions')
          .select()
          .eq('active', true)
          .lte('starts_at', now)
          .gt('ends_at', now)
          .order('ends_at')
          .limit(500);
      return List<JsonMap>.from(rows);
    } on PostgrestException catch (e) {
      if (['PGRST205', '42P01'].contains(e.code)) return [];
      rethrow;
    }
  }

  Future<void> updateSettings(JsonMap changes) {
    final uid = user?.id;
    final write = _settingsWrites.then((_) => _writeSettings(changes, uid));
    _settingsWrites = write.catchError((Object _) {});
    return write;
  }

  Future<void> _writeSettings(JsonMap changes, String? uid) async {
    if (_disposed || user?.id != uid) {
      throw Exception('Your account changed. Try saving your settings again.');
    }
    final next = {...settings, ...changes};
    if (uid != null) {
      final rows = await client
          .from('profiles')
          .update({'settings': next})
          .eq('id', uid)
          .select('id');
      if (rows.isEmpty)
        throw Exception(
            'Your profile could not be saved. Please sign in again.');
    }
    await prefs.setString('settings-${uid ?? 'guest'}', jsonEncode(next));
    if (_disposed || user?.id != uid) return;
    ++_settingsRevision;
    settings = next;
    notifyListeners();
  }

  Future<String> toggleSave(JsonMap p) async {
    final id = '${p['id']}';
    // A local save may refer to a listing that has since been published.
    // Removing that heart must also remove the device copy.
    if (localSaved.contains(id) && !saved.contains(id)) {
      localSaved.remove(id);
      await prefs.setStringList(
          'sample-saves-${user?.id ?? 'guest'}', localSaved.toList());
      notifyListeners();
      return 'Removed from saved places.';
    }
    if (!remoteIds.contains(id)) {
      if (!localSaved.add(id)) localSaved.remove(id);
      await prefs.setStringList(
          'sample-saves-${user?.id ?? 'guest'}', localSaved.toList());
      notifyListeners();
      return localSaved.contains(id)
          ? 'Sample saved on this device.'
          : 'Sample removed from saved places.';
    }
    requireUser();
    if (saved.contains(id)) {
      await client
          .from('saved_places')
          .delete()
          .eq('user_id', user!.id)
          .eq('place_id', id);
      saved.remove(id);
      if (localSaved.remove(id)) {
        await prefs.setStringList(
            'sample-saves-${user?.id ?? 'guest'}', localSaved.toList());
      }
    } else {
      await client
          .from('saved_places')
          .insert({'user_id': user!.id, 'place_id': id});
      saved.add(id);
    }
    notifyListeners();
    return saved.contains(id)
        ? 'Saved to your account.'
        : 'Removed from saved places.';
  }

  void requireUser() {
    if (user == null) throw Exception('Log in to continue.');
  }

  Future<void> postReview(JsonMap p, int rating, String text) async {
    requireUser();
    if (!remoteIds.contains('${p['id']}'))
      throw Exception(
          'This is a local sample. Reviews become available after the catalog is imported into Supabase.');
    await client.from('reviews').upsert({
      'user_id': user!.id,
      'place_id': p['id'],
      'rating': rating,
      'body': text.trim()
    }, onConflict: 'place_id,user_id');
    await refresh();
  }

  Future<void> report(JsonMap p, String reason) async {
    requireUser();
    if (!remoteIds.contains('${p['id']}'))
      throw Exception(
          'This sample has not been published. Reports are available for published listings.');
    await client.from('reports').insert(
        {'user_id': user!.id, 'place_id': p['id'], 'reason': reason.trim()});
    await refresh();
  }

  Future<LatLng> locate() {
    if (_locationRequest != null) return _locationRequest!;
    locationBusy = true;
    notifyListeners();
    return _locationRequest = _readLocation();
  }

  Future<LatLng> _readLocation() async {
    try {
      final position = await locationService.current();
      final point = LatLng(position.latitude, position.longitude);
      if (!_disposed) {
        location = point;
        locationLabel = 'Your current location';
      }
      return point;
    } finally {
      _locationRequest = null;
      locationBusy = false;
      notifyListeners();
    }
  }

  void selectLocation(LatLng point, String label) {
    location = point;
    locationLabel = label;
    notifyListeners();
  }

  Future<bool> savePlan(String title, List<String> ids, String notes) async {
    final uid = user?.id;
    if (title.trim().isEmpty ||
        title.length > 150 ||
        ids.isEmpty ||
        ids.length > 8 ||
        notes.length > 6000) {
      throw Exception('Add a trip name and one to eight stops.');
    }
    final row = {
      'title': title,
      'place_ids': ids,
      'notes': notes,
      if (uid != null) 'user_id': uid
    };
    Future<bool> saveOnDevice() async {
      if (_disposed || user?.id != uid)
        throw Exception('Your account changed. Try saving the trip again.');
      plansOnDevice = true;
      plans.insert(0, {
        ...row,
        'id': 'local-${DateTime.now().microsecondsSinceEpoch}',
        'created_at': DateTime.now().toIso8601String()
      });
      await _persistLocalPlans(uid);
      notifyListeners();
      return false;
    }

    if (uid == null) return saveOnDevice();
    try {
      await client.from('trip_plans').insert(row);
      plansOnDevice = false;
      await refresh();
      return true;
    } on PostgrestException catch (e) {
      if (!['PGRST205', '42P01'].contains(e.code)) rethrow;
      return saveOnDevice();
    }
  }

  Future<void> deletePlan(JsonMap p) async {
    if ('${p['id']}'.startsWith('local-')) {
      plans.removeWhere((r) => r['id'] == p['id']);
      await _persistLocalPlans(user?.id);
    } else {
      requireUser();
      await client
          .from('trip_plans')
          .delete()
          .eq('id', p['id'])
          .eq('user_id', user!.id);
      await refresh();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _refreshTimer?.cancel();
    _auth?.cancel();
    if (_channel != null) unawaited(client.removeChannel(_channel!));
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
