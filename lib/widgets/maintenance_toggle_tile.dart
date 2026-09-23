import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

/// Admin-only kill switch — instantly blocks every other role (including
/// MANAGEMENT) from the whole app (see server/src/middleware/auth.js +
/// AppStore.maintenanceMode / SyncFreezeOverlay's maintenance curtain).
/// Server-enforced regardless of this widget; this is just the one place
/// an admin can actually reach it (see admin_scaffold_v3.dart).
class MaintenanceToggleTile extends StatefulWidget {
  const MaintenanceToggleTile({super.key});

  @override
  State<MaintenanceToggleTile> createState() => _MaintenanceToggleTileState();
}

class _MaintenanceToggleTileState extends State<MaintenanceToggleTile> {
  bool _busy = false;

  Future<void> _apply(BuildContext context, AppStore store, bool enabled) async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    try {
      final error = await store.toggleMaintenanceMode(enabled);
      if (error != null) {
        showAppMessageAfter(navigator, message: error, isError: true);
      } else {
        showAppMessageAfter(navigator,
            message: enabled
                ? 'Maintenance mode is ON — every other user is now blocked from the app.'
                : 'Maintenance mode is OFF — normal access restored.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onChanged(BuildContext context, AppStore store, bool value) {
    if (!value) {
      // Turning it back off is always safe — no confirmation needed.
      _apply(context, store, false);
      return;
    }
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.construction_rounded, color: Color(0xFFF59E0B)),
          SizedBox(width: 8),
          Flexible(child: Text('Enable Maintenance Mode?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
        ]),
        content: const Text(
          'Every salesperson, Recovery Executive, and Manager will be instantly signed out of the app and unable to sign '
          'back in until you turn this off again. Only you will keep access.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _apply(context, store, true);
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final enabled = store.maintenanceMode;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: enabled ? const Color(0xFFF59E0B) : Colors.grey.withValues(alpha: 0.15), width: enabled ? 1.4 : 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.construction_rounded, color: Color(0xFFF59E0B), size: 18),
        ),
        title: const Text('Maintenance Mode', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1B2B48))),
        subtitle: Text(
          enabled ? 'ON — app blocked for everyone else' : 'OFF — app is accessible normally',
          style: TextStyle(fontSize: 11.5, color: enabled ? const Color(0xFFB45309) : const Color(0xFF5A6B87), fontWeight: enabled ? FontWeight.w700 : FontWeight.w500),
        ),
        trailing: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
            : Switch(
                value: enabled,
                activeThumbColor: const Color(0xFFF59E0B),
                onChanged: (v) => _onChanged(context, store, v),
              ),
      ),
    );
  }
}
