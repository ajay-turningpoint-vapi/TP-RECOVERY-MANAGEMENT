import 'package:flutter/material.dart';

/// Drop-in replacement for [ElevatedButton] that manages its own busy state
/// around an async [onPressed] — shows a small spinner in place of [child]
/// and refuses a second tap while the action is in flight.
///
/// Without this, a slow network call (or, now that the app has an offline
/// write queue, a slow local SQLite read/write) leaves a submit button
/// looking exactly like a dead/frozen one — nothing visibly happens between
/// the tap and the result, so an impatient user taps again and risks a
/// duplicate submission, or assumes the app hung. This is the same
/// busy-bool-plus-spinner pattern DisputeAssignView already hand-rolled for
/// its one "Confirm Approval & Assign" button; pulled out here so every
/// other submit button in the app gets it as a straight drop-in rather than
/// re-deriving the same StatefulWidget boilerplate at each call site.
class LoadingElevatedButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;
  const LoadingElevatedButton({super.key, required this.onPressed, required this.child, this.style});

  @override
  State<LoadingElevatedButton> createState() => _LoadingElevatedButtonState();
}

class _LoadingElevatedButtonState extends State<LoadingElevatedButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = ElevatedButtonTheme.of(context).style;
    final fg = widget.style?.foregroundColor?.resolve({}) ?? theme?.foregroundColor?.resolve({}) ?? Colors.white;
    return ElevatedButton(
      style: widget.style,
      onPressed: _busy || widget.onPressed == null ? null : _handlePress,
      child: _busy
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
          : widget.child,
    );
  }

  Future<void> _handlePress() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Same idea as [LoadingElevatedButton], for [OutlinedButton] call sites
/// (used throughout for the secondary/destructive action in a button row —
/// Reject, Cancel-and-decline, etc.).
class LoadingOutlinedButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;
  const LoadingOutlinedButton({super.key, required this.onPressed, required this.child, this.style});

  @override
  State<LoadingOutlinedButton> createState() => _LoadingOutlinedButtonState();
}

class _LoadingOutlinedButtonState extends State<LoadingOutlinedButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = OutlinedButtonTheme.of(context).style;
    final fg = widget.style?.foregroundColor?.resolve({}) ?? theme?.foregroundColor?.resolve({}) ?? Theme.of(context).colorScheme.primary;
    return OutlinedButton(
      style: widget.style,
      onPressed: _busy || widget.onPressed == null ? null : _handlePress,
      child: _busy
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: fg))
          : widget.child,
    );
  }

  Future<void> _handlePress() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Same idea, for a bare [TextButton] (used for lower-emphasis actions —
/// "Discard", dialog confirmations, etc.).
class LoadingTextButton extends StatefulWidget {
  final Future<void> Function()? onPressed;
  final Widget child;
  final ButtonStyle? style;
  const LoadingTextButton({super.key, required this.onPressed, required this.child, this.style});

  @override
  State<LoadingTextButton> createState() => _LoadingTextButtonState();
}

class _LoadingTextButtonState extends State<LoadingTextButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = TextButtonTheme.of(context).style;
    final fg = widget.style?.foregroundColor?.resolve({}) ?? theme?.foregroundColor?.resolve({}) ?? Theme.of(context).colorScheme.primary;
    return TextButton(
      style: widget.style,
      onPressed: _busy || widget.onPressed == null ? null : _handlePress,
      child: _busy
          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
          : widget.child,
    );
  }

  Future<void> _handlePress() async {
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
