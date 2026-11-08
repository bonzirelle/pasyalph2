import 'package:flutter/material.dart';
import 'app_state.dart';
import 'ui.dart';
import 'account.dart';

const _adminCategories = [
  'Tourist Spot',
  'Food',
  'Resort',
  'Stay',
  'Shop'
];
const _adminStatuses = [
  'Verified',
  'Pending Verification',
  'Rejected',
  'Suspended'
];
const _adminGreen = Color(0xff2e735c);
const _adminPale = Color(0xffeaf3ed);

class AdminPortal extends StatefulWidget {
  const AdminPortal({super.key});
  @override
  State<AdminPortal> createState() => _AdminPortalState();
}

class _AdminPortalState extends State<AdminPortal> {
  int section = 0;
  String search = '';
  String status = 'All statuses';

  static const _sections = [
    ('Overview', Icons.space_dashboard_outlined),
    ('Business listings', Icons.storefront_outlined),
    ('Accommodations', Icons.hotel_outlined),
    ('Destinations', Icons.landscape_outlined),
    ('Applications', Icons.assignment_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 980;
    if (!app.signedIn || app.role != 'admin') {
      return Scaffold(
        backgroundColor: const Color(0xfff5f7f4),
        appBar: AppBar(title: const Text('PasyalPH Admin')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Surface(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 44, color: _adminGreen),
                    const SizedBox(height: 12),
                    Text(
                      app.signedIn
                          ? 'Administrator access required'
                          : 'Sign in to the admin portal',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This portal is restricted to accounts granted the administrator role.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: app.signedIn ? 'Back to PasyalPH' : 'Sign in',
                      onPressed: () => openPage(
                          context,
                          app.signedIn
                              ? const ProfilePage()
                              : const AccountPage()),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final livePlaces = app.places
        .where((place) => app.remoteIds.contains('${place['id']}'))
        .toList();
    final listings = _listingFilter(livePlaces);
    final title = _sections[section].$1;

    return Scaffold(
      backgroundColor: const Color(0xfff5f7f4),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) _sidebar(app),
            Expanded(
              child: Column(
                children: [
                  _header(app, wide, title),
                  if (!wide) _mobileNavigation(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: app.refresh,
                      child: app.loading
                          ? const Center(child: CircularProgressIndicator())
                          : app.loadError != null && livePlaces.isEmpty
                              ? _loadError(app)
                              : _content(app, livePlaces, listings),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sidebar(AppState app) => Container(
        width: 244,
        color: const Color(0xff123e3e),
        padding: const EdgeInsets.fromLTRB(17, 24, 13, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const BrandLogo(size: 42),
              const SizedBox(width: 11),
              const Expanded(
                  child: Text('PasyalPH\nADMIN PORTAL',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5))),
            ]),
            const SizedBox(height: 36),
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 10),
              child: Text('WORKSPACE',
                  style: TextStyle(
                      color: Color(0xffa5c1b6),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3)),
            ),
            for (var i = 0; i < _sections.length; i++)
              _navItem(i, app),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: const Icon(Icons.fact_check_outlined,
                  color: Color(0xffc4d8cf), size: 20),
              title: const Text('Moderation queue',
                  style: TextStyle(color: Color(0xffe0ece6), fontSize: 12)),
              onTap: () => Navigator.of(context).pushNamed('/moderation'),
            ),
            const Spacer(),
            const Divider(color: Color(0x447fa7a0)),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: const Icon(Icons.open_in_new,
                  color: Color(0xffd9e8e0), size: 19),
              title: const Text('Open traveler app',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              onTap: () => Navigator.of(context).pushNamed('/'),
            ),
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: const Icon(Icons.logout,
                  color: Color(0xffd9e8e0), size: 19),
              title: const Text('Sign out',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
              onTap: () async {
                await app.client.auth.signOut();
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      );

  Widget _navItem(int index, AppState app) {
    final selected = section == index;
    final count = index == 4
        ? app.applications
            .where((application) => application['status'] == 'Pending review')
            .length
        : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: const Color(0xff2c6259),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        leading: Icon(_sections[index].$2,
            color: selected ? Colors.white : const Color(0xffc4d8cf),
            size: 20),
        title: Text(_sections[index].$1,
            style: TextStyle(
                color: selected ? Colors.white : const Color(0xffe0ece6),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
        trailing: count > 0
            ? CircleAvatar(
                radius: 11,
                backgroundColor: const Color(0xffe5a839),
                child: Text('$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)))
            : null,
        onTap: () => setState(() => section = index),
      ),
    );
  }

  Widget _header(AppState app, bool wide, String title) => Container(
        height: 76,
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xffe8ece8))),
        ),
        child: Row(children: [
          if (!wide) const BrandLogo(size: 36),
          if (!wide) const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800)),
                Text('Manage the PasyalPH local travel catalog',
                    style: TextStyle(
                        fontSize: wide ? 11 : 9, color: Colors.blueGrey[500])),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh data',
            onPressed: app.refreshing ? null : app.refresh,
            icon: app.refreshing
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          const SizedBox(width: 6),
          CircleAvatar(
            radius: 17,
            backgroundColor: _adminPale,
            child: Text(app.name.isEmpty ? 'A' : app.name[0].toUpperCase(),
                style: const TextStyle(
                    color: _adminGreen, fontWeight: FontWeight.w800)),
          ),
          if (wide) ...[
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 11)),
                const Text('Administrator',
                    style: TextStyle(color: muted, fontSize: 10)),
              ],
            )
          ],
        ]),
      );

  Widget _mobileNavigation() => Container(
        height: 52,
        color: Colors.white,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (var i = 0; i < _sections.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: ChoiceChip(
                  label: Text(_sections[i].$1,
                      style: const TextStyle(fontSize: 10)),
                  selected: section == i,
                  onSelected: (_) => setState(() => section = i),
                ),
              )
          ],
        ),
      );

  Widget _content(
      AppState app, List<JsonMap> livePlaces, List<JsonMap> filtered) {
    switch (section) {
      case 0:
        return _dashboard(app, livePlaces);
      case 1:
        return _catalog(app, filtered, 'Business listings', 'All');
      case 2:
        return _catalog(app, filtered, 'Accommodations', 'Stay');
      case 3:
        return _catalog(app, filtered, 'Destinations', 'Tourist Spot');
      default:
        return _applications(app);
    }
  }

  Widget _dashboard(AppState app, List<JsonMap> places) {
    final verified = places.where((p) => p['status'] == 'Verified').length;
    final pending =
        places.where((p) => p['status'] == 'Pending Verification').length;
    final stays = places
        .where((p) => ['Stay', 'Resort'].contains(p['category']))
        .length;
    final destinations =
        places.where((p) => p['category'] == 'Tourist Spot').length;
    final pendingOwners = app.applications
        .where((a) => a['status'] == 'Pending review')
        .length;
    final columns = MediaQuery.sizeOf(context).width >= 1050 ? 4 : 2;
    final cards = [
      _Metric('Catalog listings', '${places.length}', Icons.storefront_outlined,
          const Color(0xffe9f2ed), _adminGreen),
      _Metric('Verified', '$verified', Icons.verified_outlined,
          const Color(0xffeaf4f1), const Color(0xff38846d)),
      _Metric('Accommodations', '$stays', Icons.hotel_outlined,
          const Color(0xfffff2df), const Color(0xffba7920)),
      _Metric('Destinations', '$destinations', Icons.landscape_outlined,
          const Color(0xffedf0fa), const Color(0xff6572a5)),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _welcome(places.length),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (context, constraints) {
          final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final metric in cards)
                SizedBox(width: width, child: _metricCard(metric))
            ],
          );
        }),
        const SizedBox(height: 22),
        LayoutBuilder(builder: (context, constraints) {
          final split = constraints.maxWidth >= 820;
          final statusCard = _statusCard(places);
          final quickCard = _quickActions(places, pending, pendingOwners);
          if (!split) {
            return Column(children: [
              statusCard,
              const SizedBox(height: 16),
              quickCard,
              const SizedBox(height: 16),
              _recentListings(places),
            ]);
          }
          return Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: statusCard),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: quickCard),
            ]),
            const SizedBox(height: 16),
            _recentListings(places),
          ]);
        }),
      ],
    );
  }

  Widget _welcome(int count) => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
              colors: [Color(0xff164849), Color(0xff32745f)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mabuhay, admin!',
                    style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Fraunces',
                        fontSize: 24,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                    'Your catalog has $count live ${count == 1 ? 'listing' : 'listings'}. Keep local discoveries up to date.',
                    style: const TextStyle(
                        color: Color(0xffd6e8df), fontSize: 11, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.explore, color: Color(0x66ffffff), size: 52),
        ]),
      );

  Widget _metricCard(_Metric metric) => Container(
        padding: const EdgeInsets.all(17),
        decoration: _cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: metric.background,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(metric.icon, color: metric.color, size: 20),
          ),
          const SizedBox(height: 15),
          Text(metric.value,
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          Text(metric.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: muted)),
        ]),
      );

  Widget _statusCard(List<JsonMap> places) {
    final values = [
      ('Verified', const Color(0xff40856c)),
      ('Pending Verification', const Color(0xffd69a36)),
      ('Rejected', const Color(0xffc76657)),
      ('Suspended', const Color(0xff78828d)),
    ];
    final total = places.length;
    return _panel(
      title: 'Listing status',
      subtitle: 'Current review status across the live catalog',
      child: Column(
        children: [
          for (final item in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Row(children: [
                SizedBox(
                    width: 125,
                    child: Text(item.$1,
                        style: const TextStyle(fontSize: 10, color: muted))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: total == 0
                          ? 0
                          : places
                                  .where((p) => p['status'] == item.$1)
                                  .length /
                              total,
                      backgroundColor: const Color(0xffeef1ee),
                      color: item.$2,
                    ),
                  ),
                ),
                SizedBox(
                    width: 38,
                    child: Text(
                        '${places.where((p) => p['status'] == item.$1).length}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800))),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Based on $total live listings',
                style: const TextStyle(color: muted, fontSize: 9)),
          )
        ],
      ),
    );
  }

  Widget _quickActions(List<JsonMap> places, int pending, int pendingOwners) =>
      _panel(
        title: 'Needs attention',
        subtitle: 'Review items awaiting admin action',
        child: Column(children: [
          _attentionRow(Icons.hourglass_top, 'Listings to verify', '$pending',
              const Color(0xffd69a36),
              onTap: () => setState(() {
                    section = 1;
                    status = 'Pending Verification';
                  })),
          const Divider(height: 20),
          _attentionRow(Icons.business_center_outlined, 'Owner applications',
              '$pendingOwners', _adminGreen,
              onTap: () => setState(() => section = 4)),
          const Divider(height: 20),
          _attentionRow(
              Icons.reviews_outlined, 'Traveler reviews', '${AppScope.of(context).reviews.length}',
              const Color(0xff6478a8)),
        ]),
      );

  Widget _attentionRow(
          IconData icon, String label, String count, Color color,
          {VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w600))),
            Text(count,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 17, color: muted)
          ]),
        ),
      );

  Widget _recentListings(List<JsonMap> places) {
    final recent = [...places]
      ..sort((a, b) => value(b, 'updated_at').compareTo(value(a, 'updated_at')));
    return _panel(
      title: 'Recently updated',
      subtitle: 'The latest listings in your catalog',
      trailing: TextButton(
          onPressed: () => setState(() => section = 1),
          child: const Text('View all', style: TextStyle(fontSize: 10))),
      child: recent.isEmpty
          ? const Text('No live listings yet.',
              style: TextStyle(color: muted, fontSize: 11))
          : Column(
              children: [
                for (final place in recent.take(5))
                  _listingRow(place, compact: true),
              ],
            ),
    );
  }

  Widget _catalog(
      AppState app, List<JsonMap> places, String heading, String category) {
    final isAll = category == 'All';
    final count = places.length;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(heading,
                      style: const TextStyle(
                          fontFamily: 'Fraunces',
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('$count ${count == 1 ? 'listing' : 'listings'}',
                      style: const TextStyle(color: muted, fontSize: 10)),
                ]),
          ),
          FilledButton.icon(
            onPressed: () => _editPlace(app),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Add listing',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: _cardDecoration(),
          child: LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 580;
            final searchField = TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 19),
                hintText: 'Search name, address or category',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
              onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
            );
            final statusField = DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(
                  labelText: 'Status', isDense: true, border: OutlineInputBorder()),
              items: [
                'All statuses',
                ..._adminStatuses,
              ]
                  .map((v) =>
                      DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 10))))
                  .toList(),
              onChanged: (v) => setState(() => status = v ?? 'All statuses'),
            );
            if (stacked) {
              return Column(children: [
                searchField,
                const SizedBox(height: 10),
                statusField,
              ]);
            }
            return Row(children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              SizedBox(width: 210, child: statusField),
            ]);
          }),
        ),
        const SizedBox(height: 14),
        if (places.isEmpty)
          _panel(
            title: 'No listings yet',
            child: const Text(
                'Create a listing to publish it to the shared PasyalPH catalog.',
                style: TextStyle(fontSize: 11, color: muted)),
          )
        else
          _panel(
            title: 'Catalog',
            subtitle: 'Edits are shared with the traveler app',
            child: Column(children: [
              for (final place in places) _listingRow(place),
              if (!isAll)
                const SizedBox(height: 2),
            ]),
          ),
      ],
    );
  }

  List<JsonMap> _listingFilter(List<JsonMap> livePlaces) {
    final category = section == 2
        ? const ['Stay', 'Resort']
        : section == 3
            ? const ['Tourist Spot']
            : null;
    return livePlaces.where((place) {
      if (category != null && !category.contains(place['category'])) {
        return false;
      }
      if (status != 'All statuses' && place['status'] != status) return false;
      if (search.isEmpty) return true;
      return [
        value(place, 'name'),
        value(place, 'address'),
        value(place, 'category'),
      ].any((v) => v.toLowerCase().contains(search));
    }).toList()
      ..sort((a, b) => value(a, 'name').compareTo(value(b, 'name')));
  }

  Widget _listingRow(JsonMap place, {bool compact = false}) {
    final app = AppScope.of(context);
    final image = value(place, 'image');
    final category = value(place, 'category');
    final title = value(place, 'name', 'Untitled listing');
    final subtitle = compact
        ? '$category · ${value(place, 'address')}'
        : value(place, 'address');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xffedf0ed)))),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: image.startsWith('http')
                ? Image.network(image,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _imagePlaceholder())
                : _imagePlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 11)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: muted)),
                  if (!compact) ...[
                    const SizedBox(height: 5),
                    Wrap(spacing: 5, runSpacing: 4, children: [
                      _tag(category),
                      _tag(value(place, 'status'), statusColor: true),
                    ])
                  ]
                ]),
          ),
          const SizedBox(width: 8),
          if (compact)
            _tag(value(place, 'status'), statusColor: true)
          else
            PopupMenuButton<String>(
              tooltip: 'Listing actions',
              onSelected: (action) {
                if (action == 'edit') _editPlace(app, place);
                if (action == 'delete') _deletePlace(app, place);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit listing')),
                PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete listing',
                        style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tag(String text, {bool statusColor = false}) {
    final color = statusColor
        ? switch (text) {
            'Verified' => const Color(0xff33785e),
            'Rejected' => const Color(0xffb6534b),
            'Suspended' => const Color(0xff68737c),
            _ => const Color(0xffa06b1b),
          }
        : const Color(0xff456d63);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 8, fontWeight: FontWeight.w800)),
    );
  }

  Widget _imagePlaceholder() => Container(
        width: 46,
        height: 46,
        color: _adminPale,
        child: const Icon(Icons.place_outlined, color: _adminGreen, size: 21),
      );

  Future<void> _editPlace(AppState app, [JsonMap? place]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdminPlaceDialog(place: place),
    );
    if (result == true && mounted) {
      await app.refresh();
      if (mounted) toast(context, place == null ? 'Listing created.' : 'Listing updated.');
    }
  }

  Future<void> _deletePlace(AppState app, JsonMap place) async {
    final yes = await confirm(
      context,
      'Delete ${value(place, 'name')}?',
      'This permanently removes the listing from the shared traveler catalog.',
      action: 'Delete listing',
    );
    if (!yes || !mounted) return;
    await perform(context, () async {
      await app.client.from('places').delete().eq('id', place['id']);
      await app.refresh();
    }, success: 'Listing deleted.');
  }

  Widget _applications(AppState app) {
    final applications = app.applications;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Business applications',
            style: const TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 24,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text('${applications.length} applications',
            style: const TextStyle(color: muted, fontSize: 10)),
        const SizedBox(height: 17),
        if (applications.isEmpty)
          _panel(
              title: 'No applications',
              child: const Text('Business owner registrations will appear here.',
                  style: TextStyle(color: muted, fontSize: 11)))
        else
          _panel(
            title: 'Registrations',
            child: Column(children: [
              for (final application in applications)
                _applicationRow(app, application),
            ]),
          ),
      ],
    );
  }

  Widget _applicationRow(AppState app, JsonMap application) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xffedf0ed)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(value(application, 'business_name'),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800))),
            _tag(value(application, 'status'), statusColor: true),
          ]),
          const SizedBox(height: 6),
          Text(
              '${value(application, 'legal_name')} · ${value(application, 'address')}',
              style: const TextStyle(fontSize: 9, color: muted)),
          Text(
              '${value(application, 'phone')} · Permit: ${value(application, 'permit_reference')}',
              style: const TextStyle(fontSize: 9, color: muted)),
          if (value(application, 'description').isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(value(application, 'description'),
                style: const TextStyle(fontSize: 10)),
          ],
          if (application['status'] == 'Pending review')
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: () => perform(context, () async {
                  await app.client.rpc('moderate_application', params: {
                    'application_id': application['id'],
                    'approved': true,
                  });
                  await app.refresh();
                }, success: 'Owner application approved.'),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Approve owner'),
              ),
              TextButton.icon(
                onPressed: () => perform(context, () async {
                  await app.client.rpc('moderate_application', params: {
                    'application_id': application['id'],
                    'approved': false,
                  });
                  await app.refresh();
                }, success: 'Owner application rejected.'),
                icon: const Icon(Icons.close, size: 16),
                label: const Text('Reject'),
              )
            ])
        ]),
      );

  Widget _loadError(AppState app) => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _panel(
            title: 'Could not load catalog data',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.loadError ?? 'Supabase is unavailable.',
                    style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: app.refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again')),
              ],
            ),
          )
        ],
      );

  Widget _panel(
          {required String title,
          String? subtitle,
          Widget? trailing,
          required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(17),
        decoration: _cardDecoration(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: const TextStyle(fontSize: 9, color: muted)),
                    ]
                  ]),
            ),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 15),
          child,
        ]),
      );

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xffe9ede9)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 3))
        ],
      );
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.background, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color background;
  final Color color;
}

class _AdminPlaceDialog extends StatefulWidget {
  const _AdminPlaceDialog({this.place});
  final JsonMap? place;
  @override
  State<_AdminPlaceDialog> createState() => _AdminPlaceDialogState();
}

class _AdminPlaceDialogState extends State<_AdminPlaceDialog> {
  final form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> fields = {
    for (final key in [
      'name',
      'description',
      'address',
      'image',
      'hours',
      'contact',
      'rates',
      'amenities',
      'lat',
      'lng'
    ])
      key: TextEditingController()
  };
  String category = 'Tourist Spot';
  String status = 'Pending Verification';
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final place = widget.place;
    if (place != null) {
      category = _adminCategories.contains(place['category'])
          ? value(place, 'category')
          : 'Tourist Spot';
      status = _adminStatuses.contains(place['status'])
          ? value(place, 'status')
          : 'Pending Verification';
      for (final entry in fields.entries) {
        final value = entry.key == 'amenities'
            ? (place[entry.key] as List? ?? []).join(', ')
            : '${place[entry.key] ?? ''}';
        entry.value.text = value;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final lat = double.tryParse(fields['lat']!.text.trim());
    final lng = double.tryParse(fields['lng']!.text.trim());
    if (lat == null ||
        lng == null ||
        lat < 4.2 ||
        lat > 21.5 ||
        lng < 116 ||
        lng > 127) {
      setState(() => error =
          'Enter valid Philippine coordinates (latitude 4.2–21.5, longitude 116–127).');
      return;
    }
    final image = fields['image']!.text.trim();
    if (image.isNotEmpty &&
        !image.startsWith('https://') &&
        !image.startsWith('assets/')) {
      setState(() => error = 'Use an HTTPS image URL or an app asset path.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
    });
    final app = AppScope.of(context);
    try {
      app.requireUser();
      final payload = <String, dynamic>{
        'name': fields['name']!.text.trim(),
        'description': fields['description']!.text.trim(),
        'address': fields['address']!.text.trim(),
        'image': image.isEmpty ? 'assets/images/pasyalph-new-logo.jpg' : image,
        'category': category,
        'hours': fields['hours']!.text.trim(),
        'contact': fields['contact']!.text.trim(),
        'rates': fields['rates']!.text.trim(),
        'amenities': fields['amenities']!
            .text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .take(20)
            .toList(),
        'lat': lat,
        'lng': lng,
        'status': status,
      };
      final existing = widget.place;
      if (existing == null) {
        payload['owner_id'] = null;
        await app.client.from('places').insert(payload);
      } else {
        await app.client
            .from('places')
            .update(payload)
            .eq('id', existing['id']);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700, maxHeight: 850),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Text(
                    widget.place == null ? 'Create listing' : 'Edit listing',
                    style: const TextStyle(
                        fontFamily: 'Fraunces',
                        fontSize: 21,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                    onPressed: busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      final single = constraints.maxWidth < 510;
                      final name = _field('Business name', 'name',
                          required: true, maxLength: 250);
                      final categoryField = DropdownButtonFormField<String>(
                        initialValue: category,
                        decoration:
                            const InputDecoration(labelText: 'Category'),
                        items: _adminCategories
                            .map((item) => DropdownMenuItem(
                                value: item, child: Text(item)))
                            .toList(),
                        onChanged: busy
                            ? null
                            : (value) => setState(() => category = value!),
                      );
                      if (single) {
                        return Column(children: [
                          name,
                          categoryField,
                        ]);
                      }
                      return Row(children: [
                        Expanded(child: name),
                        const SizedBox(width: 12),
                        Expanded(child: categoryField),
                      ]);
                    }),
                    _field('Description', 'description',
                        required: true,
                        minLength: 20,
                        maxLength: 2000,
                        lines: 4),
                    _field('Full address, city and province', 'address',
                        required: true, minLength: 5, maxLength: 500),
                    LayoutBuilder(builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 510;
                      final lat = _field('Latitude', 'lat',
                          required: true, numeric: true);
                      final lng = _field('Longitude', 'lng',
                          required: true, numeric: true);
                      if (narrow) return Column(children: [lat, lng]);
                      return Row(children: [
                        Expanded(child: lat),
                        const SizedBox(width: 12),
                        Expanded(child: lng),
                      ]);
                    }),
                    _field('Image URL or asset path', 'image',
                        maxLength: 1000),
                    LayoutBuilder(builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 510;
                      final hours = _field('Opening hours', 'hours',
                          maxLength: 250);
                      final contact =
                          _field('Contact details', 'contact', maxLength: 100);
                      if (narrow) return Column(children: [hours, contact]);
                      return Row(children: [
                        Expanded(child: hours),
                        const SizedBox(width: 12),
                        Expanded(child: contact),
                      ]);
                    }),
                    _field('Rates / price guide', 'rates', maxLength: 500),
                    _field('Amenities (comma separated)', 'amenities',
                        maxLength: 1000),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration:
                          const InputDecoration(labelText: 'Publication status'),
                      items: _adminStatuses
                          .map((item) => DropdownMenuItem(
                              value: item, child: Text(item)))
                          .toList(),
                      onChanged: busy
                          ? null
                          : (value) => setState(() => status = value!),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 11)),
                    ],
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              busy ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : save,
                          icon: busy
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.save_outlined, size: 17),
                          label: Text(widget.place == null
                              ? 'Create listing'
                              : 'Save changes'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _field(String label, String key,
      {bool required = false,
      int? minLength,
      int? maxLength,
      int lines = 1,
      bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: fields[key],
        maxLines: lines,
        maxLength: maxLength,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        decoration: InputDecoration(labelText: label),
        validator: (raw) {
          final value = raw?.trim() ?? '';
          if (required && value.isEmpty) return 'This field is required.';
          if (minLength != null && value.length < minLength) {
            return 'Enter at least $minLength characters.';
          }
          return null;
        },
      ),
    );
  }
}
