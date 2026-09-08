import 'package:flutter/material.dart';

/// Which situation a message is reporting — drives icon, color, and the
/// default title. `error`/`success` existed before as a plain `isError`
/// bool; `warning`/`info`/`syncing` are additive so this one dialog can
/// actually look different for "something's wrong" vs "you need to know
/// this" vs "this is still in progress", instead of every non-error
/// message getting the same green checkmark regardless of what it means.
enum AppMessageType { success, error, warning, info, syncing }

class _MessageStyle {
  final Color accent;
  final Color accentDark;
  final Color accentSoft;
  final IconData icon;
  final String defaultTitle;
  const _MessageStyle(this.accent, this.accentDark, this.accentSoft, this.icon, this.defaultTitle);
}

const Map<AppMessageType, _MessageStyle> _styles = {
  AppMessageType.success: _MessageStyle(
    Color(0xFF16A34A), Color(0xFF15803D), Color(0xFFDCFCE7), Icons.check_circle_rounded, 'Done',
  ),
  AppMessageType.error: _MessageStyle(
    Color(0xFFDC2626), Color(0xFFB91C1C), Color(0xFFFEE2E2), Icons.cancel_rounded, 'Something went wrong',
  ),
  AppMessageType.warning: _MessageStyle(
    Color(0xFFD97706), Color(0xFFB45309), Color(0xFFFEF3C7), Icons.warning_rounded, 'Heads up',
  ),
  AppMessageType.info: _MessageStyle(
    Color(0xFF2563EB), Color(0xFF1D4ED8), Color(0xFFDBEAFE), Icons.info_rounded, 'Note',
  ),
  AppMessageType.syncing: _MessageStyle(
    Color(0xFF7C3AED), Color(0xFF6D28D9), Color(0xFFEDE9FE), Icons.sync_rounded, 'In progress',
  ),
};

/// App-wide replacement for transient SnackBars: a modal [AlertDialog] with a
/// single **OK** button that the user must acknowledge (or, for
/// [AppMessageType.syncing], no button at all — see `showBusy` below).
/// Styling (icon/color/title) is driven by [type]; pass [isError] instead
/// only for old call sites that haven't been migrated to [type] yet — it's
/// just `error`/`success` under the hood.
///
/// Usage — synchronous (button handler with no `await` before it):
/// ```dart
/// showAppMessage(context, message: 'Note added.'); // success
/// showAppMessage(context, message: 'Already pending.', type: AppMessageType.warning);
/// ```
///
/// Usage — after an `await` (context may have been unmounted, or the screen
/// already popped): capture the navigator *before* the gap and hand it to
/// [showAppMessageAfter]; the navigator's own context stays valid for the
/// lifetime of the app, so nothing crosses the async gap at the call site:
/// ```dart
/// final navigator = Navigator.of(context);
/// try {
///   await store.doThing();
///   navigator.pop();
///   showAppMessageAfter(navigator, message: 'Done.');
/// } catch (e) {
///   showAppMessageAfter(navigator, message: 'Could not do thing: $e', type: AppMessageType.error);
/// }
/// ```
Future<void> showAppMessage(
  BuildContext context, {
  required String message,
  bool isError = false,
  AppMessageType? type,
  String? title,
}) {
  if (!context.mounted) return Future<void>.value();
  return _showAppMessageDialog(context, message: message, type: type ?? (isError ? AppMessageType.error : AppMessageType.success), title: title);
}

/// Async-gap-safe variant: pass the [NavigatorState] captured *before* the
/// `await`. Use this whenever the message is shown after awaiting something
/// (or after popping the current screen).
Future<void> showAppMessageAfter(
  NavigatorState navigator, {
  required String message,
  bool isError = false,
  AppMessageType? type,
  String? title,
}) {
  return _showAppMessageDialog(navigator.context, message: message, type: type ?? (isError ? AppMessageType.error : AppMessageType.success), title: title);
}

Future<void> _showAppMessageDialog(
  BuildContext context, {
  required String message,
  required AppMessageType type,
  String? title,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) => _AppMessageDialog(
      message: message,
      type: type,
      title: title ?? _styles[type]!.defaultTitle,
    ),
  );
}

/// The animated card behind [showAppMessage]. Entrance: the card fades +
/// springs up, the icon pops in with an elastic overshoot (a steady spin
/// instead, for [AppMessageType.syncing]), and a soft accent-coloured ring
/// keeps pulsing behind it while the dialog is open.
class _AppMessageDialog extends StatefulWidget {
  final String message;
  final String title;
  final AppMessageType type;

  const _AppMessageDialog({
    required this.message,
    required this.title,
    required this.type,
  });

  @override
  State<_AppMessageDialog> createState() => _AppMessageDialogState();
}

class _AppMessageDialogState extends State<_AppMessageDialog>
    with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat();

  // Only the syncing type spins continuously — every other type's icon
  // just pops in once via _iconScale below.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _enter, curve: const Interval(0.0, 0.5));
  late final Animation<double> _cardScale = Tween<double>(begin: 0.82, end: 1.0)
      .animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutBack));
  late final Animation<double> _iconScale = CurvedAnimation(
      parent: _enter, curve: const Interval(0.25, 1.0, curve: Curves.elasticOut));

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _styles[widget.type]!;
    final accent = style.accent;
    final accentDark = style.accentDark;
    final accentSoft = style.accentSoft;
    final isSyncing = widget.type == AppMessageType.syncing;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _cardScale,
        child: Dialog(
          backgroundColor: Colors.white,
          elevation: 16,
          insetPadding: const EdgeInsets.symmetric(horizontal: 36),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pulsing ring + popped-in (or spinning) icon.
                SizedBox(
                  width: 108,
                  height: 108,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (_, __) {
                          final t = Curves.easeOut.transform(_pulse.value);
                          return Container(
                            width: 84 + 40 * t,
                            height: 84 + 40 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withOpacity(0.22 * (1 - t)),
                            ),
                          );
                        },
                      ),
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [accentSoft, accentSoft.withOpacity(0.55)],
                          ),
                        ),
                        child: isSyncing
                            ? RotationTransition(
                                turns: _spin,
                                child: Icon(style.icon, color: accent, size: 50),
                              )
                            : ScaleTransition(
                                scale: _iconScale,
                                child: Icon(style.icon, color: accent, size: 54),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 21,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.42,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      gradient: LinearGradient(colors: [accent, accentDark]),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Center(
                          child: Text(
                            'OK',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
