import 'package:flutter/material.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';

/// Compact global branch selector. Bound to [AppStore.branchFilter] so it
/// reads and writes the one app-wide scope every RE/Manager screen, card
/// and count derives from. Renders nothing for a Salesperson, or when
/// there's only a single branch to choose from.
class BranchFilterChip extends StatelessWidget {
  final AppStore store;
  final bool dark;
  const BranchFilterChip({super.key, required this.store, this.dark = false});

  @override
  Widget build(BuildContext context) {
    if (!store.canFilterByBranch) return const SizedBox.shrink();
    final options = store.branchOptions;
    if (options.length <= 2) return const SizedBox.shrink(); // only one real branch

    final fg = dark ? Colors.white : const Color(0xFF64748B);
    final bg = dark ? Colors.white.withValues(alpha: 0.14) : Colors.white;
    final border = dark ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: options.contains(store.branchFilter) ? store.branchFilter : AppStore.kAllBranches,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 15, color: fg),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
          dropdownColor: dark ? const Color(0xFF1B2B48) : Colors.white,
          items: options
              .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text(b, style: TextStyle(fontSize: 12, color: dark ? Colors.white : const Color(0xFF16233D))),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) store.setBranchFilter(v);
          },
        ),
      ),
    );
  }
}
