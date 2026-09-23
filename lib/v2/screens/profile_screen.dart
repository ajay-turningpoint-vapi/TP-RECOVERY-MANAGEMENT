import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/widgets/recovery_score_breakdown.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/call_helper.dart';

const String _supportPhoneNumber = '7227909850';

// Real per-user photos, added one at a time as they're provided — keyed by
// login username (lowercase). Everyone not in this map keeps the existing
// initials-avatar header; there's no upload/storage feature behind this,
// just bundled assets swapped in per username. A few names (e.g. Kanaiya,
// Sagar) are the same real person's photo reused across their multiple
// branch logins (kanaiya.claart + kanaiya, sagar.claart + sagar) — bare
// first-name matches only; a username with a phone number baked into the
// full name (e.g. "NILESH FURIA(...)", "VIRAG(...) -PORSHIVE") is a
// disambiguated, presumably different person and gets its own entry only.
const Map<String, String> _profilePhotos = {
  'gopal': 'assets/images/gopal_profile.jpg',
  'bharat': 'assets/images/bharat.jpg',
  'bharat.fpnavsari': 'assets/images/bharat_fpnavsari.jpg',
  'chandu': 'assets/images/chandu.jpg',
  'chetan': 'assets/images/chetan.jpg',
  'dhiraj': 'assets/images/dhiraj.jpg',
  'durgesh.fpvapi': 'assets/images/durgesh.jpg',
  'gautam': 'assets/images/gautam.jpg',
  'jagdish': 'assets/images/jagdish.jpg',
  'jignesh': 'assets/images/jignesh.jpg',
  'jitendra': 'assets/images/jitendra.jpg',
  'kamlesh.fpvapi': 'assets/images/kamlesh.jpg',
  'kanaiya.claart': 'assets/images/kanaiya.jpg',
  'kanaiya': 'assets/images/kanaiya.jpg',
  'mahipal.fpnavsari': 'assets/images/mahipal.jpg',
  'mangal.fpvapi': 'assets/images/mangal.jpg',
  'narpat': 'assets/images/narpat.jpg',
  'nilesh.furia': 'assets/images/nilesh_furia.jpg',
  'patrakar': 'assets/images/patrakar.jpg',
  'priyanshu.fpvapi': 'assets/images/priyanshu.jpg',
  'rakesh.fpvapi': 'assets/images/rakesh.jpg',
  'ravi': 'assets/images/ravi.jpg',
  'sagar.claart': 'assets/images/sagar.jpg',
  'sagar': 'assets/images/sagar.jpg',
  'sumit.fpvapi': 'assets/images/sumit.jpg',
  'virag.fpvapi': 'assets/images/virag.jpg',
};

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final isRE = store.userRole == 'RECOVERY_EXECUTIVE';
    // Real identity from the logged-in session — no fabricated persona.
    // Matches manager_profile_screen.dart's approach.
    final name = store.currentUserFullName;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .map((p) => p.isEmpty ? '' : p[0])
        .take(2)
        .join()
        .toUpperCase();
    final role = isRE ? 'Recovery Executive (RE)' : 'Salesperson';
    final portfolioSize = store.myCustomers.length;
    final photoAsset = _profilePhotos[store.currentUsername.toLowerCase()];

    final recoveryScore =
        isRE ? null : store.myRecoveryScoreComponents?['total']?.toInt();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0052CC),
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(isRE ? 'RE Profile' : 'My Profile',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white)),
      ),
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: photoAsset != null
                ? _PhotoHeader(
                    photoAsset: photoAsset,
                    name: name,
                    role: role,
                    isRE: isRE,
                    portfolioSize: portfolioSize,
                  )
                : Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0052CC), Color(0xFF1E3A8A)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            CircleAvatar(
                              radius: 46,
                              backgroundColor: Colors.white,
                              child: CircleAvatar(
                                radius: 43,
                                backgroundColor: const Color(0xFFE3F2FD),
                                child: Text(initials,
                                    style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0052CC))),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.check,
                                  size: 10, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(name,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(role,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white70)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                              isRE
                                  ? 'Company-wide  ·  $portfolioSize Customers'
                                  : '$portfolioSize Customers in portfolio',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 20)),

          // ── Account Details & Settings ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Recovery Score (salesperson only) ──────────────────────
                  if (recoveryScore != null) ...[
                    const _SectionTitle(title: 'Recovery Performance'),
                    const SizedBox(height: 12),
                    _RecoveryScoreCard(
                      score: recoveryScore,
                      onTap: () => showRecoveryScoreBreakdown(context, store),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Quick Info ───────────────────────────────────────────
                  // Real fields only — no fabricated contact/territory/
                  // reporting-line data (this used to show a fixed fake
                  // persona regardless of who actually logged in).
                  const _SectionTitle(title: 'Account Details'),
                  const SizedBox(height: 12),
                  _InfoTile(
                      icon: Icons.badge_outlined,
                      label: 'Login ID',
                      value: store.currentUsername),
                  _InfoTile(
                      icon: Icons.work_outline, label: 'Role', value: role),

                  const SizedBox(height: 20),

                  // ── Actions ───────────────────────────────────────────────
                  const _SectionTitle(title: 'Settings'),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFF8E24AA),
                    iconBg: const Color(0xFFF3E5F5),
                    label: 'Change Password',
                    onTap: () => _showChangePassword(context, store),
                  ),
                  _ActionTile(
                    icon: Icons.help_outline,
                    iconColor: const Color(0xFFF57C00),
                    iconBg: const Color(0xFFFFF3E0),
                    label: 'Help & Support',
                    onTap: () => contactActions(context, _supportPhoneNumber),
                  ),
                  const SizedBox(height: 8),
                  _ActionTile(
                    icon: Icons.logout,
                    iconColor: const Color(0xFFE53935),
                    iconBg: const Color(0xFFFFEBEE),
                    label: 'Logout',
                    labelColor: const Color(0xFFE53935),
                    onTap: () => _confirmLogout(context, store),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePassword(BuildContext context, AppStore store) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ChangePasswordSheet(store: store),
    );
  }

  void _confirmLogout(BuildContext context, AppStore store) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xFFE53935)),
            SizedBox(width: 8),
            Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF5A6B87))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
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
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

/// Full-bleed cover-photo header for a user in [_profilePhotos] — the
/// actual photo fills the entire area the plain gradient header used to
/// occupy, with a bottom scrim so the name/role/chip stay readable over
/// whatever the photo looks like underneath.
class _PhotoHeader extends StatelessWidget {
  final String photoAsset;
  final String name;
  final String role;
  final bool isRE;
  final int portfolioSize;
  const _PhotoHeader({
    required this.photoAsset,
    required this.name,
    required this.role,
    required this.isRE,
    required this.portfolioSize,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
      child: SizedBox(
        height: 380,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(photoAsset,
                fit: BoxFit.cover, alignment: Alignment.topCenter),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Color(0xCC0B1B3A)
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black45, blurRadius: 6)
                                ])),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.check,
                            size: 9, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(role,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                        isRE
                            ? 'Company-wide  ·  $portfolioSize Customers'
                            : '$portfolioSize Customers in portfolio',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Color(0xFF1B2B48)),
      );
}

String _scoreBand(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 60) return 'Good';
  if (score >= 40) return 'Average';
  if (score >= 20) return 'Below Average';
  return 'Poor';
}

Color _scoreBandColor(String band) {
  switch (band) {
    case 'Excellent':
      return const Color(0xFF16A34A);
    case 'Good':
      return const Color(0xFF0052CC);
    case 'Average':
      return const Color(0xFFF57C00);
    case 'Below Average':
      return const Color(0xFFEA580C);
    default:
      return const Color(0xFFE53935);
  }
}

class _RecoveryScoreCard extends StatelessWidget {
  final int score;
  final VoidCallback onTap;

  const _RecoveryScoreCard({required this.score, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final band = _scoreBand(score);
    final color = _scoreBandColor(band);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.12), shape: BoxShape.circle),
              child: Text('$score%',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900, color: color)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recovery Score',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF1B2B48))),
                  const SizedBox(height: 3),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(band,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                  const SizedBox(height: 4),
                  const Text('Tap to see what makes up your score',
                      style:
                          TextStyle(fontSize: 10.5, color: Color(0xFF5A6B87))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA0AEC0)),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF0052CC)),
            const SizedBox(width: 12),
            Text('$label: ',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1B2B48),
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    this.labelColor = const Color(0xFF1B2B48),
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        // A newer Flutter enforces that ListTile needs a real Material
        // ancestor for its background/ink splash to render — without this,
        // it throws "ListTile background color or ink splashes may be
        // invisible" (previously just a silent debug warning, now a real
        // uncaught exception that surfaced the global error dialog).
        child: Material(
          type: MaterialType.transparency,
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            title: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: labelColor)),
            trailing: const Icon(Icons.arrow_forward_ios,
                size: 13, color: Color(0xFFA0AEC0)),
            onTap: onTap,
          ),
        ),
      );
}

// ── Change Password bottom sheet ─────────────────────────────────────────────

class _ChangePasswordSheet extends StatefulWidget {
  final AppStore store;
  const _ChangePasswordSheet({required this.store});

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _showNext = false;
  bool _showConfirm = false;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_next.text.isEmpty || _confirm.text.isEmpty) {
      return 'Please fill in both fields.';
    }
    if (_next.text.length < 8) {
      return 'New password must be at least 8 characters.';
    }
    if (_next.text != _confirm.text) {
      return 'New password and confirmation do not match.';
    }
    return null;
  }

  Future<void> _submit() async {
    final localError = _validate();
    if (localError != null) {
      setState(() => _error = localError);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final result = await widget.store.changePassword(_next.text);
    if (!mounted) return;
    if (result == null) {
      navigator.pop();
      showAppMessageAfter(navigator,
          message: 'Your password has been updated.');
      return;
    }
    setState(() {
      _submitting = false;
      _error = result;
    });
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required bool obscured,
    required VoidCallback onToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5A6B87))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscured,
          enabled: !_submitting,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF0F4F8),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
            suffixIcon: IconButton(
              icon: Icon(obscured ? Icons.visibility_off : Icons.visibility,
                  size: 18, color: const Color(0xFF5A6B87)),
              onPressed: onToggle,
            ),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            const Text('Change Password',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF1B2B48))),
            const SizedBox(height: 4),
            const Text('Choose a new password for your account.',
                style: TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
            const SizedBox(height: 18),
            _field(
              label: 'New Password',
              controller: _next,
              obscured: !_showNext,
              onToggle: () => setState(() => _showNext = !_showNext),
            ),
            _field(
              label: 'Confirm New Password',
              controller: _confirm,
              obscured: !_showConfirm,
              onToggle: () => setState(() => _showConfirm = !_showConfirm),
            ),
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_error!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFC62828),
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 14),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0052CC),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Update Password',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
