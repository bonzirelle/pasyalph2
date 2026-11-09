import 'package:flutter/material.dart';
import 'app_state.dart';
import 'ui.dart';
import 'account.dart';
import 'map_page.dart';
import 'explore.dart';

class BusinessApplicationPage extends StatefulWidget {
  const BusinessApplicationPage({super.key});
  @override
  State<BusinessApplicationPage> createState() =>
      _BusinessApplicationPageState();
}

class _BusinessApplicationPageState extends State<BusinessApplicationPage> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'legal_name',
      'business_name',
      'address',
      'phone',
      'permit_reference',
      'description'
    ])
      key: TextEditingController()
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in fields.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final application = app.applications
        .where((a) => a['owner_id'] == app.user?.id)
        .firstOrNull;
    return Scaffold(
        appBar: AppBar(title: const Text('Business registration')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('Bring your business to PasyalPH',
              style: TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 26,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
              'Register your business profile before submitting listings.',
              style: TextStyle(color: muted)),
          const SizedBox(height: 20),
          if (!app.signedIn)
            EmptyState('Log in to continue',
                'Business registration requires a verified PasyalPH account.',
                action: PrimaryButton(
                    label: 'Log in',
                    onPressed: () => openPage(context, const AccountPage())))
          else if (application != null && application['status'] != 'Rejected')
            Surface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  StatusPill(value(application, 'status')),
                  const SizedBox(height: 15),
                  Text(value(application, 'business_name'),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(application['status'] == 'Approved'
                      ? 'Your business profile is approved. You can submit listings for verification.'
                      : 'An administrator will review your registration. Your business tools will become available after approval.'),
                  if (application['status'] == 'Approved') ...[
                    const SizedBox(height: 15),
                    PrimaryButton(
                        label: 'Open business tools',
                        onPressed: () => openPage(context, const OwnerPage()))
                  ]
                ]))
          else
            Surface(
                child: Form(
                    key: form,
                    child: Column(children: [
                      if (application?['status'] == 'Rejected')
                        const Padding(
                            padding: EdgeInsets.only(bottom: 18),
                            child: Text(
                                'Your previous registration was rejected. Review your details before submitting a new application.')),
                      Field('Legal owner name', fields['legal_name']!,
                          required: true, maxLength: 250),
                      Field('Business name', fields['business_name']!,
                          required: true, maxLength: 250),
                      Field('Business address', fields['address']!,
                          required: true, minLength: 5, maxLength: 500),
                      Field('Business mobile number', fields['phone']!,
                          required: true,
                          keyboard: TextInputType.phone,
                          maxLength: 30),
                      Field('Business permit/reference number',
                          fields['permit_reference']!,
                          required: true, maxLength: 100),
                      Field('About your business', fields['description']!,
                          lines: 4,
                          required: true,
                          minLength: 20,
                          maxLength: 2000),
                      const Text(
                          'Do not upload government IDs or sensitive documents. An administrator may contact you for verification.',
                          style: TextStyle(fontSize: 10, color: muted)),
                      const SizedBox(height: 14),
                      if (error != null)
                        Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      PrimaryButton(
                          label: 'Submit business registration',
                          busy: busy,
                          onPressed: () async {
                            if (!form.currentState!.validate()) return;
                            setState(() => busy = true);
                            try {
                              await app.client
                                  .from('business_applications')
                                  .insert({
                                'owner_id': app.user!.id,
                                for (final e in fields.entries)
                                  e.key: e.value.text.trim()
                              });
                              await app.refresh();
                              if (mounted)
                                toast(context,
                                    'Registration submitted for review.');
                            } catch (e) {
                              if (mounted) setState(() => error = errorText(e));
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          }),
                    ]))),
        ]));
  }
}

class OwnerPage extends StatelessWidget {
  const OwnerPage({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final approved = app.role == 'admin' ||
        app.applications.any(
            (a) => a['owner_id'] == app.user?.id && a['status'] == 'Approved');
    final list = app.places
        .where((p) => p['owner_id'] == app.user?.id && p['owner_id'] != null)
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Your businesses')),
        body: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              if (!app.signedIn || !approved)
                EmptyState('Owner profile unavailable',
                    'Business listings require an approved owner application.',
                    action: PrimaryButton(
                        label: 'Open registration',
                        onPressed: () =>
                            openPage(context, const BusinessApplicationPage())))
              else ...[
                const Text(
                    'Add a destination, accommodation, or food spot to PasyalPH.',
                    style: TextStyle(color: muted)),
                const SizedBox(height: 18),
                PrimaryButton(
                    label: 'Add a business listing',
                    icon: Icons.add,
                    onPressed: () => openPage(context, const ListingEditor())),
                SectionTitle('Your listings (${list.length})'),
                if (list.isEmpty)
                  const EmptyState('Your business journey starts here',
                      'New listings appear here while awaiting verification.',
                      icon: Icons.storefront_outlined),
                for (final p in list)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Surface(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(value(p, 'name'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            StatusPill(value(p, 'status'),
                                color: p['status'] == 'Verified'
                                    ? const Color(0xff327d50)
                                    : muted),
                            const SizedBox(height: 8),
                            Text(value(p, 'address'),
                                style: const TextStyle(
                                    fontSize: 11, color: muted)),
                            Row(children: [
                              TextButton(
                                  onPressed: () => openPage(
                                      context, ListingEditor(place: p)),
                                  child: const Text('Edit listing')),
                              TextButton(
                                  onPressed: () =>
                                      openPage(context, PlacePage(place: p)),
                                  child: const Text('Preview'))
                            ])
                          ]))),
              ],
            ])));
  }
}

class ListingEditor extends StatefulWidget {
  const ListingEditor({super.key, this.place});
  final JsonMap? place;
  @override
  State<ListingEditor> createState() => _ListingEditorState();
}

class _ListingEditorState extends State<ListingEditor> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final k in [
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
      k: TextEditingController()
  };
  String category = 'Food';
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final p = widget.place;
    if (p != null) {
      category = value(p, 'category');
      for (final e in fields.entries)
        e.value.text = e.key == 'amenities'
            ? (p[e.key] as List? ?? []).join(', ')
            : value(p, e.key);
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) c.dispose();
    super.dispose();
  }

  Future<void> geocode() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final points = await geocodePH(fields['address']!.text);
      if (points.isEmpty)
        throw Exception('No address found. Enter coordinates manually.');
      if (!mounted) return;
      final p = await showModalBottomSheet<JsonMap>(
          context: context,
          showDragHandle: true,
          builder: (c) => ListView(shrinkWrap: true, children: [
                const ListTile(title: Text('Confirm your business location')),
                for (final p in points)
                  ListTile(
                      title: Text('${p['name']}',
                          style: const TextStyle(fontSize: 12)),
                      onTap: () => Navigator.pop(c, p))
              ]));
      if (p != null && mounted)
        setState(() {
          fields['lat']!.text = '${p['lat']}';
          fields['lng']!.text = '${p['lng']}';
        });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final lat = double.tryParse(fields['lat']!.text),
        lng = double.tryParse(fields['lng']!.text);
    if (lat == null ||
        lng == null ||
        lat < 4.2 ||
        lat > 21.5 ||
        lng < 116 ||
        lng > 127) {
      setState(() =>
          error = 'Locate the address or enter valid Philippine coordinates.');
      return;
    }
    final image = fields['image']!.text.trim();
    if (image.isNotEmpty &&
        !image.startsWith('https://') &&
        !image.startsWith('assets/')) {
      setState(() => error = 'Use an HTTPS image URL or upload a photo.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final app = AppScope.of(context);
    try {
      app.requireUser();
      final data = {
        'name': fields['name']!.text.trim(),
        'description': fields['description']!.text.trim(),
        'address': fields['address']!.text.trim(),
        'category': category,
        'image': image.isEmpty ? 'assets/images/pasyalph-new-logo.jpg' : image,
        'hours': fields['hours']!.text.trim(),
        'contact': fields['contact']!.text.trim(),
        'rates': fields['rates']!.text.trim(),
        'amenities': fields['amenities']!
            .text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .take(20)
            .toList(),
        'lat': lat,
        'lng': lng,
        'status': 'Pending Verification'
      };
      if (widget.place == null) {
        await app.client
            .from('places')
            .insert({...data, 'owner_id': app.user!.id});
      } else {
        await app.client
            .from('places')
            .update(data)
            .eq('id', widget.place!['id']);
      }
      await app.refresh();
      if (mounted) {
        toast(context, 'Listing submitted for verification.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.place == null
              ? 'Add a business listing'
              : 'Edit listing')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'Listings and edits stay hidden from Explore until verified.',
            style: TextStyle(fontSize: 11, color: muted)),
        const SizedBox(height: 18),
        Surface(
            child: Form(
                key: form,
                child: Column(children: [
                  Field('Business name', fields['name']!,
                      required: true, maxLength: 250),
                  DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: categories
                          .skip(1)
                          .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s,
                                  style: const TextStyle(fontSize: 12))))
                          .toList(),
                      onChanged: (v) => setState(() => category = v!)),
                  const SizedBox(height: 14),
                  Field('Description', fields['description']!,
                      lines: 4, required: true, minLength: 20, maxLength: 2000),
                  Field('Full address, city and province', fields['address']!,
                      required: true, minLength: 5, maxLength: 500),
                  OutlinedButton.icon(
                      onPressed: busy ? null : geocode,
                      icon: const Icon(Icons.location_searching, size: 17),
                      label: const Text('Locate address on map')),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                        child: Field('Latitude', fields['lat']!,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true, signed: true))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Field('Longitude', fields['lng']!,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true, signed: true)))
                  ]),
                  Field('Photo URL', fields['image']!,
                      keyboard: TextInputType.url),
                  TextButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              await perform(context, () async {
                                final url =
                                    await uploadImage(AppScope.of(context));
                                if (url != null && mounted)
                                  setState(() => fields['image']!.text = url);
                              });
                              if (mounted) setState(() => busy = false);
                            },
                      icon: const Icon(Icons.upload_outlined, size: 17),
                      label: const Text('Upload listing photo')),
                  Field('Operating hours', fields['hours']!, maxLength: 250),
                  Field('Business phone', fields['contact']!,
                      keyboard: TextInputType.phone, maxLength: 100),
                  Field('Rates', fields['rates']!, maxLength: 500),
                  Field('Amenities, separated by commas', fields['amenities']!,
                      maxLength: 1000),
                  if (error != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  PrimaryButton(
                      label: 'Submit for verification',
                      busy: busy,
                      onPressed: save)
                ])))
      ]));
}
