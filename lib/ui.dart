import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_state.dart';

const ink = Color(0xff073b42),
    cream = Color(0xfffaf9f4),
    muted = Color(0xff77808b),
    accent = Color(0xff479bb7);
ThemeData appTheme(bool dark) {
  final scheme = ColorScheme.fromSeed(
          seedColor: ink, brightness: dark ? Brightness.dark : Brightness.light)
      .copyWith(
          primary: dark ? const Color(0xff9ed8d4) : ink,
          secondary: accent,
          surface: dark ? const Color(0xff1b3035) : cream);
  return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Jakarta',
      scaffoldBackgroundColor: scheme.surface,
      cardColor: dark ? const Color(0xff243a3f) : Colors.white,
      textTheme: TextTheme(
          headlineLarge: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface),
          headlineMedium: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface),
          titleLarge: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 21,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface),
          bodyMedium: const TextStyle(fontSize: 13, height: 1.6)),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: dark ? const Color(0xff243a3f) : Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xffd9e1e3))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xffd9e1e3))),
          hintStyle: const TextStyle(color: muted, fontSize: 12)),
      appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 23,
              color: scheme.onSurface,
              fontWeight: FontWeight.bold)),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
              textStyle: const TextStyle(
                  fontFamily: 'Jakarta',
                  fontSize: 12,
                  fontWeight: FontWeight.w700))));
}

void toast(BuildContext context, String text) {
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

Future<void> perform(BuildContext context, Future<void> Function() action,
    {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) toast(context, success);
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
  }
}

Future<T?> openPage<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
Future<void> openUrl(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    if (!['https', 'http', 'tel', 'mailto'].contains(uri.scheme))
      throw Exception('This link is unavailable.');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
      throw Exception('Could not open this link.');
  } catch (e) {
    if (context.mounted) toast(context, errorText(e));
  }
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(size * .28),
      child: Image.asset('assets/images/pasyalph-new-logo.jpg',
          width: size, height: size, fit: BoxFit.cover));
}

class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, this.size = 36, this.light = false});
  final double size;
  final bool light;
  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(
          text: 'Pasyal',
          style: TextStyle(
              fontFamily: 'Fraunces',
              fontSize: size,
              fontWeight: FontWeight.w800,
              color: light ? Colors.white : ink,
              letterSpacing: -1.2),
          children: const [
            TextSpan(text: 'PH', style: TextStyle(color: Color(0xffefa52e)))
          ]));
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.icon,
      this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: FilledButton(
          onPressed: busy ? null : onPressed,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (busy) ...[
              const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10)
            ] else if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8)
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center))
          ])));
}

class Surface extends StatelessWidget {
  const Surface(
      {super.key, required this.child, this.padding = 16, this.margin = 0});
  final Widget child;
  final double padding, margin;
  @override
  Widget build(BuildContext context) => Container(
      margin: EdgeInsets.symmetric(vertical: margin),
      child: Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          elevation: 0.5,
          shadowColor: Colors.black12,
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: EdgeInsets.all(padding), child: child)));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(fontSize: 10, color: muted))
        ])),
        if (trailing != null) trailing!
      ]));
}

class Field extends StatelessWidget {
  const Field(this.label, this.controller,
      {super.key,
      this.lines = 1,
      this.obscure = false,
      this.required = false,
      this.minLength = 1,
      this.keyboard,
      this.hint,
      this.maxLength,
      this.validator,
      this.readOnly = false});
  final String label;
  final TextEditingController controller;
  final int lines, minLength;
  final int? maxLength;
  final bool obscure, required, readOnly;
  final TextInputType? keyboard;
  final String? hint;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
          controller: controller,
          readOnly: readOnly,
          obscureText: obscure,
          minLines: lines,
          maxLines: obscure ? 1 : lines,
          maxLength: maxLength,
          keyboardType: keyboard,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
              labelText: label, hintText: hint, alignLabelWithHint: lines > 1),
          validator: validator ??
              (v) {
                if (required && (v ?? '').trim().length < minLength)
                  return 'Enter ${minLength > 1 ? 'at least $minLength characters' : label}.';
                return null;
              }));
}

class PlacePhoto extends StatelessWidget {
  const PlacePhoto(this.src,
      {super.key, this.height = 165, this.width = double.infinity});
  final String src;
  final double height, width;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => Container(
        height: height,
        width: width,
        color: const Color(0xffdeebe6),
        child: const Icon(Icons.landscape_outlined, size: 42, color: ink));
    if (src.startsWith('assets/'))
      return Image.asset(src,
          height: height,
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (_, e, s) => fallback());
    if (src.startsWith('https://'))
      return Image.network(src,
          height: height,
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (_, e, s) => fallback());
    return fallback();
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color = ink});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(30)),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700)));
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.message,
      {super.key, this.icon = Icons.travel_explore, this.action});
  final String title, message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 46, color: accent),
        const SizedBox(height: 15),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted, fontSize: 12)),
        if (action != null) ...[const SizedBox(height: 20), action!]
      ]));
}

Future<bool> confirm(BuildContext context, String title, String body,
        {String action = 'Continue'}) async =>
    await showDialog<bool>(
        context: context,
        builder: (c) =>
            AlertDialog(title: Text(title), content: Text(body), actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(c, true), child: Text(action))
            ])) ??
    false;
