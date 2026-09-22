import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart' show InfoCard, SectionLabel, kBg, kNavy, kMuted, kBorder, kBlue, kRed, kGreen, kOrange;
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/loading_button.dart';
import 'package:salesman_mobile/widgets/maintenance_toggle_tile.dart';

/// Shared with manager_profile_screen.dart's header — keeps every
/// role-profile-style header in the app on the same blue identity.
const _kAdminGradient = LinearGradient(colors: [Color(0xFF0052CC), Color(0xFF1E3A8A)], begin: Alignment.topCenter, end: Alignment.bottomCenter);

/// The whole app for the ADMIN role — three fixed bottom-nav tabs (sync
/// health, salesperson password resets, settings/maintenance), mirroring
/// the ReScaffoldV3/ManagerScaffoldV3 shell + IndexedStack pattern. Every
/// capability here is also ADMIN-server-enforced regardless of this UI
/// (see server/src/routes/busySyncAdminRoutes.js / adminRoutes.js /
/// maintenanceRoutes.js).
class AdminScaffoldV3 extends StatefulWidget {
  const AdminScaffoldV3({super.key});

  @override
  State<AdminScaffoldV3> createState() => _AdminScaffoldV3State();
}

class _AdminScaffoldV3State extends State<AdminScaffoldV3> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [
      _AdminSyncTab(),
      _AdminPasswordTab(),
      _AdminSettingsTab(),
    ];
    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _currentIndex, children: pages)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: kBlue,
        unselectedItemColor: const Color(0xFFA0AEC0),
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.sync_rounded), label: 'Sync'),
          BottomNavigationBarItem(icon: Icon(Icons.lock_reset_rounded), label: 'Password'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

void _confirmLogout(BuildContext context, AppStore store) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [Icon(Icons.logout, color: kRed), SizedBox(width: 8), Text('Logout', style: TextStyle(fontWeight: FontWeight.bold))]),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: kMuted))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          onPressed: () {
            Navigator.pop(context);
            store.logout();
          },
          child: const Text('Logout', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

/// A blue identity header shared by all three tabs, with an optional extra
/// row underneath (the Sync tab's stat chips).
Widget _tabHeader(
  BuildContext context,
  AppStore store, {
  required IconData icon,
  required String title,
  required Widget subtitle,
  Widget? extra,
}) {
  return Container(
    decoration: const BoxDecoration(
      gradient: _kAdminGradient,
      borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
    ),
    padding: const EdgeInsets.fromLTRB(18, 16, 10, 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  subtitle,
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.logout, color: Colors.white70), tooltip: 'Logout', onPressed: () => _confirmLogout(context, store)),
          ],
        ),
        if (extra != null) ...[const SizedBox(height: 16), extra],
      ],
    ),
  );
}

/// Tab 1 — BUSY sync health across every branch + manual trigger.
class _AdminSyncTab extends StatefulWidget {
  const _AdminSyncTab();

  @override
  State<_AdminSyncTab> createState() => _AdminSyncTabState();
}

class _AdminSyncTabState extends State<_AdminSyncTab> {
  Map<String, dynamic>? _health;
  bool _loadingHealth = true;
  String? _healthError;
  DateTime? _healthCheckedAt;
  Timer? _pollTimer;
  int _pollTicks = 0;

  // Set only by the company-wide "Run Sync Now" button (never by an
  // individual branch's own button) — lets branch tiles that haven't been
  // reached yet in *this* run show "Queued" instead of silently keeping
  // whatever stale status they had before the run started. Cleared once
  // the run finishes.
  DateTime? _batchTriggeredAt;

  // Safety valve — a genuinely stuck server-side job (or a lost connection
  // mid-poll) must not leave this polling forever in the background.
  static const _maxPollTicks = 300; // 300 * 1s = 5 minutes

  @override
  void initState() {
    super.initState();
    _loadHealth();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHealth() async {
    setState(() {
      _loadingHealth = true;
      _healthError = null;
    });
    try {
      final health = await context.read<AppStore>().fetchBusySyncHealth();
      if (!mounted) return;
      setState(() {
        _health = health;
        _healthCheckedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _healthError = 'Could not load sync health: $e');
    } finally {
      if (mounted) setState(() => _loadingHealth = false);
    }
  }

  /// Keeps re-fetching health every 1s while a sync (company-wide or a
  /// single branch) is in progress, so "Running" / spinners clear on their
  /// own the moment the job finishes — without this, the screen only ever
  /// updated once right after the trigger call and then sat frozen on
  /// "Syncing…" until a manual pull-to-refresh, even though the job itself
  /// had long since finished.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTicks = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _pollTicks++;
      await _loadHealth();
      final stillRunning = (_health?['isRunning'] as bool?) ?? false;
      if (!stillRunning) {
        if (mounted) setState(() => _batchTriggeredAt = null);
      }
      if (!stillRunning || _pollTicks >= _maxPollTicks || !mounted) {
        timer.cancel();
        _pollTimer = null;
      }
    });
  }

  Future<void> _triggerSync(BuildContext context) async {
    final store = context.read<AppStore>();
    final navigator = Navigator.of(context);
    final error = await store.triggerBusySync();
    if (error != null) {
      showAppMessageAfter(navigator, message: error, isError: true);
      return;
    }
    // No confirmation popup on success — the branch tiles below switch to
    // "Queued"/"Running" immediately, which is the feedback.
    setState(() => _batchTriggeredAt = DateTime.now());
    _startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      backgroundColor: kBg,
      body: RefreshIndicator(
        onRefresh: _loadHealth,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _tabHeader(
                context,
                store,
                icon: Icons.admin_panel_settings_rounded,
                title: store.currentUserFullName,
                subtitle: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(20)),
                  child: const Text('System Administrator', style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                extra: Row(
                  children: [
                    Expanded(child: _headerStat(Icons.people_alt_outlined, '${(_health?['totalCustomers'] as int?) ?? '—'}', 'Customers Synced')),
                    const SizedBox(width: 10),
                    Expanded(child: _headerStat(Icons.apartment_outlined, '${(_health?['branches'] as List?)?.length ?? '—'}', 'Branches Live')),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _headerStat(
                        store.maintenanceMode ? Icons.construction_rounded : Icons.check_circle_outline,
                        store.maintenanceMode ? 'ON' : 'Normal',
                        'App Access',
                        accent: store.maintenanceMode ? const Color(0xFFF59E0B) : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SectionLabel('BUSY SYNC HEALTH'),
                  _buildSyncHealthCard(context),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(IconData icon, String value, String label, {Color? accent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: accent ?? Colors.white70),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: accent ?? Colors.white)),
          ),
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.white60, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildSyncHealthCard(BuildContext context) {
    if (_loadingHealth && _health == null) {
      return const InfoCard(children: [
        Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator(strokeWidth: 2.4))),
      ]);
    }
    if (_healthError != null && _health == null) {
      return InfoCard(children: [
        Row(children: [
          const Icon(Icons.cloud_off_rounded, color: kRed, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_healthError!, style: const TextStyle(fontSize: 12.5, color: kRed))),
        ]),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: OutlinedButton(onPressed: _loadHealth, child: const Text('Retry'))),
      ]);
    }

    final health = _health!;
    final isRunning = health['isRunning'] as bool? ?? false;
    final totalCustomers = health['totalCustomers'] as int? ?? 0;
    final connectivity = (health['connectivity'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mssqlConnected = connectivity['mssqlConnected'] as bool? ?? false;
    final mariaDbHealthy = connectivity['mariaDbHealthy'] as bool? ?? false;
    final branches = (health['branches'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    // Which branch the server is processing *right now* — see
    // customerAgeingSync.js's getSyncProgress(). More precise than each
    // branch's own lastRun.status, which only flips to 'running' for the
    // moments that one branch is mid-flight and is easy for a poll to miss
    // entirely on a fast branch.
    final activeBranch = isRunning ? ((health['progress'] as Map?)?['branch'] as String?) : null;
    final allOk = branches.every((b) {
      final s = ((b['lastRun'] as Map?)?['status']) as String?;
      return s == 'success';
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoCard(children: [
          Row(
            children: [
              Expanded(
                child: Row(children: [
                  _connectivityChip('BUSY (MSSQL)', mssqlConnected),
                  const SizedBox(width: 8),
                  _connectivityChip('MariaDB', mariaDbHealthy),
                ]),
              ),
              if (isRunning)
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2, color: kBlue)),
                  SizedBox(width: 6),
                  Text('Syncing…', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kBlue)),
                ])
              else
                Icon(allOk ? Icons.check_circle : Icons.error_outline, size: 18, color: allOk ? kGreen : kRed),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: kBorder)),
          Row(
            children: [
              const Icon(Icons.people_alt_outlined, size: 15, color: kMuted),
              const SizedBox(width: 6),
              Text('$totalCustomers customers across ${branches.length} branch${branches.length == 1 ? '' : 'es'}',
                  style: const TextStyle(fontSize: 12.5, color: kMuted, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_healthCheckedAt != null)
                Text('Checked ${DateFormat('hh:mm a').format(_healthCheckedAt!)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: LoadingElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: isRunning ? null : () => _triggerSync(context),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(isRunning ? Icons.hourglass_top_rounded : Icons.sync_rounded, size: 17),
                  const SizedBox(width: 8),
                  Text(isRunning ? 'Sync in progress…' : 'Run Sync Now', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        ...branches.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BranchHealthTile(
                branch: b,
                anySyncRunning: isRunning,
                activeBranch: activeBranch,
                batchTriggeredAt: _batchTriggeredAt,
                onSynced: _startPolling,
              ),
            )),
      ],
    );
  }

  Widget _connectivityChip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: (ok ? kGreen : kRed).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, size: 11, color: ok ? kGreen : kRed),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 10.5, color: ok ? kGreen : kRed, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _BranchHealthTile extends StatefulWidget {
  final Map<String, dynamic> branch;
  final bool anySyncRunning;
  // The branch the server is actively processing right now (company-wide
  // run only — see getSyncProgress() server-side), or null.
  final String? activeBranch;
  // Set only while a company-wide "Run Sync Now" is in flight — branches
  // this run hasn't reached yet show "Queued" instead of a stale old status.
  final DateTime? batchTriggeredAt;
  final VoidCallback onSynced;
  const _BranchHealthTile({
    required this.branch,
    required this.anySyncRunning,
    required this.activeBranch,
    required this.batchTriggeredAt,
    required this.onSynced,
  });

  @override
  State<_BranchHealthTile> createState() => _BranchHealthTileState();
}

class _BranchHealthTileState extends State<_BranchHealthTile> {
  // Drives the "Running" badge the instant *this* branch's own button is
  // tapped — deterministic, not a race against the next poll tick. Without
  // this, a branch that finishes in under a second (small row count) could
  // go straight from its old status to "OK" without the poll ever once
  // catching it mid-run, making the button look like it did nothing.
  bool _triggering = false;

  Future<void> _syncThisBranch(BuildContext context, String name) async {
    setState(() => _triggering = true);
    final store = context.read<AppStore>();
    final navigator = Navigator.of(context);
    final error = await store.triggerBusySync(branch: name);
    if (error != null) {
      if (mounted) setState(() => _triggering = false);
      showAppMessageAfter(navigator, message: error, isError: true);
      return;
    }
    // No confirmation popup on success — this tile's own badge flips to
    // "Running" immediately (see _triggering above), which is the feedback.
    widget.onSynced();
    // Cleared once the poll confirms the run this branch was part of has
    // actually finished, not right after the trigger call returns — the
    // trigger only confirms the job *started*.
    await _waitForBranchToFinish();
  }

  Future<void> _waitForBranchToFinish() async {
    // widget.anySyncRunning is only as fresh as the parent's *last* poll —
    // right after triggering, that's still the pre-trigger snapshot (which
    // correctly said "nothing running" a moment ago), so checking it right
    // away reads stale data and clears _triggering almost instantly. The
    // parent's poll (started by onSynced -> _startPolling, 1s interval)
    // needs at least one full cycle to fetch a fresh answer — wait longer
    // than that interval before trusting anySyncRunning at all. This is
    // also what makes "Running" visible to a human for fast branches
    // (previously only Turning Point's ~8s run was ever long enough to be
    // caught by a poll — everything else cleared before any poll ran).
    await Future.delayed(const Duration(milliseconds: 1200));
    while (mounted && widget.anySyncRunning) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    if (mounted) setState(() => _triggering = false);
  }

  @override
  Widget build(BuildContext context) {
    final branch = widget.branch;
    final name = branch['branch'] as String? ?? '—';
    final lastRun = (branch['lastRun'] as Map?)?.cast<String, dynamic>();
    final status = lastRun?['status'] as String?;
    // startedAt, not finishedAt — every branch synced in the same run
    // shares one startedAt (see server's customerAgeingSync.js), so this
    // reads identically across branches instead of drifting by however
    // long each branch's own fetch/write happened to take.
    final startedAt = lastRun?['startedAt'] as String?;
    final errorMessage = lastRun?['errorMessage'] as String?;

    // .toLocal() — the server sends UTC ISO strings; every other date in
    // this app converts before formatting (see app_store.dart), this tile
    // was the one spot that didn't, so it displayed raw UTC as if it were
    // local time (off by however far the device's timezone sits from UTC).
    final started = startedAt != null ? DateTime.tryParse(startedAt)?.toLocal() : null;

    final isActiveNow = widget.activeBranch != null && widget.activeBranch == name;
    final isRunningNow = _triggering || isActiveNow || status == 'running';
    // This run hasn't gotten to this branch yet — its last recorded run
    // predates when "Run Sync Now" was tapped, so the OK/error badge it's
    // still showing is left over from a previous run, not this one.
    final isQueued = !isRunningNow &&
        widget.batchTriggeredAt != null &&
        (started == null || started.isBefore(widget.batchTriggeredAt!));

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    if (isRunningNow) {
      statusColor = kBlue;
      statusLabel = 'Running';
      statusIcon = Icons.sync_rounded;
    } else if (isQueued) {
      statusColor = kMuted;
      statusLabel = 'Queued';
      statusIcon = Icons.schedule_rounded;
    } else if (status == null) {
      statusColor = kMuted;
      statusLabel = 'No runs yet';
      statusIcon = Icons.help_outline_rounded;
    } else if (status == 'success') {
      statusColor = kGreen;
      statusLabel = 'OK';
      statusIcon = Icons.check_circle_rounded;
    } else {
      statusColor = kRed;
      statusLabel = status;
      statusIcon = Icons.error_rounded;
    }

    final busy = isRunningNow || widget.anySyncRunning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder)),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.apartment_rounded, size: 16, color: statusColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: kNavy)),
                if (started != null)
                  Text('Last synced ${DateFormat('dd MMM, hh:mm a').format(started)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                if (errorMessage != null && status != 'success')
                  Text(errorMessage, style: const TextStyle(fontSize: 10.5, color: kRed), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(statusIcon, size: 12, color: statusColor),
              const SizedBox(width: 4),
              Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            height: 34,
            child: isRunningNow
                ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
                : IconButton(
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    color: kBlue,
                    tooltip: 'Sync $name',
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(backgroundColor: kBlue.withOpacity(0.08), shape: const CircleBorder()),
                    onPressed: busy ? null : () => _syncThisBranch(context, name),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Tab 2 — reset a salesperson's password. Server refuses any other
/// target role (see server/src/services/adminService.js).
class _AdminPasswordTab extends StatelessWidget {
  const _AdminPasswordTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _tabHeader(
              context,
              store,
              icon: Icons.lock_reset_rounded,
              title: 'Reset Password',
              subtitle: const Text('Force a salesperson onto a new password', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SectionLabel('RESET SALESPERSON PASSWORD'),
                _ResetPasswordCard(salesmen: store.salesmen),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab 3 — account info + sole control of maintenance mode.
class _AdminSettingsTab extends StatelessWidget {
  const _AdminSettingsTab();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _tabHeader(
              context,
              store,
              icon: Icons.settings_rounded,
              title: store.currentUserFullName,
              subtitle: const Text('System Administrator', style: TextStyle(fontSize: 11.5, color: Colors.white70)),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const SectionLabel('ACCOUNT'),
                InfoCard(children: [
                  Row(children: [
                    const Icon(Icons.badge_outlined, size: 16, color: kBlue),
                    const SizedBox(width: 10),
                    const Text('Login ID: ', style: TextStyle(fontSize: 12, color: kMuted)),
                    Expanded(child: Text(store.currentUsername, style: const TextStyle(fontSize: 12, color: kNavy, fontWeight: FontWeight.w600))),
                  ]),
                ]),
                const SizedBox(height: 22),
                const Row(children: [
                  Icon(Icons.warning_amber_rounded, size: 13, color: kOrange),
                  SizedBox(width: 6),
                  Text('DANGER ZONE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kOrange, letterSpacing: 0.4)),
                ]),
                const SizedBox(height: 10),
                const MaintenanceToggleTile(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetPasswordCard extends StatefulWidget {
  final List<Map<String, dynamic>> salesmen;
  const _ResetPasswordCard({required this.salesmen});

  @override
  State<_ResetPasswordCard> createState() => _ResetPasswordCardState();
}

class _ResetPasswordCardState extends State<_ResetPasswordCard> {
  String? _selectedId;
  final _passwordController = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, AppStore store) {
    setState(() => _error = null);
    if (_selectedId == null) {
      setState(() => _error = 'Select a salesperson');
      return;
    }
    if (_passwordController.text.trim().length < 8) {
      setState(() => _error = 'New password must be at least 8 characters');
      return;
    }
    final salesmanName = store.salesmanDisplayName(_selectedId!);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.lock_reset_rounded, color: kOrange),
          SizedBox(width: 8),
          Flexible(child: Text('Reset Password?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        ]),
        content: Text('$salesmanName will be signed out of every device and must sign back in with the new password.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          LoadingElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white),
            onPressed: () async {
              final navigator = Navigator.of(context);
              final newPassword = _passwordController.text.trim();
              final error = await store.resetSalesmanPassword(_selectedId!, newPassword);
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (error != null) {
                showAppMessageAfter(navigator, message: error, isError: true);
              } else {
                _passwordController.clear();
                showAppMessageAfter(navigator, message: "$salesmanName's password has been reset.");
              }
            },
            child: const Text('Reset Password'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return InfoCard(children: [
      DropdownButtonFormField<String>(
        value: _selectedId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Salesperson',
          prefixIcon: Icon(Icons.person_search_outlined, size: 18),
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: widget.salesmen
            .map<DropdownMenuItem<String>>((s) => DropdownMenuItem(
                  value: s['name'] as String,
                  child: Text((s['fullName'] as String?) ?? s['name'] as String, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) => setState(() => _selectedId = v),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        obscureText: _obscure,
        decoration: InputDecoration(
          labelText: 'New Password',
          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: IconButton(
            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.error_outline, size: 13, color: kRed),
          const SizedBox(width: 4),
          Text(_error!, style: const TextStyle(fontSize: 11.5, color: kRed)),
        ]),
      ],
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kOrange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () => _submit(context, store),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_reset_rounded, size: 17),
              SizedBox(width: 8),
              Text('Reset Password', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    ]);
  }
}
