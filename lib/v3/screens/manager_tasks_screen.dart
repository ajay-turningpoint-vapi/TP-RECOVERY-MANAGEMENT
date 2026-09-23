import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart' show kDark, kNavy, kMuted, kBorder, kBg, kBlue, kRed, kOrange, kPurple, kGreen, taskTypeLabel, taskTypeIcon;

/// Read-only task monitoring for the Manager role — real `AppTask` data,
/// company-wide, no action controls. A manager can track progress and
/// delays but cannot edit, approve, reassign, or complete a task from here.
enum _Filter { all, pending, inProgress, overdue, completed, approval }

class ManagerTasksScreen extends StatefulWidget {
  final void Function(int)? onNavigate;
  const ManagerTasksScreen({super.key, this.onNavigate});

  @override
  State<ManagerTasksScreen> createState() => _ManagerTasksScreenState();
}

class _ManagerTasksScreenState extends State<ManagerTasksScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';
  bool _sortAscending = true;
  final Set<String> _priorityFilter = {'High', 'Medium', 'Low'};

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  bool _isTomorrow(DateTime d) => _isToday(d.subtract(const Duration(days: 1)));

  /// An honest "how overdue" label — the old `.clamp(1, 999)` on inDays
  /// forced a false "1 day" floor for anything overdue by minutes or
  /// hours (and its plural "s" used the unclamped value, so it could even
  /// read "1 days").
  String _overdueLabel(DateTime now, DateTime deadline) {
    final diff = now.difference(deadline);
    if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'}';
    final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return '$minutes minute${minutes == 1 ? '' : 's'}';
  }

  String _priorityLabel(String p) {
    if (p == 'Critical' || p == 'High') return 'High';
    if (p == 'Normal') return 'Medium';
    return 'Low';
  }

  Color _priorityColor(String label) {
    switch (label) {
      case 'High':
        return kRed;
      case 'Medium':
        return kOrange;
      default:
        return kGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    var tasks = store.tasks.toList();

    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      tasks = tasks.where((t) => taskTypeLabel(t.type).toLowerCase().contains(q) || t.customerName.toLowerCase().contains(q) || t.ownerId.toLowerCase().contains(q)).toList();
    }
    tasks = tasks.where((t) => _priorityFilter.contains(_priorityLabel(t.priority))).toList();

    final total = tasks.length;
    final dueToday = tasks.where((t) => t.status != TaskStatus.completed && _isToday(t.deadline)).length;
    final overdue = tasks.where((t) => t.isOverdue).length;
    final completedToday = tasks.where((t) => t.status == TaskStatus.completed && _isToday(t.completedAt ?? t.deadline)).length;
    final awaitingApproval = tasks.where((t) => t.approvalStatus == 'Pending').length;
    final pendingCount = tasks.where((t) => t.status == TaskStatus.pending && t.approvalStatus != 'Pending').length;
    final inProgressCount = tasks.where((t) => t.status == TaskStatus.inProgress).length;
    final completedCount = tasks.where((t) => t.status == TaskStatus.completed).length;

    List<AppTask> filtered;
    switch (_filter) {
      case _Filter.pending:
        filtered = tasks.where((t) => t.status == TaskStatus.pending && t.approvalStatus != 'Pending').toList();
        break;
      case _Filter.inProgress:
        filtered = tasks.where((t) => t.status == TaskStatus.inProgress).toList();
        break;
      case _Filter.overdue:
        filtered = tasks.where((t) => t.isOverdue).toList();
        break;
      case _Filter.completed:
        filtered = tasks.where((t) => t.status == TaskStatus.completed).toList();
        break;
      case _Filter.approval:
        filtered = tasks.where((t) => t.approvalStatus == 'Pending').toList();
        break;
      case _Filter.all:
        filtered = tasks;
    }
    filtered.sort((a, b) => _sortAscending ? a.deadline.compareTo(b.deadline) : b.deadline.compareTo(a.deadline));

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              children: [
                _header(context),
                _statCards(total, dueToday, overdue, completedToday, awaitingApproval),
                _filterChips(total, pendingCount, inProgressCount, overdue, completedCount, awaitingApproval),
                _searchSortRow(context),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No tasks in this view.', style: TextStyle(color: kMuted)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) => _taskCard(context, filtered[i]),
                        ),
                ),
                if (overdue > 0) _overdueBanner(overdue),
              ],
            );
            if (constraints.maxWidth <= 600) return content;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header
  // -------------------------------------------------------------------
  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: kNavy),
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                widget.onNavigate?.call(0);
              }
            },
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Task Monitoring', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: kNavy)),
                Text('Track assigned tasks, delays and completions', style: TextStyle(fontSize: 11.5, color: kMuted)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
            child: IconButton(icon: const Icon(Icons.tune, color: kNavy, size: 20), onPressed: () => _showFilterSheet(context)),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Stat cards
  // -------------------------------------------------------------------
  Widget _statCards(int total, int dueToday, int overdue, int completedToday, int awaitingApproval) {
    final cards = [
      (Icons.assignment_outlined, kPurple, '$total', 'Total Tasks'),
      (Icons.event_outlined, kOrange, '$dueToday', 'Due Today'),
      (Icons.warning_amber_rounded, kRed, '$overdue', 'Overdue'),
      (Icons.check_circle_outline, kGreen, '$completedToday', 'Completed Today'),
      (Icons.description_outlined, kBlue, '$awaitingApproval', 'Awaiting Approval'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final (icon, color, value, label) = cards[i];
            return Container(
              width: 92,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color),
                  const Spacer(),
                  Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color)),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: kDark, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Filter chips
  // -------------------------------------------------------------------
  Widget _filterChips(int all, int pending, int inProgress, int overdue, int completed, int approval) {
    final chips = [
      (_Filter.all, 'All', all),
      (_Filter.pending, 'Pending', pending),
      (_Filter.inProgress, 'In Progress', inProgress),
      (_Filter.overdue, 'Overdue', overdue),
      (_Filter.completed, 'Completed', completed),
      (_Filter.approval, 'Approval', approval),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: SizedBox(
        height: 34,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Builder(builder: (ctx) {
                  final (filterValue, label, count) = chips[i];
                  final active = _filter == filterValue;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = filterValue),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: active ? kBlue : Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: active ? kBlue : kBorder)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.white : kDark)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: active ? Colors.white.withValues(alpha: 0.25) : kBg, borderRadius: BorderRadius.circular(10)),
                            child: Text('$count', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: active ? Colors.white : kMuted)),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Search + Sort
  // -------------------------------------------------------------------
  Widget _searchSortRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 12, color: kDark),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search, size: 18, color: kMuted),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                  hintText: 'Search by task title, customer or owner',
                  hintStyle: const TextStyle(fontSize: 11.5, color: kMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _sortAscending = !_sortAscending),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: kNavy),
                  const SizedBox(width: 4),
                  const Text('Sort', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kNavy)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (context, setModalState) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter by Priority', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['High', 'Medium', 'Low'].map((p) {
                    final selected = _priorityFilter.contains(p);
                    return FilterChip(
                      label: Text(p, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      selectedColor: _priorityColor(p).withValues(alpha: 0.15),
                      checkmarkColor: _priorityColor(p),
                      onSelected: (v) {
                        setModalState(() {
                          setState(() {
                            if (v) {
                              _priorityFilter.add(p);
                            } else if (_priorityFilter.length > 1) {
                              _priorityFilter.remove(p);
                            }
                          });
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Apply', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // -------------------------------------------------------------------
  // Task card (view-only — tap opens a read-only detail sheet)
  // -------------------------------------------------------------------
  Widget _taskCard(BuildContext context, AppTask t) {
    final priorityLabel = _priorityLabel(t.priority);
    final priorityColor = _priorityColor(priorityLabel);

    String statusLabel;
    Color statusColor;
    if (t.approvalStatus == 'Pending') {
      statusLabel = 'Awaiting Approval';
      statusColor = kBlue;
    } else if (t.status == TaskStatus.completed) {
      statusLabel = 'Completed';
      statusColor = kGreen;
    } else if (t.isOverdue) {
      statusLabel = 'Overdue';
      statusColor = kRed;
    } else if (t.status == TaskStatus.inProgress) {
      statusLabel = 'In Progress';
      statusColor = kBlue;
    } else {
      statusLabel = 'Pending';
      statusColor = kPurple;
    }

    final metaText = _metaText(t);
    final metaColor = _metaColor(t);
    final metaIcon = _metaIcon(t);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetailSheet(context, t, priorityLabel, priorityColor, statusLabel, statusColor),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(taskTypeIcon(t.type), size: 18, color: priorityColor)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(taskTypeLabel(t.type), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kNavy)),
                    Text('${t.customerName}  •  ${context.read<AppStore>().salesmanDisplayName(t.ownerId)}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(metaIcon, size: 12, color: metaColor),
                        const SizedBox(width: 4),
                        Flexible(child: Text(metaText, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: metaColor))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(priorityLabel, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: priorityColor)),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(statusLabel, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: statusColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 130,
                    child: Text(t.reason, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kMuted)),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, size: 18, color: kMuted),
            ],
          ),
        ),
      ),
    );
  }

  String _metaText(AppTask t) {
    final now = DateTime.now();
    if (t.approvalStatus == 'Pending') return 'Awaiting RE approval';
    if (t.status == TaskStatus.completed) {
      final done = t.completedAt ?? t.deadline;
      return _isToday(done) ? 'Completed Today, ${DateFormat('hh:mm a').format(done)}' : 'Completed ${DateFormat('dd MMM').format(done)}';
    }
    if (t.isOverdue) return 'Overdue by ${_overdueLabel(now, t.deadline)}';
    if (_isToday(t.deadline)) return 'Due Today, ${DateFormat('hh:mm a').format(t.deadline)}';
    if (_isTomorrow(t.deadline)) return 'Due Tomorrow, ${DateFormat('hh:mm a').format(t.deadline)}';
    return 'Due ${DateFormat('dd MMM, hh:mm a').format(t.deadline)}';
  }

  Color _metaColor(AppTask t) {
    if (t.approvalStatus == 'Pending') return kOrange;
    if (t.status == TaskStatus.completed) return kGreen;
    if (t.isOverdue) return kRed;
    return kBlue;
  }

  IconData _metaIcon(AppTask t) {
    if (t.approvalStatus == 'Pending') return Icons.hourglass_empty;
    if (t.status == TaskStatus.completed) return Icons.check_circle;
    if (t.isOverdue) return Icons.warning_amber_rounded;
    return Icons.access_time;
  }

  // -------------------------------------------------------------------
  // Read-only detail sheet
  // -------------------------------------------------------------------
  void _showDetailSheet(BuildContext context, AppTask t, String priorityLabel, Color priorityColor, String statusLabel, Color statusColor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)), child: Icon(taskTypeIcon(t.type), color: priorityColor)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(taskTypeLabel(t.type), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kNavy)),
                          Text('${t.customerName}  •  ${context.read<AppStore>().salesmanDisplayName(t.ownerId)}', style: const TextStyle(fontSize: 12, color: kMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text('$priorityLabel Priority', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: priorityColor))),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Text(statusLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor))),
                  ],
                ),
                const SizedBox(height: 16),
                _detailRow('Due Date', DateFormat('dd MMM yyyy, hh:mm a').format(t.deadline)),
                _detailRow('Description', t.reason),
                if (t.outcome != null) _detailRow('Outcome', t.outcome!),
                if (t.approvalStatus == 'Pending') ...[
                  _detailRow('Proposed Details', t.pendingReason ?? '-'),
                  if (t.pendingDeadline != null) _detailRow('Proposed Due Date', DateFormat('dd MMM yyyy, hh:mm a').format(t.pendingDeadline!)),
                ],
                _detailRow('Source', t.source),
                const SizedBox(height: 8),
                const Text('Manager view is read-only — actions on this task are taken by the Recovery Executive or the assigned salesperson.', style: TextStyle(fontSize: 11, color: kMuted, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, color: kDark, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // Overdue banner
  // -------------------------------------------------------------------
  Widget _overdueBanner(int overdue) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kRed.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: kRed.withValues(alpha: 0.2))),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: kRed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$overdue task${overdue == 1 ? '' : 's'} are overdue and need manager attention', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kDark)),
                const Text('Review and reassign to avoid further delays.', style: TextStyle(fontSize: 10.5, color: kMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kPurple, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () => setState(() => _filter = _Filter.overdue),
            child: const Text('Review', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
