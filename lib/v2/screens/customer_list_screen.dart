import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/models/customer.dart';
import 'package:salesman_mobile/v2/screens/customer_360_screen.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:intl/intl.dart';

class CustomerListScreen extends StatefulWidget {
  final String title;
  final List<Customer> customers;

  /// Optional per-customer amount to spotlight on each row (e.g. the PTP
  /// amount the salesman promised is due today), shown above the standing
  /// OUTSTANDING figure. Keyed by customer id.
  final Map<String, double>? highlightAmountByCustomerId;
  final String highlightAmountLabel;

  /// When true, every row shows the customer's next action ("Action: …"),
  /// regardless of BUSY-vs-RMS origin — used by the "Today's Recovery"
  /// drill-down so the salesman sees what to do per customer.
  final bool showNextAction;

  /// "Total Overdue" drill-down mode: each row shows the overdue amount
  /// alongside the standing outstanding figure, and the filter panel is
  /// swapped from the category chips for two sort controls (Customer Name
  /// / Amount, each Ascending or Descending — default Name Ascending).
  final bool overdueView;

  /// Same panel treatment as [overdueView] — the category chips are
  /// swapped for the two sort controls (Customer Name / Amount, each
  /// Ascending or Descending) — except "Amount" sorts by the standing
  /// outstanding figure rather than the overdue amount. Used by the
  /// Total Outstanding, Today's Recovery, PTP Due Today, Broken PTP,
  /// Management Instructions, Physical Visits, Due Customers and
  /// My Customers lists.
  final bool sortControlsView;

  /// "Today's Recovery" drill-down mode: customers already worked today
  /// (state == 'Waiting / Monitoring') stay in the list, marked DONE with
  /// their recorded outcome and an "Edit Outcome" button (RE-approved).
  final bool todaysRecoveryView;

  const CustomerListScreen({
    super.key,
    required this.title,
    required this.customers,
    this.highlightAmountByCustomerId,
    this.highlightAmountLabel = 'AMOUNT DUE',
    this.showNextAction = false,
    this.overdueView = false,
    this.sortControlsView = false,
    this.todaysRecoveryView = false,
  });

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  
  // Filters
  String _selectedOutstanding = 'All'; // 'All', '>10L', '5-10L', '<5L'
  String _selectedEscalation = 'All';  // 'All', 'L1', 'L2', 'L3'
  String _selectedState = 'All';       // 'All', 'RE Control', 'RE Supervision', 'Agent Led'

  // Sort controls (overdueView / sortControlsView). Default: Customer Name, Ascending.
  String _sortField = 'Customer Name'; // 'Customer Name' | 'Amount'
  String _sortDir = 'Ascending';       // 'Ascending' | 'Descending'

  bool _isFilterExpanded = false;

  /// Both drill-downs that replace the category chips with the two
  /// Customer Name / Amount sort controls.
  bool get _usesSortControls => widget.overdueView || widget.sortControlsView;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _getBadgeColor(String priority) {
    if (priority == 'High') return const Color(0xFFE53935);
    if (priority == 'Medium') return const Color(0xFFF57C00);
    return const Color(0xFF388E3C);
  }

  Color _getBadgeBgColor(String priority) {
    if (priority == 'High') return const Color(0xFFFFEBEE);
    if (priority == 'Medium') return const Color(0xFFFFF3E0);
    return const Color(0xFFE8F5E9);
  }

  String _getPriority(double due) {
    if (due >= 100000) return 'High';
    if (due >= 50000) return 'Medium';
    return 'Low';
  }

  Color _getAvatarBg(int index) {
    final colors = [
      const Color(0xFFE3F2FD),
      const Color(0xFFE0F2F1),
      const Color(0xFFF3E5F5),
      const Color(0xFFFCE4EC),
      const Color(0xFFFFF3E0)
    ];
    return colors[index % colors.length];
  }

  Color _getAvatarText(int index) {
    final colors = [
      const Color(0xFF1565C0),
      const Color(0xFF00695C),
      const Color(0xFF6A1B9A),
      const Color(0xFFAD1457),
      const Color(0xFFEF6C00)
    ];
    return colors[index % colors.length];
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 2).toUpperCase();
  }

  // Was deriving a fake escalation level from currentRecoveryState string
  // matching ('RE Supervision' never actually occurs as a real state value
  // anywhere in the app, so the 'L2' branch was dead code, and 'L3' fired
  // for ANY reason the state was 'RE Control', including a manual RE
  // Take-Control with no real escalation at all) — now reads the real,
  // canonical field the rest of the app (including recovery-priority
  // sorting) actually uses.
  String _getEscalationLevel(Customer c) => c.escalationLevel == 'none' ? 'L1' : c.escalationLevel;

  List<Customer> _getFilteredCustomers() {
    final filtered = widget.customers.where((c) {
      // 1. Search Query filter (Name, GSTIN, Area) — c.gstNo/c.address are
      // real BUSY-sourced fields; this used to match against a fabricated
      // GSTIN derived from the customer id and a hardcoded 'Mumbai', so
      // searching by a real GST number or area never actually worked.
      final q = _searchQuery.toLowerCase();
      final matchesSearch = c.name.toLowerCase().contains(q) ||
          c.id.toLowerCase().contains(q) ||
          (c.gstNo?.toLowerCase().contains(q) ?? false) ||
          (c.address?.toLowerCase().contains(q) ?? false);
      if (!matchesSearch) return false;

      // The category filters (Outstanding / Escalation / Recovery State) are
      // hidden when the sort controls are shown — skip them so they can't
      // silently exclude rows.
      if (!_usesSortControls) {
        // 2. Outstanding Threshold filter
        if (_selectedOutstanding == '>10L' && c.totalOutstanding < 1000000) return false;
        if (_selectedOutstanding == '5-10L' && (c.totalOutstanding < 500000 || c.totalOutstanding >= 1000000)) return false;
        if (_selectedOutstanding == '<5L' && c.totalOutstanding >= 500000) return false;

        // 3. Escalation Level filter
        final esc = _getEscalationLevel(c);
        if (_selectedEscalation != 'All' && esc != _selectedEscalation) return false;

        // 4. Recovery State filter
        if (_selectedState != 'All' && c.currentRecoveryState != _selectedState) return false;
      }

      return true;
    }).toList();

    if (_usesSortControls) {
      // Explicit sort by the chosen field/direction. "Amount" is the
      // overdue amount (totalDue) in overdueView, and the standing
      // outstanding figure in sortControlsView.
      final asc = _sortDir == 'Ascending';
      filtered.sort((a, b) {
        final int cmp = _sortField == 'Amount'
            ? (widget.sortControlsView
                    ? a.totalOutstanding.compareTo(b.totalOutstanding)
                    : a.totalDue.compareTo(b.totalDue))
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return asc ? cmp : -cmp;
      });
      return filtered;
    }

    // Already arrives most-urgent-first — the server sorts by real
    // recovery priority (see AppStore.compareByRecoveryPriority's doc
    // comment), and filtering above preserves that order.
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredCustomers();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
        backgroundColor: const Color(0xFF0052CC),
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(_isFilterExpanded ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () {
              setState(() {
                _isFilterExpanded = !_isFilterExpanded;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter Panel
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F4F8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, color: Color(0xFF0052CC)),
                            hintText: 'Search Name, GSTIN, Area...',
                            hintStyle: TextStyle(color: Color(0xFFA0AEC0), fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isFilterExpanded) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFE6EBF1)),
                  const SizedBox(height: 14),

                  if (_usesSortControls) ...[
                    // Two independent sort choices: the field, then the
                    // direction. Default is Customer Name, Ascending.
                    _buildSegmentGroup(
                      label: 'Sort by',
                      options: const ['Customer Name', 'Amount'],
                      selected: _sortField,
                      onSelected: (val) => setState(() => _sortField = val),
                    ),
                    const SizedBox(height: 12),
                    _buildSegmentGroup(
                      label: 'Order',
                      options: const ['Ascending', 'Descending'],
                      icons: const [Icons.arrow_upward, Icons.arrow_downward],
                      selected: _sortDir,
                      onSelected: (val) => setState(() => _sortDir = val),
                    ),
                  ] else ...[
                    // Filter groups
                    _buildFilterRow(
                      label: 'Outstanding',
                      options: ['All', '>10L', '5-10L', '<5L'],
                      selectedValue: _selectedOutstanding,
                      onSelected: (val) => setState(() => _selectedOutstanding = val),
                    ),
                    const SizedBox(height: 12),
                    _buildFilterRow(
                      label: 'Escalation',
                      options: ['All', 'L1', 'L2', 'L3', 'L4'],
                      selectedValue: _selectedEscalation,
                      onSelected: (val) => setState(() => _selectedEscalation = val),
                    ),
                    const SizedBox(height: 12),
                    _buildFilterRow(
                      label: 'Recovery State',
                      options: ['All', 'RE Control', 'RE Supervision', 'Agent Led'],
                      selectedValue: _selectedState,
                      onSelected: (val) => setState(() => _selectedState = val),
                    ),
                  ],
                ],
              ],
            ),
          ),
          
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No matching customers found.', style: TextStyle(color: Color(0xFF5A6B87))))
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final c = filtered[i];
                      final priority = _getPriority(c.totalDue);
                      final avatarBg = _getAvatarBg(i);
                      final avatarText = _getAvatarText(i);
                      final store = ctx.watch<AppStore>();
                      // "Done" greys the row and swaps in "Edit Recorded
                      // Outcome" — real, server-persisted state, not an
                      // in-memory per-session flag (which used to reset on
                      // every app restart and show a stale/inconsistent
                      // count). A No Answer locks Record Outcome on the
                      // customer screen regardless of when it was recorded
                      // (Customer360Screen's `isLocked`); a genuinely
                      // resolved outcome (state == 'Waiting / Monitoring')
                      // only counts as "done" if that resolution happened
                      // today, per store.recoveryDoneTodayCustomerIds — the
                      // real audit trail, grounded the same way the
                      // dashboard's done count is. NOT customer.updatedAt:
                      // the daily BUSY sync bumps that for the whole
                      // portfolio regardless of activity, which used to
                      // grey out nearly every resolved customer right after
                      // that sync ran, whether or not they were actually
                      // touched today.
                      // A still-actionable non-resolving outcome that ISN'T
                      // a No Answer (Follow-up) still ticks the dashboard's
                      // done count (see reportService.getDashboard's
                      // myRecoveryDoneTodayCount) but must not grey out
                      // here: Record Outcome stays directly enabled for
                      // those on the customer screen, with no "Edit
                      // Recorded Outcome" step to go through.
                      final isDone = widget.todaysRecoveryView &&
                          (c.isPendingNoAnswerEdit ||
                              (c.currentRecoveryState == 'Waiting / Monitoring' && store.recoveryDoneTodayCustomerIds.contains(c.id)));
                      final editPending = isDone && store.hasPendingOutcomeEdit(c.id);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 0,
                        color: isDone ? const Color(0xFFF1F3F5) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.withOpacity(0.15)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => Customer360Screen(customer: c)));
                          },
                          child: Builder(builder: (_) {
                            final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
                            final highlight = widget.highlightAmountByCustomerId?[c.id];
                            return Opacity(
                              opacity: isDone ? 0.55 : 1.0,
                              child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: avatarBg,
                                        radius: 24,
                                        child: Text(_getInitials(c.name), style: TextStyle(color: avatarText, fontWeight: FontWeight.bold, fontSize: 16)),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1B2B48)), overflow: TextOverflow.ellipsis)),
                                                // Priority is derived from RMS's totalDue, which BUSY-sourced
                                                // rows (c.address set) don't carry — hide rather than show a
                                                // badge computed from an always-zero value.
                                                if (isDone) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(4)),
                                                    child: const Text('DONE', style: TextStyle(color: Color(0xFF16A34A), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                                                  ),
                                                ] else if (c.address == null) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(color: _getBadgeBgColor(priority), borderRadius: BorderRadius.circular(4)),
                                                    child: Text(priority, style: TextStyle(color: _getBadgeColor(priority), fontSize: 10, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(Icons.place_outlined, size: 12, color: Color(0xFFA0AEC0)),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    c.address ?? c.branch,
                                                    style: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 11, fontWeight: FontWeight.w600),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // "Action" is an RMS recovery-workflow field with nothing
                                            // meaningful for BUSY-sourced rows — normally omitted, but
                                            // forced on for the Today's Recovery drill-down.
                                            if ((widget.showNextAction || c.address == null) && c.primaryNextAction.trim().isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Icon(isDone ? Icons.check_circle_outline : Icons.my_location, size: 12, color: const Color(0xFF5A6B87)),
                                                  const SizedBox(width: 4),
                                                  Text(isDone ? 'Recorded: ' : 'Action: ', style: TextStyle(color: const Color(0xFF5A6B87).withOpacity(0.7), fontSize: 11)),
                                                  Flexible(child: Text(c.primaryNextAction, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF1B2B48), fontSize: 11, fontWeight: FontWeight.bold))),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (highlight == null) ...[
                                        const SizedBox(width: 8),
                                        Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: widget.overdueView
                                              ? [
                                                  const Text('OVERDUE', style: TextStyle(color: Color(0xFFE53935), fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 2),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(money.format(c.totalDue), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFE53935), fontSize: 18)),
                                                  ),
                                                ]
                                              : [
                                                  const Text('OUTSTANDING', style: TextStyle(color: Color(0xFF1B2B48), fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 2),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(money.format(c.totalOutstanding), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1B2B48), fontSize: 18)),
                                                  ),
                                                ],
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (isDone) ...[
                                    const SizedBox(height: 10),
                                    const Divider(height: 1, color: Color(0xFFEDF2F7)),
                                    const SizedBox(height: 8),
                                    if (editPending)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                                        child: const Text('Outcome edit pending — awaiting RE review.',
                                            style: TextStyle(fontSize: 11.5, color: Color(0xFFC2410C), fontWeight: FontWeight.w600)),
                                      )
                                    else
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          onPressed: () => Navigator.push(context, MaterialPageRoute(
                                              builder: (_) => Customer360Screen(customer: c, editOutcome: true))),
                                          icon: const Icon(Icons.edit_note, size: 18),
                                          label: const Text('Edit Recorded Outcome'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFF0052CC),
                                            side: const BorderSide(color: Color(0xFF0052CC)),
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                  ],
                                  if (highlight != null) ...[
                                    const SizedBox(height: 12),
                                    const Divider(height: 1, color: Color(0xFFEDF2F7)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(child: _amountCell(widget.highlightAmountLabel, money.format(highlight), const Color(0xFFF57C00))),
                                        Container(width: 1, height: 30, color: const Color(0xFFEDF2F7)),
                                        Expanded(child: _amountCell('OUTSTANDING', money.format(c.totalOutstanding), const Color(0xFF1B2B48), alignEnd: true)),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _amountCell(String label, String value, Color valueColor, {bool alignEnd = false}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF97A3B6), fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: valueColor, fontSize: 16)),
        ),
      ],
    );
  }

  /// Full-width segmented control — equal-width pills, label on the left.
  /// Used by the Customer Name / Amount sort screens.
  Widget _buildSegmentGroup({
    required String label,
    required List<String> options,
    required String selected,
    required Function(String) onSelected,
    List<IconData>? icons,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Color(0xFF5A6B87))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              for (int i = 0; i < options.length; i++)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onSelected(options[i]),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected == options[i]
                            ? const Color(0xFF0052CC)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icons != null) ...[
                            Icon(icons[i],
                                size: 14,
                                color: selected == options[i]
                                    ? Colors.white
                                    : const Color(0xFF5A6B87)),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: Text(
                              options[i],
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: selected == options[i]
                                    ? Colors.white
                                    : const Color(0xFF5A6B87),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterRow({
    required String label,
    required List<String> options,
    required String selectedValue,
    required Function(String) onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF5A6B87))),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: options.map((opt) {
            final isSel = selectedValue == opt;
            return ChoiceChip(
              label: Text(opt, style: TextStyle(color: isSel ? Colors.white : const Color(0xFF5A6B87), fontSize: 11, fontWeight: FontWeight.bold)),
              selected: isSel,
              selectedColor: const Color(0xFF0052CC),
              backgroundColor: const Color(0xFFF0F4F8),
              onSelected: (selected) {
                if (selected) {
                  onSelected(opt);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
