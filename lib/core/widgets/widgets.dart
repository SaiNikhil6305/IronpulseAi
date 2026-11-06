import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(Gaps.lg), this.onTap, this.color,
      this.borderColor});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Gaps.radius),
        side: BorderSide(color: borderColor ?? AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction, this.subtitle});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Gaps.xl, bottom: Gaps.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: AppColors.textMuted)),
              if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.caption, this.accent = false});
  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(Gaps.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: accent ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 6),
          ],
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
        ]),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: accent ? AppColors.accent : AppColors.text)),
        ),
        if (caption != null) ...[
          const SizedBox(height: 2),
          Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(Gaps.lg),
          decoration: const BoxDecoration(color: AppColors.accentMuted, shape: BoxShape.circle),
          child: Icon(icon, color: AppColors.accent, size: 32),
        ),
        const SizedBox(height: Gaps.lg),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        if (message != null) ...[
          const SizedBox(height: Gaps.sm),
          Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
        ],
        if (action != null) ...[
          const SizedBox(height: Gaps.lg),
          FilledButton(onPressed: onAction, child: Text(action!)),
        ],
      ]),
    );
  }
}

/// Renders an AsyncValue, keeping stale data visible while reloading.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.value as T);
    if (value.hasError) {
      return Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: Text('Could not load: ${value.error}', style: const TextStyle(color: AppColors.error)),
      );
    }
    return loading ?? const Center(child: Padding(padding: EdgeInsets.all(Gaps.xl), child: CircularProgressIndicator()));
  }
}

class LoadingButton extends StatelessWidget {
  const LoadingButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon,
      this.outlined = false});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ]);
    final onTap = loading ? null : onPressed;
    return SizedBox(
      width: double.infinity,
      child: outlined ? OutlinedButton(onPressed: onTap, child: child) : FilledButton(onPressed: onTap, child: child),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 8, this.color});
  final double value;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1).toDouble(),
        minHeight: height,
        color: color ?? AppColors.accent,
        backgroundColor: AppColors.surfaceHigh,
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.textMuted, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
      ]),
    );
  }
}

/// Numeric text field with a decimal keyboard and comma support.
class NumberField extends StatelessWidget {
  const NumberField({super.key, required this.controller, required this.label, this.suffix, this.validator,
      this.integer = false, this.autofocus = false, this.onChanged, this.textInputAction});
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final String? Function(String?)? validator;
  final bool integer;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(integer ? r'[0-9]' : r'[0-9.,]'))],
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: validator,
      onChanged: onChanged,
      textInputAction: textInputAction ?? TextInputAction.next,
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      action: action,
      backgroundColor: error ? const Color(0xFF3A1416) : null,
    ));
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String confirm = 'Confirm', bool destructive = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: destructive ? AppColors.error : AppColors.accent),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.size = 22});
  final double size;
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.monitor_heart_rounded, color: AppColors.accent, size: size + 4),
      const SizedBox(width: 6),
      Text.rich(TextSpan(children: [
        TextSpan(text: 'IRON', style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: 1)),
        TextSpan(
            text: 'PULSE',
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: 1, color: AppColors.accent)),
      ])),
    ]);
  }
}
