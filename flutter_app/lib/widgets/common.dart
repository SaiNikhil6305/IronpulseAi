import 'package:flutter/material.dart';

import '../theme.dart';

/// Bumped whenever data changes so every tab reloads.
final appRefresh = ValueNotifier<int>(0);
void notifyDataChanged() => appRefresh.value++;

class IPCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlight;
  const IPCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: IP.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: highlight ? IP.accent.withOpacity(0.6) : IP.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(
              child: Text(text.toUpperCase(),
                  style: const TextStyle(color: IP.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2))),
          if (trailing != null) trailing!,
        ]),
      );
}

class Muted extends StatelessWidget {
  final String text;
  final double size;
  const Muted(this.text, {super.key, this.size = 14});
  @override
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: IP.muted, fontSize: size));
}

class ProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  const ProgressBar(this.value, {super.key, this.color = IP.accent});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0), minHeight: 8, backgroundColor: IP.surface2, color: color),
      );
}

class StatTile extends StatelessWidget {
  final String label, value;
  final IconData? icon;
  const StatTile(this.label, this.value, {super.key, this.icon});
  @override
  Widget build(BuildContext context) => Expanded(
        child: IPCard(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (icon != null) Icon(icon, size: 18, color: IP.muted),
            if (icon != null) const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Muted(label, size: 12),
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, body;
  const EmptyState({super.key, required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: IP.muted),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Muted(body),
        ]),
      );
}

/// Rebuilds [builder] whenever app data changes.
class Reloading<T> extends StatelessWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const Reloading({super.key, required this.load, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: appRefresh,
        builder: (context, v, _) => FutureBuilder<T>(
          key: ValueKey(v),
          future: load(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Something went wrong: ${snap.error}')));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return builder(context, snap.data as T);
          },
        ),
      );
}
