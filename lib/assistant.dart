import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'app_state.dart';
import 'ui.dart';
import 'explore.dart';
import 'account.dart';
import 'map_page.dart';
import 'location_ui.dart';

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});
  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final input = TextEditingController(), scroll = ScrollController();
  List<JsonMap> messages = [];
  bool busy = false;
  String mode = 'catalog';
  List<JsonMap> suggestions = [];
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> send([String? prompt]) async {
    final text = (prompt ?? input.text).trim();
    if (text.isEmpty || busy) return;
    final app = AppScope.of(context);
    input.clear();
    setState(() {
      messages.add({'role': 'user', 'text': text});
      busy = true;
    });
    try {
      JsonMap? answer;
      if (app.signedIn) {
        try {
          final response =
              await app.client.functions.invoke('travel-assistant', body: {
            'messages': messages.takeLast(12),
            'location': app.location == null
                ? null
                : {
                    'lat': app.location!.latitude,
                    'lng': app.location!.longitude
                  },
            'radiusKm': 25
          }).timeout(const Duration(seconds: 25));
          if (response.status == 200 &&
              response.data is Map &&
              response.data['text'] is String)
            answer = Map<String, dynamic>.from(response.data);
        } catch (_) {
          /* Local catalog remains available if AI is not connected. */
        }
      }
      answer ??= catalogAnswer(app, text);
      if (!mounted) return;
      final ids = (answer['place_ids'] as List? ?? []).map((s) => '$s').toSet();
      setState(() {
        mode = value(answer!, 'mode', 'catalog');
        suggestions = app.publicPlaces
            .where((p) => ids.contains('${p['id']}'))
            .take(4)
            .toList();
        messages.add({'role': 'model', 'text': answer['text']});
      });
    } catch (e) {
      if (mounted)
        setState(() => messages.add({
              'role': 'model',
              'text': 'I couldn’t complete that request. ${errorText(e)}'
            }));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients)
            scroll.animateTo(scroll.position.maxScrollExtent,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ask PasyalPH'),
              Text(mode == 'ai' ? 'AI travel assistant' : 'Catalog guide',
                  style: const TextStyle(
                      fontFamily: 'Jakarta', fontSize: 10, color: muted))
            ]),
            actions: [
              IconButton(
                  tooltip: 'New chat',
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            messages = [];
                            suggestions = [];
                          }),
                  icon: const Icon(Icons.add))
            ]),
        body: Column(children: [
          Expanded(
              child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                if (messages.isEmpty) ...[
                  const SizedBox(height: 20),
                  const Center(child: BrandLogo(size: 66)),
                  const SizedBox(height: 22),
                  Text('Where shall we go?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  const Text(
                      'Find a hidden gem, plan a day out, or discover a place to stay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 20),
                  for (final prompt in [
                    'Plan a day trip in Tagaytay',
                    'Find food spots and cafés',
                    'Show Airbnb-style stays',
                    'What is near me?'
                  ])
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                            onPressed: () => send(prompt),
                            child: Text(prompt,
                                style: const TextStyle(fontSize: 12)))),
                ],
                for (final message in messages)
                  Align(
                      alignment: message['role'] == 'user'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          constraints: const BoxConstraints(maxWidth: 350),
                          decoration: BoxDecoration(
                              color: message['role'] == 'user'
                                  ? ink
                                  : Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(20)),
                          child: SelectableText('${message['text']}',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.8,
                                  color: message['role'] == 'user'
                                      ? Colors.white
                                      : null)))),
                if (busy)
                  const Padding(
                      padding: EdgeInsets.all(14),
                      child: LinearProgressIndicator()),
                for (final p in suggestions)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: PlaceCard(p, compact: true)),
                if (suggestions.isNotEmpty)
                  TextButton.icon(
                      onPressed: () => openPage(
                          context,
                          PlanEditor(
                              initialPlaces: suggestions
                                  .map((p) => '${p['id']}')
                                  .toList())),
                      icon: const Icon(Icons.route_outlined, size: 16),
                      label: const Text('Build a trip with these places')),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.location_on_outlined, size: 14, color: muted),
                const SizedBox(width: 5),
                Expanded(
                    child: Text(
                        app.location == null
                            ? 'No location shared'
                            : app.locationLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: muted))),
                TextButton(
                    onPressed: busy || app.locationBusy
                        ? null
                        : () => requestUserLocation(context),
                    child: Text(app.locationBusy ? 'Locating…' : 'Use location',
                        style: const TextStyle(fontSize: 10))),
                IconButton(
                    tooltip: 'Choose a city',
                    onPressed: busy ? null : () => chooseCity(context, app),
                    icon:
                        const Icon(Icons.edit_location_alt_outlined, size: 18))
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                  controller: input,
                  maxLength: 2000,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => send(),
                  decoration: InputDecoration(
                      hintText: 'Ask about your next trip…',
                      suffixIcon: IconButton(
                          tooltip: 'Send message',
                          onPressed: busy ? null : () => send(),
                          icon: const Icon(Icons.arrow_upward))))),
          const SafeArea(
              top: false,
              child: Padding(
                  padding: EdgeInsets.only(bottom: 8, left: 16, right: 16),
                  child: Text(
                      'Confirm opening hours and prices before traveling.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 9, color: muted)))),
        ]));
  }
}

extension _LastMessages<T> on List<T> {
  List<T> takeLast(int n) => skip(length > n ? length - n : 0).toList();
}

JsonMap catalogAnswer(AppState app, String prompt) {
  final q = prompt.toLowerCase();
  final nearby = RegExp(r'near|nearby|around me|malapit').hasMatch(q);
  if (nearby && app.location == null)
    return {
      'mode': 'catalog',
      'text':
          'Choose “Use location” or a city below so I can find catalog places near you. I won’t assume your location.',
      'place_ids': []
    };
  final categories = <String>[];
  if (RegExp(r'food|eat|café|cafe|coffee|bulalo|restaurant|kain').hasMatch(q))
    categories.add('Food');
  if (RegExp(r'stay|airbnb|sleep|hotel|overnight').hasMatch(q))
    categories.add('Stay');
  if (RegExp(r'resort|swim|pool').hasMatch(q)) categories.add('Resort');
  if (RegExp(r'shop|souvenir|pasalubong').hasMatch(q)) categories.add('Shop');
  final tokens = q
      .split(RegExp(r'[^a-z0-9]+'))
      .where((s) =>
          s.length > 3 &&
          ![
            'plan',
            'trip',
            'show',
            'find',
            'what',
            'places',
            'spots',
            'with',
            'near',
            'nearby',
            'from',
            'that',
            'this',
            'style',
            'stays',
            'please'
          ].contains(s))
      .toList();
  final candidates = app.publicPlaces
      .where((p) => categories.isEmpty || categories.contains(p['category']))
      .where((p) => !nearby || distanceKm(app.location!, coordinates(p)) <= 25)
      .toList();
  int score(JsonMap p) => tokens
      .where((t) => '${p['name']} ${p['address']} ${p['category']}'
          .toLowerCase()
          .contains(t))
      .length;
  candidates.sort((a, b) {
    final scored = score(b) - score(a);
    if (scored != 0) return scored;
    return distanceKm(app.location ?? pilot, coordinates(a))
        .compareTo(distanceKm(app.location ?? pilot, coordinates(b)));
  });
  final matched = candidates.where((p) => score(p) > 0).toList();
  final list = (matched.isNotEmpty ? matched : candidates).take(4).toList();
  if (list.isEmpty)
    return {
      'mode': 'catalog',
      'text': nearby
          ? 'No catalog places match within 25 km. Choose another city or browse Explore.'
          : 'No catalog listings match that category yet. Try another search.',
      'place_ids': []
    };
  final itinerary = RegExp(r'plan|itinerary|day trip').hasMatch(q);
  final body = StringBuffer(
      'Catalog guide · these suggestions use listed details, not a live AI response.\n\n');
  if (itinerary)
    body.writeln(
        'A suggested ${q.contains('tagaytay') ? 'Tagaytay ' : ''}day out\nActivity order only; allow extra time for travel.\n');
  for (var i = 0; i < list.length; i++) {
    final p = list[i];
    body.writeln(
        '${i + 1}. ${p['name']}\n${p['address']}\n${p['hours']}\nListed rates: ${p['rates']}${nearby ? '\n${app.distance(p)} straight-line distance' : ''}\n');
  }
  body.write(
      'Some listings are original samples. Confirm rates and availability directly. Travel, meals and group costs are not included in the listed rates.');
  return {
    'mode': 'catalog',
    'text': body.toString(),
    'place_ids': list.map((p) => p['id']).toList()
  };
}

Future<void> chooseCity(BuildContext context, AppState app) async {
  final text = TextEditingController();
  final query = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
              title: const Text('Choose a Philippine city'),
              content: TextField(
                  controller: text,
                  decoration:
                      const InputDecoration(hintText: 'City, province')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, text.text),
                    child: const Text('Search'))
              ]));
  text.dispose();
  if (query == null || !context.mounted) return;
  await perform(context, () async {
    final results = await geocodePH(query);
    if (!context.mounted) return;
    if (results.isEmpty) throw Exception('No Philippine address found.');
    final picked = await showModalBottomSheet<JsonMap>(
        context: context,
        showDragHandle: true,
        builder: (c) => ListView(shrinkWrap: true, children: [
              for (final p in results)
                ListTile(
                    title: Text('${p['name']}',
                        style: const TextStyle(fontSize: 12)),
                    onTap: () => Navigator.pop(c, p))
            ]));
    if (picked != null) {
      app.selectLocation(coordinates(picked), value(picked, 'name'));
    }
  });
}

class TripPlansPage extends StatelessWidget {
  const TripPlansPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('Your trip plans'), actions: [
          IconButton(
              tooltip: 'Create trip',
              onPressed: () => openPage(context, const PlanEditor()),
              icon: const Icon(Icons.add))
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (!app.signedIn)
            EmptyState('Plan your next adventure',
                'Guest plans stay on this device. Log in to use available cloud features.',
                action: PrimaryButton(
                    label: 'Log in',
                    onPressed: () => openPage(context, const AccountPage()))),
          ...[
            if (app.hasLocalPlans)
              const Text(
                  'Plans marked “On this device” are not synced to your account.',
                  style: TextStyle(fontSize: 11, color: muted)),
            if (app.plans.isEmpty)
              EmptyState('Where will you go next?',
                  'Choose places and build your own itinerary.',
                  action: PrimaryButton(
                      label: 'Create a trip',
                      onPressed: () => openPage(context, const PlanEditor()))),
            for (final p in app.plans)
              Surface(
                  margin: 7,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value(p, 'title'),
                            style: Theme.of(context).textTheme.titleLarge),
                        StatusPill(
                            value(p, 'id').startsWith('local-')
                                ? 'On this device'
                                : 'Synced to account',
                            color: muted),
                        const SizedBox(height: 8),
                        for (final id in p['place_ids'] as List? ?? [])
                          Text(
                              '${(p['place_ids'] as List).indexOf(id) + 1}. ${app.places.where((r) => r['id'] == id).firstOrNull?['name'] ?? 'Listing unavailable'}',
                              style: const TextStyle(fontSize: 12)),
                        if (value(p, 'notes').isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(value(p, 'notes'),
                              style:
                                  const TextStyle(fontSize: 12, color: muted))
                        ],
                        Row(children: [
                          TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(
                                    text:
                                        '${p['title']}\n${(p['place_ids'] as List? ?? []).map((id) => app.places.where((r) => r['id'] == id).firstOrNull?['name'] ?? id).join('\n')}\n${p['notes']}'));
                                toast(context, 'Trip copied.');
                              },
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('Copy')),
                          TextButton(
                              onPressed: () async {
                                if (await confirm(context, 'Delete trip plan?',
                                        'This removes the saved itinerary.',
                                        action: 'Delete') &&
                                    context.mounted)
                                  await perform(
                                      context, () => app.deletePlan(p));
                              },
                              child: const Text('Delete'))
                        ])
                      ])),
          ]
        ]));
  }
}

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, this.initialPlaces = const []});
  final List<String> initialPlaces;
  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  final form = GlobalKey<FormState>(),
      title = TextEditingController(text: 'My Philippine adventure'),
      notes = TextEditingController();
  late List<String> ids;
  bool busy = false;
  String filter = '';
  @override
  void initState() {
    super.initState();
    ids = widget.initialPlaces.toSet().take(8).toList();
  }

  @override
  void dispose() {
    title.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text('Build your itinerary')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Form(
              key: form,
              child: Column(children: [
                Field('Trip name', title, required: true, maxLength: 150),
                Field('Notes, budget and travel dates', notes,
                    lines: 3, maxLength: 6000)
              ])),
          const Text(
              'Choose up to 8 stops. Use the arrows to change the order.',
              style: TextStyle(fontSize: 11, color: muted)),
          for (var i = 0; i < ids.length; i++)
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                    radius: 14,
                    child:
                        Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                title: Text(
                    '${app.places.where((p) => p['id'] == ids[i]).firstOrNull?['name'] ?? ids[i]}',
                    style: const TextStyle(fontSize: 12)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      tooltip: 'Move stop up',
                      onPressed: i == 0
                          ? null
                          : () {
                              setState(() {
                                final p = ids.removeAt(i);
                                ids.insert(i - 1, p);
                              });
                            },
                      icon: const Icon(Icons.arrow_upward, size: 17)),
                  IconButton(
                      tooltip: 'Remove stop',
                      onPressed: () => setState(() => ids.removeAt(i)),
                      icon: const Icon(Icons.close, size: 17))
                ])),
          const SizedBox(height: 16),
          TextField(
              onChanged: (v) => setState(() => filter = v),
              decoration: const InputDecoration(
                  hintText: 'Find a stop', prefixIcon: Icon(Icons.search))),
          for (final p in app.publicPlaces.where((p) =>
              '${p['name']} ${p['address']}'
                  .toLowerCase()
                  .contains(filter.toLowerCase())))
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(value(p, 'name'),
                    style: const TextStyle(fontSize: 12)),
                subtitle: Text(value(p, 'address'),
                    style: const TextStyle(fontSize: 10)),
                value: ids.contains('${p['id']}'),
                onChanged: (v) {
                  if (v! && ids.length >= 8) {
                    toast(context, 'Choose up to eight stops.');
                    return;
                  }
                  setState(() {
                    if (v) {
                      ids.add('${p['id']}');
                    } else {
                      ids.remove('${p['id']}');
                    }
                  });
                }),
          const SizedBox(height: 20),
          PrimaryButton(
              label: 'Save itinerary',
              busy: busy,
              onPressed: () async {
                if (!form.currentState!.validate() || ids.isEmpty) {
                  toast(context, 'Add a trip name and at least one stop.');
                  return;
                }
                setState(() => busy = true);
                await perform(context, () async {
                  final synced = await app.savePlan(
                      title.text.trim(), ids, notes.text.trim());
                  if (context.mounted) {
                    toast(
                        context,
                        synced
                            ? 'Trip saved to your account.'
                            : 'Trip saved on this device.');
                    Navigator.pop(context);
                  }
                });
                if (mounted) setState(() => busy = false);
              }),
        ]));
  }
}
