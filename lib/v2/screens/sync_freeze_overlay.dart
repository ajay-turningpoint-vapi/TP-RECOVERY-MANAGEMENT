import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/screens/maintenance_screen.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/pending_sync_screen.dart';

/// Wraps the whole app (see v3/main_v3.dart's MaterialApp.builder) and, for
/// as long as AppStore.isSyncing is true, blocks every screen behind a
/// full-screen scrim with a real explanation — the daily BUSY sync is
/// rewriting customer/PTP/task data server-side, so any read or write
/// during that window could see (or silently lose) a half-synced state.
/// AbsorbPointer, not just a visual overlay, so no tap/scroll underneath
/// can reach the frozen screen while this is up.
class SyncFreezeOverlay extends StatelessWidget {
  final Widget child;
  const SyncFreezeOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    // The admin-only kill switch — server-enforced (see
    // server/src/middleware/auth.js). Two conditions both matter here:
    // ADMIN is never actually rejected (this now blocks MANAGEMENT too —
    // the switch moved to ADMIN-only), so this never blocks an admin's own
    // screen the instant they flip it on (which would strand them with no
    // way back in to turn it off); and it must only ever apply to the
    // already-logged-in app shell, never the login screen itself —
    // checkMaintenanceStatus() runs before anyone's logged in too
    // (userRole is '' then), and blocking the login FORM would trap an
    // admin who force-closed the app during an active maintenance window
    // with no way to sign back in at all. A non-admin's login attempt
    // still gets rejected with a clear message (see authService.js)
    // without needing a blocking screen here.
    final blockedByMaintenance = store.isLoggedIn && store.maintenanceMode && store.userRole != 'ADMIN';
    if (blockedByMaintenance) {
      // A genuine full screen, not a popup/curtain over the blurred app —
      // same widget LoginScreen shows pre-login, so there is exactly one
      // maintenance UI anywhere in the app.
      return const MaintenanceScreen();
    }
    return Stack(
      children: [
        child,
        // Mount/unmount cleanly so the entrance + exit animations run.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: store.showSyncCurtain
              ? _SyncCurtain(since: store.syncingSince)
              : const SizedBox.shrink(key: ValueKey('sync-idle')),
        ),
        // Non-blocking: the sync FAILED (usually the BUSY source was
        // unreachable). The app is usable on last-known data, but the user
        // must know it may be stale. A plain Positioned child of this Stack
        // (never wrapped in AnimatedSwitcher — a Positioned can't be a
        // transition child).
        if (!store.showSyncCurtain && store.showSyncFailure)
          _SyncFailedBanner(
            message: store.syncFailedMessage ??
                'The last BUSY sync didn’t finish, so customer data may be out of date. '
                    'It runs again automatically — no action needed.',
            isConnection: store.syncFailedIsConnection,
            at: store.syncFailedAt,
            onDismiss: store.dismissSyncFailure,
          ),
        // Device itself has no signal (not a BUSY-sync failure — see
        // AppStore._loadFromCache) and the screen is showing the last
        // locally-cached snapshot instead of a live one. Bottom-anchored so
        // it never collides with the top sync-failure banner above, and
        // non-dismissible — it clears itself the instant a live refresh
        // succeeds (AppStore._refreshAllFromApi clears dataAsOf).
        if (!store.showSyncCurtain && store.isShowingCachedData)
          _CachedDataBanner(asOf: store.dataAsOf!, liftedBy: store.pendingActionCount > 0 ? 44 : 0),
        // A queued offline action is waiting to sync — see AppStore's
        // pending_action_queue.dart. Tappable to the full list; stacks
        // above the cached-data banner when both apply.
        if (!store.showSyncCurtain && store.pendingActionCount > 0) _PendingSyncBanner(count: store.pendingActionCount),
      ],
    );
  }
}

class _PendingSyncBanner extends StatelessWidget {
  final int count;
  const _PendingSyncBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset + 8, left: 10, right: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingSyncScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.sync_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '$count action${count == 1 ? '' : 's'} waiting to sync',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CachedDataBanner extends StatelessWidget {
  final DateTime asOf;
  // Extra bottom padding so this banner stacks above the pending-sync one
  // when both are showing at once, instead of overlapping it.
  final double liftedBy;
  const _CachedDataBanner({required this.asOf, this.liftedBy = 0});

  String _timeLabel() {
    final h = asOf.hour % 12 == 0 ? 12 : asOf.hour % 12;
    final m = asOf.minute.toString().padLeft(2, '0');
    final ampm = asOf.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset + 8 + liftedBy, left: 10, right: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 14, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Offline — showing data from ${_timeLabel()}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-anchored, dismissible strip shown when the most recent BUSY sync
/// finished in a failed / interrupted state. Deliberately does NOT block
/// input — stale data is still better than a frozen app.
class _SyncFailedBanner extends StatelessWidget {
  final String message;
  final bool isConnection;
  final DateTime? at;
  final VoidCallback onDismiss;
  const _SyncFailedBanner({
    required this.message,
    required this.isConnection,
    required this.at,
    required this.onDismiss,
  });

  String _agoLabel() {
    if (at == null) return '';
    final d = DateTime.now().difference(at!);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} hr ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final ago = _agoLabel();
    final topInset = MediaQuery.of(context).padding.top;
    // Anchored to the top, width-bounded (left:0/right:0), and capped so it
    // stays phone-width even when the app is shown inside a wide desktop
    // frame. Deliberately NOT wrapped in anything that needs an Overlay
    // (no Tooltip) — this layer sits above the Navigator.
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: EdgeInsets.only(top: topInset + 8, left: 10, right: 10),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFB91C1C),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.22),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isConnection
                          ? Icons.cloud_off_rounded
                          : Icons.sync_problem_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnection
                                ? "Can't reach BUSY — connection lost"
                                : 'BUSY sync failed',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            message,
                            style: const TextStyle(
                              color: Color(0xFFFFE4E4),
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ago.isNotEmpty
                                ? 'Last attempt $ago · retries on its own'
                                : 'Retries on its own',
                            style: const TextStyle(
                              color: Color(0xFFFCA5A5),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 18),
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const _kNavy = Color(0xFF0B1F3A);
const _kInk = Color(0xFF16233D);
const _kSlate = Color(0xFF64748B);
const _kBlue = Color(0xFF2563EB);
const _kIndigo = Color(0xFF4F46E5);
const _kCyan = Color(0xFF22D3EE);

class _SyncCurtain extends StatefulWidget {
  final DateTime? since;
  const _SyncCurtain({required this.since}) : super(key: const ValueKey('sync-active'));

  @override
  State<_SyncCurtain> createState() => _SyncCurtainState();
}

class _SyncCurtainState extends State<_SyncCurtain> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  // Continuous loop that drives the rotating ring, the orbiting dot,
  // the halo pulse and the shimmering progress bar.
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  late final Animation<double> _scrim =
      CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
  late final Animation<double> _card = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.15, 1.0, curve: Curves.easeOutBack),
  );
  late final Animation<double> _cardFade = CurvedAnimation(
    parent: _enter,
    curve: const Interval(0.15, 0.7, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  String _elapsedLabel() {
    final since = widget.since;
    if (since == null) return 'Started just now';
    final secs = DateTime.now().difference(since).inSeconds;
    if (secs < 60) return 'Started $secs sec ago';
    final mins = secs ~/ 60;
    return 'Started $mins min ${secs % 60} sec ago';
  }

  @override
  Widget build(BuildContext context) {
    // NOT Positioned.fill — this widget is mounted as an AnimatedSwitcher
    // child (wrapped in a FadeTransition), so a Positioned here throws
    // "Incorrect use of ParentDataWidget", which then surfaces as a global
    // "Something went wrong" dialog. SizedBox.expand fills the switcher's
    // internal Stack the same way without needing Stack parent data.
    return SizedBox.expand(
      child: AbsorbPointer(
        absorbing: true,
        child: AnimatedBuilder(
          animation: _enter,
          builder: (context, _) {
            final t = _scrim.value;
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 9 * t, sigmaY: 9 * t),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [
                      _kNavy.withOpacity(0.58 * t),
                      const Color(0xFF020617).withOpacity(0.78 * t),
                    ],
                  ),
                ),
                child: FadeTransition(
                  opacity: _cardFade,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.86, end: 1.0).animate(_card),
                    child: _card_(),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _card_() {
    return Material(
      type: MaterialType.transparency,
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 34),
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.fromLTRB(28, 34, 28, 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.7), width: 1),
        boxShadow: [
          BoxShadow(
            color: _kIndigo.withOpacity(0.28),
            blurRadius: 44,
            spreadRadius: -6,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Spinner(loop: _loop),
          const SizedBox(height: 24),
          const Text(
            'Syncing with BUSY',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 19,
              letterSpacing: -0.2,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Customer balances, PTPs, and tasks are being refreshed from BUSY. '
            'The app stays locked until this finishes so nothing is read or '
            'saved against half-synced data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: _kSlate,
            ),
          ),
          const SizedBox(height: 22),
          _ShimmerBar(loop: _loop),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule_rounded, size: 13, color: _kSlate),
              const SizedBox(width: 5),
              // Rebuilds each loop tick, so the elapsed text stays live.
              AnimatedBuilder(
                animation: _loop,
                builder: (_, __) => Text(
                  _elapsedLabel(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _kSlate,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Runs daily at 12:00 PM · usually done in a few minutes',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
      ),
    );
  }
}

/// Centered icon with a pulsing halo, a sweeping gradient ring and a
/// single dot orbiting the ring.
class _Spinner extends StatelessWidget {
  final AnimationController loop;
  const _Spinner({required this.loop});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: AnimatedBuilder(
        animation: loop,
        builder: (context, _) {
          final v = loop.value;
          final pulse = (math.sin(v * 2 * math.pi) + 1) / 2; // 0..1
          return Stack(
            alignment: Alignment.center,
            children: [
              // Soft breathing halo.
              Container(
                width: 66 + 14 * pulse,
                height: 66 + 14 * pulse,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBlue.withOpacity(0.10 * (1 - pulse) + 0.04),
                ),
              ),
              // Sweeping gradient ring.
              Transform.rotate(
                angle: v * 2 * math.pi,
                child: Container(
                  width: 66,
                  height: 66,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Colors.transparent,
                        _kCyan,
                        _kBlue,
                        _kIndigo,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.35, 0.6, 0.82, 1.0],
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: 55,
                      height: 55,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              // Orbiting dot.
              Transform.rotate(
                angle: -v * 2 * math.pi * 1.6,
                child: Transform.translate(
                  offset: const Offset(0, -33),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kIndigo,
                      boxShadow: [
                        BoxShadow(color: _kIndigo.withOpacity(0.5), blurRadius: 6),
                      ],
                    ),
                  ),
                ),
              ),
              // Center icon, gently counter-rotating.
              Transform.rotate(
                angle: -v * 2 * math.pi * 0.5,
                child: const Icon(Icons.sync_rounded, size: 26, color: _kBlue),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Indeterminate progress bar with a gradient block gliding across a track.
class _ShimmerBar extends StatelessWidget {
  final AnimationController loop;
  const _ShimmerBar({required this.loop});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 5,
        child: LayoutBuilder(
          builder: (context, c) {
            return AnimatedBuilder(
              animation: loop,
              builder: (context, _) {
                final w = c.maxWidth;
                const blockFrac = 0.42;
                final blockW = w * blockFrac;
                // eased ping-pong so it decelerates at each edge
                final p = Curves.easeInOut.transform(
                  (math.sin(loop.value * 2 * math.pi) + 1) / 2,
                );
                final x = (w + blockW) * p - blockW;
                return Stack(
                  children: [
                    Container(color: const Color(0xFFEEF2F7)),
                    Positioned(
                      left: x,
                      top: 0,
                      bottom: 0,
                      width: blockW,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: const LinearGradient(
                            colors: [_kCyan, _kBlue, _kIndigo],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
