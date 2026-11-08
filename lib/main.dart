import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'config.dart';
import 'ui.dart';
import 'explore.dart';
import 'map_page.dart';
import 'account.dart';
import 'assistant.dart';
import 'admin.dart';
import 'business.dart';

String initialRouteFromUri(Uri uri) {
  final route = uri.path.isNotEmpty && uri.path != '/'
      ? uri
      : Uri.tryParse(uri.fragment) ?? Uri();
  final path = route.path.startsWith('/') ? route.path : '/';
  return route.hasQuery ? '$path?${route.query}' : path;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Supabase.initialize(
        url: supabaseUrl, publishableKey: supabasePublishableKey);
    final state = AppState(
        Supabase.instance.client, await SharedPreferences.getInstance());
    runApp(PasyalPH(state: state));
    unawaited(state.initialize());
  } catch (e) {
    runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
            body: Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                        'PasyalPH could not start. Check your connection and reload.\n${errorText(e)}'))))));
  }
}

class PasyalPH extends StatelessWidget {
  const PasyalPH({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => AppScope(
      state: state,
      child: AnimatedBuilder(
          animation: state,
          builder: (context, _) => MaterialApp(
                title: 'PasyalPH — Explore local places',
                debugShowCheckedModeBanner: false,
                initialRoute: initialRouteFromUri(Uri.base),
                theme: appTheme(false),
                darkTheme: appTheme(true),
                themeMode: state.settings['colorScheme'] == 'night'
                    ? ThemeMode.dark
                    : state.settings['colorScheme'] == 'day'
                        ? ThemeMode.light
                        : ThemeMode.system,
                builder: (context, child) =>
                    LayoutBuilder(builder: (context, c) {
                  final route = isAdminRoute(Uri.base.path) ||
                      isAdminRoute(
                          Uri.tryParse(Uri.base.fragment)?.path ?? '');
                  if (route) return child!;
                  final framed = c.maxWidth > 540;
                  final width = framed ? 430.0 : c.maxWidth;
                  final height = framed
                      ? (c.maxHeight - 48).clamp(300.0, 900.0)
                      : c.maxHeight;
                  return ColoredBox(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xff1d3035)
                          : const Color(0xffe5edeb),
                      child: Center(
                          child: SizedBox(
                              width: width,
                              height: height,
                              child: DecoratedBox(
                                  decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                          framed ? 30 : 0),
                                      boxShadow: framed
                                          ? [
                                              const BoxShadow(
                                                  color: Color(0x33182d26),
                                                  blurRadius: 45,
                                                  offset: Offset(0, 15))
                                            ]
                                          : []),
                                  child: ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                          framed ? 30 : 0),
                                      child: MediaQuery(
                                          data: MediaQuery.of(context).copyWith(
                                              size: Size(width, height)),
                                          child: child!))))));
                }),
                onGenerateRoute: (settings) {
                  final uri = Uri.tryParse(settings.name ?? '/') ?? Uri();
                  Widget page;
                  switch (uri.path) {
                    case '/login':
                      page = const AccountPage();
                      break;
                    case '/map':
                      page = const MapPage();
                      break;
                    case '/saved':
                      page = const SavedPage();
                      break;
                    case '/settings':
                      page = const ProfilePage();
                      break;
                    case '/assistant':
                      page = const AssistantPage();
                      break;
                    case '/admin':
                    case '/admin/listings':
                    case '/admin/accommodations':
                    case '/admin/destinations':
                    case '/admin/applications':
                      final validStatuses = [
                        'All statuses',
                        'Verified',
                        'Pending Verification',
                        'Rejected',
                        'Suspended'
                      ];
                      final requestedStatus =
                          uri.queryParameters['status'] ?? 'All statuses';
                      page = AdminPortal(
                        initialSection: adminSectionForRoute(uri.path),
                        initialStatus: validStatuses.contains(requestedStatus)
                            ? requestedStatus
                            : 'All statuses',
                      );
                      break;
                    case '/moderation':
                      page = const AdminPage();
                      break;
                    case '/privacy':
                      page = const PolicyPage(privacy: true);
                      break;
                    case '/terms':
                      page = const PolicyPage(privacy: false);
                      break;
                    default:
                      page = const Shell();
                  }
                  return MaterialPageRoute(
                      settings: settings, builder: (_) => page);
                },
              )));
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;
  final visited = <int>{0};
  Timer? introTimer;
  bool intro = true, recoveryShown = false;
  @override
  void initState() {
    super.initState();
    introTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && intro) setState(() => intro = false);
    });
  }

  @override
  void dispose() {
    introTimer?.cancel();
    super.dispose();
  }

  void selectTab(int next) {
    setState(() {
      visited.add(next);
      tab = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.recovery && !recoveryShown) {
      recoveryShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openPage(context, const PasswordPage());
      });
    }
    if (intro)
      return IntroPage(onDone: () {
        introTimer?.cancel();
        setState(() => intro = false);
      });
    return Scaffold(
      body: SafeArea(
          bottom: false,
          child: IndexedStack(index: tab, children: [
            ExplorePage(onMap: () => selectTab(1)),
            if (visited.contains(1))
              const MapPage(embedded: true)
            else
              const SizedBox.shrink(),
            const SavedPage(embedded: true),
            const ProfilePage(embedded: true)
          ])),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              heroTag: 'assistant',
              onPressed: () => openPage(context, const AssistantPage()),
              icon: const Icon(Icons.chat_bubble_outline, size: 20),
              label: const Text('Ask AI'),
              backgroundColor: ink,
              foregroundColor: Colors.white)
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                  top: BorderSide(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: .2)))),
          child: SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                      children: List.generate(4, (i) {
                    final labels = app.filipino
                        ? ['Tuklasin', 'Mapa', 'Naka-save', 'Profile']
                        : ['Explore', 'Map', 'Saved', 'Profile'];
                    final icons = [
                      Icons.explore_outlined,
                      Icons.map_outlined,
                      Icons.favorite_border,
                      Icons.person_outline
                    ];
                    return Expanded(
                        child: Semantics(
                            selected: tab == i,
                            child: InkWell(
                                onTap: () => selectTab(i),
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(icons[i],
                                              size: 21,
                                              color: tab == i
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                  : muted),
                                          const SizedBox(height: 4),
                                          Text(labels[i],
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: tab == i
                                                      ? FontWeight.w800
                                                      : FontWeight.w500,
                                                  color: tab == i
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .primary
                                                      : muted))
                                        ])))));
                  }))))),
    );
  }
}

class IntroPage extends StatelessWidget {
  const IntroPage({super.key, required this.onDone});
  final VoidCallback onDone;
  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xffeff7ed),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(30),
                  child: Column(children: [
                    const BrandLogo(size: 116),
                    const SizedBox(height: 26),
                    const BrandTitle(size: 44),
                    const SizedBox(height: 16),
                    const Text('YOUR NEXT ADVENTURE STARTS HERE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                            color: Color(0xff467461))),
                    const SizedBox(height: 22),
                    const Text(
                        'Discover beautiful places, hidden gems, and unforgettable experiences across the Philippines.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            height: 1.9,
                            fontSize: 13,
                            color: Color(0xff62746b))),
                    const SizedBox(height: 30),
                    const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Icon(Icons.location_on,
                              color: Colors.redAccent, size: 32),
                          Icon(Icons.flight_takeoff,
                              color: Color(0xff286b83), size: 42),
                          Icon(Icons.location_on,
                              color: Color(0xffe6a536), size: 32)
                        ]),
                    const SizedBox(height: 36),
                    PrimaryButton(
                        label: 'Let’s explore',
                        icon: Icons.arrow_forward,
                        onPressed: onDone),
                    const SizedBox(height: 12),
                    const Text('Made for your Philippine adventures',
                        style: TextStyle(fontSize: 11, color: muted)),
                  ])))));
}
