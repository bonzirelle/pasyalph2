import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_state.dart';
import 'ui.dart';
import 'account.dart';
import 'map_page.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key, required this.onMap});
  final VoidCallback onMap;
  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  String query = '', category = 'All';
  final search = TextEditingController();
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.publicPlaces
        .where((p) =>
            (category == 'All' || p['category'] == category) &&
            '${p['name']} ${p['address']}'
                .toLowerCase()
                .contains(query.toLowerCase()))
        .toList()
      ..sort((a, b) {
        final s =
            (b['sponsored'] == true ? 1 : 0) - (a['sponsored'] == true ? 1 : 0);
        return s != 0
            ? s
            : distanceKm(app.location ?? pilot, coordinates(a))
                .compareTo(distanceKm(app.location ?? pilot, coordinates(b)));
      });
    return RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(padding: const EdgeInsets.only(bottom: 80), children: [
          SizedBox(
              height: 246,
              child: Stack(fit: StackFit.expand, children: [
                const PlacePhoto('assets/images/taal.jpg', height: 246),
                DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                      Colors.black.withValues(alpha: .2),
                      ink.withValues(alpha: .3),
                      Theme.of(context).scaffoldBackgroundColor
                    ]))),
                Positioned(
                    top: 20,
                    right: 18,
                    child: FilledButton.tonal(
                        onPressed: () => openPage(context, const AccountPage()),
                        style: FilledButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: .92),
                            foregroundColor: ink,
                            minimumSize: const Size(0, 36),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.person_outline, size: 16),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 90),
                              child: Text(app.signedIn ? app.name : 'Log in',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11)))
                        ]))),
                const Positioned(
                    left: 20,
                    top: 62,
                    right: 20,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.location_on_outlined,
                                size: 14, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Tagaytay City, Cavite',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700))
                          ]),
                          SizedBox(height: 10),
                          Row(children: [
                            BrandLogo(size: 40),
                            SizedBox(width: 10),
                            BrandTitle(light: true, size: 35)
                          ]),
                          SizedBox(height: 9),
                          Row(children: [
                            Icon(Icons.auto_awesome,
                                size: 13, color: Colors.white),
                            SizedBox(width: 6),
                            Flexible(
                                child: Text('Verified places, honest reviews.',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.white)))
                          ])
                        ])),
                Positioned(
                    bottom: 0,
                    left: 20,
                    right: 20,
                    child: Material(
                        elevation: 6,
                        shadowColor: Colors.black12,
                        borderRadius: BorderRadius.circular(18),
                        child: TextField(
                            controller: search,
                            onChanged: (v) => setState(() => query = v),
                            decoration: InputDecoration(
                                hintText: 'Search spots, food, stays…',
                                prefixIcon: const Icon(Icons.search, size: 20),
                                suffixIcon: query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: () {
                                          search.clear();
                                          setState(() => query = '');
                                        },
                                        icon:
                                            const Icon(Icons.close, size: 17)),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(18),
                                    borderSide: BorderSide.none))))),
              ])),
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: Text(
                  'PasyalPH currently covers destinations in the Philippines only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: muted))),
          SizedBox(
              height: 37,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: categories.length,
                  separatorBuilder: (_, i) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ChoiceChip(
                      label: Text(categories[i],
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700)),
                      selected: category == categories[i],
                      showCheckmark: false,
                      selectedColor: Theme.of(context).colorScheme.primary,
                      labelStyle: TextStyle(
                          color: category == categories[i]
                              ? Theme.of(context).colorScheme.onPrimary
                              : null),
                      side: BorderSide.none,
                      onSelected: (_) =>
                          setState(() => category = categories[i]),
                      shape: const StadiumBorder()))),
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(children: [
                Expanded(
                    child: Text('${list.length} places to explore',
                        style: const TextStyle(fontSize: 11, color: muted))),
                FilledButton.icon(
                    onPressed: widget.onMap,
                    icon: const Icon(Icons.map_outlined, size: 15),
                    label: const Text('Map'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 34),
                        shape: const StadiumBorder()))
              ])),
          if (app.loading) const LinearProgressIndicator(minHeight: 2),
          if (app.loadError != null)
            Padding(
                padding: const EdgeInsets.all(20),
                child: Surface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Showing the original sample catalog',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('Live data could not be refreshed. ${app.loadError}',
                          style: const TextStyle(fontSize: 11)),
                      TextButton(
                          onPressed: app.refresh,
                          child: const Text('Try again'))
                    ]))),
          if (list.any(sample))
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Text(
                    'Original sample catalog · confirm details before visiting.',
                    style: TextStyle(fontSize: 10, color: muted))),
          if (category == 'All' || category == 'Tourist Spot')
            PlaceSection('Tourist Spots',
                list.where((p) => p['category'] == 'Tourist Spot').toList()),
          if (category == 'All' || category == 'Stay')
            PlaceSection('Airbnb-style Stays',
                list.where((p) => p['category'] == 'Stay').toList(),
                subtitle:
                    'Sample rentals · host and booking details need verification'),
          if (category == 'All' || !['Tourist Spot', 'Stay'].contains(category))
            PlaceSection(
                'Nearby Places',
                list
                    .where((p) =>
                        !['Tourist Spot', 'Stay'].contains(p['category']))
                    .toList(),
                subtitle: app.location == null
                    ? 'Distances from Tagaytay City center'
                    : 'Distances from your selected location'),
          if (list.isEmpty)
            const EmptyState('No listed places found',
                'Try another search or use the map to find other Philippine destinations.'),
        ]));
  }
}

class PlaceSection extends StatelessWidget {
  const PlaceSection(this.title, this.places, {super.key, this.subtitle});
  final String title;
  final String? subtitle;
  final List<JsonMap> places;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SectionTitle(title, subtitle: subtitle)),
        if (places.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Surface(
                  child: Text('New listings coming soon.',
                      style: TextStyle(color: muted, fontSize: 12))))
        else
          SizedBox(
              height: 265,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  itemCount: places.length,
                  separatorBuilder: (_, i) => const SizedBox(width: 12),
                  itemBuilder: (c, i) => SizedBox(
                      width: MediaQuery.sizeOf(c).width * .79,
                      child: PlaceCard(places[i]))))
      ]);
}

class PlaceCard extends StatelessWidget {
  const PlaceCard(this.place, {super.key, this.compact = false});
  final JsonMap place;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value(place, 'name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 5),
          Text(value(place, 'address'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: muted)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.star, size: 14, color: accent),
            const SizedBox(width: 4),
            Text(app.rating(place),
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            Text(' (${app.reviewsFor(place).length})',
                style: const TextStyle(fontSize: 10, color: muted)),
            const Spacer(),
            Text(app.distance(place),
                style: const TextStyle(fontSize: 10, color: muted))
          ])
        ]);
    return Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(19),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: () => openPage(context, PlacePage(place: place)),
            child: compact
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(children: [
                      ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: PlacePhoto(value(place, 'image'),
                              height: 88, width: 88)),
                      const SizedBox(width: 12),
                      Expanded(child: details)
                    ]))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Stack(children: [
                          PlacePhoto(value(place, 'image'), height: 157),
                          Positioned(
                              top: 10,
                              left: 10,
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: .93),
                                      borderRadius: BorderRadius.circular(30)),
                                  child: Text(value(place, 'category'),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: ink)))),
                          Positioned(
                              top: 5,
                              right: 5,
                              child: IconButton.filledTonal(
                                  tooltip: app.isSaved(place)
                                      ? 'Remove saved place'
                                      : 'Save place',
                                  onPressed: () => perform(context, () async {
                                        toast(context,
                                            await app.toggleSave(place));
                                      }),
                                  icon: Icon(
                                      app.isSaved(place)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 18),
                                  style: IconButton.styleFrom(
                                      backgroundColor:
                                          Colors.white.withValues(alpha: .93),
                                      foregroundColor: ink))),
                          if (place['sponsored'] == true)
                            const Positioned(
                                bottom: 8,
                                left: 10,
                                child: StatusPill('Sponsored',
                                    color: Color(0xffa15b00))),
                          if (app.promotionsFor(place).isNotEmpty)
                            Positioned(
                                bottom: 8,
                                right: 10,
                                child: StatusPill(
                                    app
                                                .promotionsFor(place)
                                                .first['discount_label']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true
                                        ? app
                                            .promotionsFor(place)
                                            .first['discount_label']
                                            .toString()
                                        : 'Promotion',
                                    color: const Color(0xffa15b00)))
                        ]),
                        Padding(
                            padding: const EdgeInsets.all(13), child: details)
                      ])));
  }
}

class PlacePage extends StatefulWidget {
  const PlacePage({super.key, required this.place});
  final JsonMap place;
  @override
  State<PlacePage> createState() => _PlacePageState();
}

class _PlacePageState extends State<PlacePage> {
  final review = TextEditingController();
  int rating = 5;
  bool busy = false;
  @override
  void dispose() {
    review.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p =
        app.places.where((p) => p['id'] == widget.place['id']).firstOrNull ??
            widget.place;
    final nearby = app.publicPlaces.where((r) => r['id'] != p['id']).toList()
      ..sort((a, b) => distanceKm(coordinates(p), coordinates(a))
          .compareTo(distanceKm(coordinates(p), coordinates(b))));
    return Scaffold(
        body: SafeArea(
            child:
                ListView(padding: const EdgeInsets.only(bottom: 25), children: [
      SizedBox(
          height: 240,
          child: Stack(fit: StackFit.expand, children: [
            PlacePhoto(value(p, 'image'), height: 240),
            Positioned(
                top: 15,
                left: 15,
                child: IconButton.filledTonal(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back))),
            Positioned(
                top: 15,
                right: 15,
                child: IconButton.filledTonal(
                    tooltip: 'Save place',
                    onPressed: () => perform(context, () async {
                          toast(context, await app.toggleSave(p));
                        }),
                    icon: Icon(app.isSaved(p)
                        ? Icons.favorite
                        : Icons.favorite_border)))
          ])),
      Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              StatusPill(sample(p) ? 'Original sample' : value(p, 'status'),
                  color: sample(p) ? muted : const Color(0xff327d50)),
              if (p['sponsored'] == true)
                const StatusPill('Sponsored', color: Color(0xffa15b00))
            ]),
            const SizedBox(height: 12),
            Text(value(p, 'name'),
                style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 5),
            Text('★ ${app.rating(p)} · ${p['category']} · ${app.distance(p)}',
                style: const TextStyle(color: muted, fontSize: 12)),
            const SizedBox(height: 16),
            Text(value(p, 'description')),
            if (app.promotionsFor(p).isNotEmpty) ...[
              const SizedBox(height: 16),
              Surface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Current promotions',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    for (final promotion in app.promotionsFor(p))
                      Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(value(promotion, 'title'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                if (value(promotion, 'discount_label')
                                    .isNotEmpty)
                                  Text(value(promotion, 'discount_label'),
                                      style: const TextStyle(
                                          color: Color(0xffa15b00),
                                          fontWeight: FontWeight.w700)),
                                if (value(promotion, 'description').isNotEmpty)
                                  Text(value(promotion, 'description')),
                              ]))
                  ]))
            ],
            const SizedBox(height: 18),
            Surface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _info(Icons.location_on_outlined, value(p, 'address')),
                  _info(Icons.schedule, value(p, 'hours')),
                  _info(Icons.phone_outlined, value(p, 'contact')),
                  _info(Icons.sell_outlined, value(p, 'rates')),
                  Text(
                      'Last updated: ${value(p, 'source_updated', value(p, 'updated_at').split('T').first)}. Prices may change.',
                      style: const TextStyle(color: muted, fontSize: 10)),
                  if (sample(p))
                    const Text(
                        'Sample details from the original app; not independently verified.',
                        style: TextStyle(color: muted, fontSize: 10))
                ])),
            const SizedBox(height: 12),
            Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ((p['amenities'] as List?) ?? [])
                    .map(
                        (a) => StatusPill('$a', color: const Color(0xff5b666e)))
                    .toList()),
            const SectionTitle('Getting there'),
            for (final route in (p['routes'] as List? ?? []))
              Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Surface(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Icon(Icons.navigation_outlined,
                            color: accent, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  '${route['mode']} ${route['estimate'] ?? ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              Text('${route['detail']}',
                                  style: const TextStyle(
                                      color: muted, fontSize: 12))
                            ]))
                      ]))),
            const Text(
                'Fares are indicative estimates; actual costs may differ.',
                style: TextStyle(color: muted, fontSize: 10)),
            const SizedBox(height: 12),
            PrimaryButton(
                label: 'Plan a route',
                icon: Icons.directions,
                onPressed: () => openPage(context, MapPage(destination: p))),
            Row(children: [
              Expanded(
                  child: TextButton.icon(
                      onPressed: () => openUrl(context,
                          'https://www.openstreetmap.org/?mlat=${p['lat']}&mlon=${p['lng']}#map=16/${p['lat']}/${p['lng']}'),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('OpenStreetMap',
                          style: TextStyle(fontSize: 11)))),
              IconButton(
                  tooltip: 'Copy place link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text:
                            '${p['name']} — https://www.openstreetmap.org/?mlat=${p['lat']}&mlon=${p['lng']}#map=16/${p['lat']}/${p['lng']}'));
                    toast(context, 'Place link copied.');
                  },
                  icon: const Icon(Icons.share_outlined, size: 18))
            ]),
            const SectionTitle('Reviews'),
            Surface(
                child: Column(children: [
              Row(
                  children: List.generate(
                      5,
                      (i) => Expanded(
                          child: IconButton(
                              tooltip: 'Rate ${i + 1} stars',
                              onPressed: () => setState(() => rating = i + 1),
                              icon: Icon(
                                  i < rating ? Icons.star : Icons.star_border,
                                  color: accent))))),
              const SizedBox(height: 10),
              TextField(
                  controller: review,
                  maxLength: 2000,
                  maxLines: 3,
                  decoration: InputDecoration(
                      hintText: app.signedIn
                          ? 'Share your experience…'
                          : 'Log in to share your experience…')),
              if (!app.signedIn)
                TextButton(
                    onPressed: () => openPage(context, const AccountPage()),
                    child: const Text('Log in or sign up')),
              PrimaryButton(
                  label: 'Post review',
                  busy: busy,
                  onPressed: () async {
                    if (review.text.trim().length < 5) {
                      toast(context, 'Write at least 5 characters.');
                      return;
                    }
                    setState(() => busy = true);
                    await perform(context, () async {
                      await app.postReview(p, rating, review.text);
                      review.clear();
                    }, success: 'Review saved.');
                    if (mounted) setState(() => busy = false);
                  })
            ])),
            for (final r in app.reviewsFor(p))
              Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Surface(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Expanded(
                              child: Text(
                                  r['user_id'] == app.user?.id
                                      ? 'Your review'
                                      : 'PasyalPH traveler',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700))),
                          if (r['user_id'] == app.user?.id)
                            IconButton(
                                tooltip: 'Delete review',
                                icon:
                                    const Icon(Icons.delete_outline, size: 16),
                                onPressed: () async {
                                  if (await confirm(
                                          context,
                                          'Delete your review?',
                                          'This removes your review from the listing.',
                                          action: 'Delete') &&
                                      context.mounted)
                                    await perform(context, () async {
                                      await app.client
                                          .from('reviews')
                                          .delete()
                                          .eq('id', r['id'])
                                          .eq('user_id', app.user!.id);
                                      await app.refresh();
                                    });
                                })
                        ]),
                        Text('★' * number(r['rating']).toInt(),
                            style: const TextStyle(color: accent)),
                        Text(value(r, 'body')),
                        Text(value(r, 'created_at').split('T').first,
                            style: const TextStyle(fontSize: 10, color: muted))
                      ]))),
            if (app.reviewsFor(p).isEmpty)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('No traveler reviews yet. Be the first!',
                      style: TextStyle(color: muted, fontSize: 12))),
            if (app.sampleReviews(p).isNotEmpty)
              ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Reviews from the original sample',
                      style: TextStyle(fontSize: 12)),
                  subtitle: const Text(
                      'Demo content, separate from traveler ratings',
                      style: TextStyle(fontSize: 10, color: muted)),
                  children: [
                    for (final r in app.sampleReviews(p))
                      ListTile(
                          title: Text('${r['user']} · ${r['rating']} ★',
                              style: const TextStyle(fontSize: 12)),
                          subtitle: Text('${r['text']}',
                              style: const TextStyle(fontSize: 12)))
                  ]),
            const SectionTitle('Also nearby'),
            for (final n in nearby.take(3))
              Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PlaceCard(n, compact: true)),
            TextButton.icon(
                onPressed: () => _report(context, app, p),
                icon: const Icon(Icons.flag_outlined, size: 17),
                label: const Text('Report this listing'),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error)),
          ])),
    ])));
  }

  Widget _info(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: muted),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text.isEmpty ? 'Confirm with the venue' : text,
                style: const TextStyle(fontSize: 12)))
      ]));
  Future<void> _report(BuildContext context, AppState app, JsonMap p) async {
    final reason = TextEditingController();
    final text = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Report this listing'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Tell us what is incorrect or inappropriate.'),
                  const SizedBox(height: 14),
                  TextField(
                      controller: reason,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration:
                          const InputDecoration(hintText: 'Describe the issue'))
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        if (reason.text.trim().length >= 5)
                          Navigator.pop(c, reason.text.trim());
                      },
                      child: const Text('Send report'))
                ]));
    reason.dispose();
    if (text != null && context.mounted)
      await perform(context, () => app.report(p, text),
          success: 'Report sent for review.');
  }
}

class SavedPage extends StatelessWidget {
  const SavedPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final list = app.publicPlaces.where(app.isSaved).toList();
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: !embedded,
            title: const Text('Saved places')),
        body: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              const Text('Keep your next adventure close.',
                  style: TextStyle(color: muted)),
              if (app.localSaved.isNotEmpty)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        'Sample saves are stored on this device. Published listings sync to your account.',
                        style: TextStyle(fontSize: 11, color: muted))),
              if (list.isEmpty)
                EmptyState('Your wishlist starts here',
                    'Tap the heart on a place to save it for later.',
                    icon: Icons.favorite_border,
                    action: !app.signedIn
                        ? PrimaryButton(
                            label: 'Log in to sync saved places',
                            onPressed: () =>
                                openPage(context, const AccountPage()))
                        : null),
              for (final p in list)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: PlaceCard(p, compact: true))
            ])));
  }
}
