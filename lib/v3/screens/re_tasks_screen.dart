import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';
import 'package:salesman_mobile/v3/screens/unified_task_detail_screen.dart';

final _rupee =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _navy = Color(0xFF1B2B48);
const _blue = Color(0xFF2563EB);

/// Every real, actionable item in the system rendered as one row — the RE's
/// unified "what must I personally do" queue (spec §3, §28). Each item
/// carries a [TaskKind] + refId so it opens the one shared, fully-functional
/// Task Details screen — no duplicated or diverging action logic.
class _TaskItem {
  final String id;
  final TaskKind kind;
  final String refId;
  final IconData icon;
  final Color color;
  final String priority; // 'HIGH' | 'MEDIUM' | 'LOW'
  final String title;
  final String subtitle1;
  final String subtitle2;
  final DateTime date;
  final bool isDone;
  final String? amountLabel;
  final double? amountValue;
  final Color amountColor;
  // A second, distinct figure — currently only used by 'Overdue Target
  // Review' items, which need both the salesman's Total Overdue AND
  // their PTP amount due today shown as two separate numbers, not one
  // figure standing in for both.
  final String? secondAmountLabel;
  final double? secondAmountValue;

  _TaskItem({
    required this.id,
    required this.kind,
    required this.refId,
    required this.icon,
    required this.color,
    required this.priority,
    required this.title,
    required this.subtitle1,
    required this.subtitle2,
    required this.date,
    required this.isDone,
    this.amountLabel,
    this.amountValue,
    this.amountColor = kRed,
    this.secondAmountLabel,
    this.secondAmountValue,
  });
}

Color _priorityColor(String p) {
  switch (p) {
    case 'HIGH':
      return kRed;
    case 'MEDIUM':
      return kOrange;
    default:
      return kGreen;
  }
}

enum _Filter { all, dueToday, overdue, upcoming, completed }

class ReTasksScreen extends StatefulWidget {
  const ReTasksScreen({super.key});

  @override
  State<ReTasksScreen> createState() => _ReTasksScreenState();
}

class _ReTasksScreenState extends State<ReTasksScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';
  int _visible = 6;
  final Set<String> _priorityFilter = {'HIGH', 'MEDIUM', 'LOW'};
  final ScrollController _scrollController = ScrollController();
  // Updated at the top of build() — lets the scroll listener know whether
  // there's actually anything left to load, so it doesn't keep calling
  // setState every scroll tick once the whole filtered list is showing.
  int _totalFilteredCount = 0;

  @override
  void initState() {
    super.initState();
    // Infinite scroll — replaces the old tap-to-load "Load More" row.
    // Grows the visible window as the user nears the bottom instead of
    // requiring an explicit tap each time.
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      if (_visible >= _totalFilteredCount) return;
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 300) {
        setState(() => _visible += 6);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  /// An honest "how overdue" label — the old `.clamp(1, 999)` on inDays
  /// forced a false "1 Day" floor for anything overdue by minutes or
  /// hours, which is exactly what a same-day-overdue item would show.
  String _overdueLabel(DateTime now, DateTime due) {
    final diff = now.difference(due);
    if (diff.inDays >= 1)
      return '${diff.inDays} Day${diff.inDays == 1 ? '' : 's'}';
    if (diff.inHours >= 1)
      return '${diff.inHours} Hour${diff.inHours == 1 ? '' : 's'}';
    final minutes = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return '$minutes Minute${minutes == 1 ? '' : 's'}';
  }

  List<_TaskItem> _buildItems(AppStore store) {
    final items = <_TaskItem>[];

    // 1) Real AppTasks — excluding items that get their own specialised
    // entry below (pending extension requests, unreviewed physical visits).
    for (final t in store.tasks) {
      final isVisitPendingReview = t.type == TaskType.physicalVisit &&
          t.status == TaskStatus.completed &&
          !t.reviewedByRE;
      if (t.approvalStatus == 'Pending' || isVisitPendingReview) continue;
      final done = t.status == TaskStatus.completed;
      final priority = t.priority == 'Critical' || t.priority == 'High'
          ? 'HIGH'
          : (t.priority == 'Normal' ? 'MEDIUM' : 'LOW');
      items.add(_TaskItem(
        id: 'task_${t.id}',
        kind: TaskKind.realTask,
        refId: t.id,
        icon: taskTypeIcon(t.type),
        color: _priorityColor(priority),
        priority: priority,
        title: taskTypeLabel(t.type),
        subtitle1: 'Owner: ${store.salesmanDisplayName(t.ownerId)}',
        subtitle2: t.customerName,
        date: t.deadline,
        isDone: done,
        amountLabel: 'Outstanding',
        amountValue: store.customers
            .firstWhere((c) => c.id == t.customerId,
                orElse: () => store.customers.first)
            .totalDue,
      ));
    }

    // 2) Physical visits pending RE review
    for (final t in store.physicalVisitsPendingReview) {
      final dispute = store.disputes.cast<Map<String, dynamic>?>().firstWhere(
          (d) => d != null && d['customer'] == t.customerName,
          orElse: () => null);
      items.add(_TaskItem(
        id: 'visit_${t.id}',
        kind: TaskKind.visitReview,
        refId: t.id,
        icon: Icons.location_on_outlined,
        color: kPurple,
        priority: 'MEDIUM',
        title: 'Physical Visit Review',
        subtitle1: 'Salesman: ${store.salesmanDisplayName(t.ownerId)}',
        subtitle2: t.customerName,
        date: t.completedAt ?? t.deadline,
        isDone: false,
        amountLabel: dispute != null ? 'Amount in Dispute' : 'Outstanding',
        amountValue: dispute != null
            ? (dispute['amount'] as num).toDouble()
            : store.customers
                .firstWhere((c) => c.id == t.customerId,
                    orElse: () => store.customers.first)
                .totalDue,
        amountColor: kPurple,
      ));
    }

    // 3) Task extension requests
    for (final t in store.tasks.where((t) => t.approvalStatus == 'Pending')) {
      items.add(_TaskItem(
        id: 'ext_${t.id}',
        kind: TaskKind.taskExtension,
        refId: t.id,
        icon: Icons.schedule,
        color: kAmber,
        priority: 'MEDIUM',
        title: 'Task Extension Request',
        subtitle1: 'Salesman: ${store.salesmanDisplayName(t.ownerId)}',
        subtitle2: t.customerName,
        date: t.pendingDeadline ?? t.deadline,
        isDone: false,
        amountLabel: 'Outstanding',
        amountValue: store.customers
            .firstWhere((c) => c.id == t.customerId,
                orElse: () => store.customers.first)
            .totalDue,
        amountColor: kAmber,
      ));
    }

    // 5) Underperforming salesmen — surfaced at the customer level, not the
    // salesman level. A "review this salesman" item with no specific
    // account attached gives RE nothing to actually act on; the real
    // problem always lives on one of their accounts. So this points
    // straight at that salesman's single largest overdue account — RE
    // opens that customer, sees the real numbers, and can create a task /
    // contact the salesman about that specific account.
    for (final s in store.salesmen
        .where((s) => (s['collectionAchievedPercent'] as int) < 60)) {
      final owned = store.customers
          .where((c) => c.assignedSalesmanId == s['name'] && c.totalDue > 0)
          .toList();
      if (owned.isEmpty) continue;
      owned.sort((a, b) => b.totalDue.compareTo(a.totalDue));
      final worst = owned.first;
      items.add(_TaskItem(
        id: 'target_${worst.id}',
        kind: TaskKind.overdueTarget,
        refId: worst.id,
        icon: Icons.person_outline,
        color: kOrange,
        priority: 'MEDIUM',
        title: 'Underperforming Salesman — Top Account',
        subtitle1: 'Salesman: ${(s['fullName'] as String?) ?? s['name']} (${s['collectionAchievedPercent']}% achieved)',
        subtitle2: worst.name,
        date: DateTime.now(),
        isDone: false,
        amountLabel: 'Overdue Amount',
        amountValue: worst.totalDue,
        amountColor: kOrange,
        secondAmountLabel: 'PTP Due Today',
        secondAmountValue: (s['dueTodayPtps'] as num).toDouble(),
      ));
    }

    // 6) Disputes awaiting review — 'Awaiting Verification' belongs to the
    // canonical in-progress bucket, not awaiting-review (matches
    // store.disputesAwaitingReviewCount, which totalOpenTaskItemsCount's
    // dispute term is built from).
    for (final d
        in store.disputes.where((d) => d['status'] == 'Pending Approval')) {
      items.add(_TaskItem(
        id: 'dispute_${d['id']}',
        kind: TaskKind.dispute,
        refId: d['id'],
        icon: Icons.description_outlined,
        color: kIndigo,
        priority: (d['priority'] as String?) == 'High' ? 'HIGH' : 'MEDIUM',
        title: 'Dispute Awaiting Review',
        subtitle1:
            'Raised: ${DateFormat('dd MMM yyyy').format(d['raisedDate'])}',
        subtitle2: '${d['customer']}  ·  ${d['invoice']}',
        date: (d['lastUpdated'] as DateTime?) ?? DateTime.now(),
        isDone: false,
        amountLabel: 'Dispute Amount',
        amountValue: (d['amount'] as num).toDouble(),
        amountColor: kIndigo,
      ));
    }

    // 7) PTP correction requests
    for (final p in store.ptpCorrectionRequests) {
      final c = store.customers.firstWhere((c) => c.id == p.customerId,
          orElse: () => store.customers.first);
      items.add(_TaskItem(
        id: 'ptpc_${p.id}',
        kind: TaskKind.ptpCorrection,
        refId: p.id,
        icon: Icons.swap_horiz,
        color: kTeal,
        priority: 'MEDIUM',
        title: 'PTP Correction Request',
        subtitle1: 'Customer: ${c.name}',
        subtitle2: 'Owner: ${store.salesmanDisplayName(c.assignedSalesmanId)}',
        date: p.correctionRequestedDate ?? p.promiseDate,
        isDone: false,
        amountLabel: 'Requested Amount',
        amountValue: p.correctionRequestedAmount ?? p.amountPromised,
        amountColor: kTeal,
      ));
    }

    // 8) Outcome edit requests
    for (final r in store.pendingOutcomeEdits) {
      items.add(_TaskItem(
        id: 'oer_${r.id}',
        kind: TaskKind.outcomeEdit,
        refId: r.id,
        icon: Icons.edit_note,
        color: kPink,
        priority: 'LOW',
        title: 'Outcome Edit Request',
        subtitle1: 'Customer: ${r.customerName}',
        subtitle2: 'by ${store.salesmanDisplayName(r.salesmanId)}',
        date: r.requestedAt,
        isDone: false,
        amountLabel: null,
      ));
    }

    // 9) Broken PTPs without an open escalation case (raw "PTP Missed" signal)
    final escalatedCustomerIds =
        store.openEscalationCases.map((e) => e.customerId).toSet();
    for (final p in store.brokenPtps) {
      if (escalatedCustomerIds.contains(p.customerId)) continue;
      final c = store.customers.firstWhere((c) => c.id == p.customerId,
          orElse: () => store.customers.first);
      items.add(_TaskItem(
        id: 'ptpm_${p.id}',
        kind: TaskKind.ptpMissed,
        refId: p.id,
        icon: Icons.event_busy,
        color: kRed,
        priority: 'HIGH',
        title: 'PTP Missed',
        subtitle1:
            'Salesman: ${store.salesmanDisplayName(c.assignedSalesmanId)}',
        subtitle2: c.name,
        date: p.promiseDate,
        isDone: false,
        amountLabel: 'PTP Amount',
        amountValue: p.amountPromised,
      ));
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    var items = _buildItems(store);
    items = items.where((i) => _priorityFilter.contains(i.priority)).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      items = items
          .where((i) =>
              i.title.toLowerCase().contains(q) ||
              i.subtitle1.toLowerCase().contains(q) ||
              i.subtitle2.toLowerCase().contains(q))
          .toList();
    }

    final now = DateTime.now();
    final total = items.where((i) => !i.isDone).length;
    // Overdue means "date already passed" (time-aware) — a same-day item
    // whose time has passed is overdue right now, not still "Due Today";
    // the `!i.date.isBefore(now)` guard on dueToday keeps the two buckets
    // mutually exclusive instead of double-counting or hiding lateness for
    // the rest of the calendar day.
    final dueToday = items
        .where((i) => !i.isDone && !i.date.isBefore(now) && _isToday(i.date))
        .length;
    final overdue =
        items.where((i) => !i.isDone && i.date.isBefore(now)).length;
    final upcoming = items
        .where((i) =>
            !i.isDone &&
            i.date.isAfter(now) &&
            !_isToday(i.date) &&
            i.date.difference(now).inDays <= 7)
        .length;
    final completed = items.where((i) => i.isDone).length;

    List<_TaskItem> filtered;
    switch (_filter) {
      case _Filter.dueToday:
        filtered = items
            .where(
                (i) => !i.isDone && !i.date.isBefore(now) && _isToday(i.date))
            .toList();
        break;
      case _Filter.overdue:
        filtered =
            items.where((i) => !i.isDone && i.date.isBefore(now)).toList();
        break;
      case _Filter.upcoming:
        filtered = items
            .where((i) => !i.isDone && i.date.isAfter(now) && !_isToday(i.date))
            .toList();
        break;
      case _Filter.completed:
        filtered = items.where((i) => i.isDone).toList();
        break;
      case _Filter.all:
        filtered = items.where((i) => !i.isDone).toList();
    }
    filtered.sort((a, b) => a.date.compareTo(b.date));
    final shown = filtered.take(_visible).toList();
    _totalFilteredCount = filtered.length;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              children: [
                _header(context),
                _statCards(total, dueToday, overdue, upcoming, completed),
                _search(),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(
                          child: Text('No tasks in this view.',
                              style: TextStyle(color: kMuted)))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                          itemCount: shown.length + 1,
                          itemBuilder: (ctx, i) {
                            if (i == shown.length) {
                              final hasMore = shown.length < filtered.length;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: hasMore
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: _blue))
                                      : Text(
                                          'Showing all ${filtered.length} Tasks',
                                          style: const TextStyle(
                                              fontSize: 11.5, color: kMuted)),
                                ),
                              );
                            }
                            return _taskRow(context, shown[i]);
                          },
                        ),
                ),
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

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tasks',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: _navy)),
                Text('Manage your recovery tasks',
                    style: TextStyle(fontSize: 11.5, color: kMuted)),
              ],
            ),
          ),
          IconButton(
              icon: const Icon(Icons.tune, color: _navy),
              onPressed: () => _showFilterSheet(context)),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (context, setModalState) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter by Priority',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: ['HIGH', 'MEDIUM', 'LOW'].map((p) {
                    final selected = _priorityFilter.contains(p);
                    return FilterChip(
                      label: Text(p, style: const TextStyle(fontSize: 11.5)),
                      selected: selected,
                      selectedColor: _priorityColor(p).withOpacity(0.15),
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
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Apply',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _statCards(
      int total, int dueToday, int overdue, int upcoming, int completed) {
    final cards = [
      (
        _Filter.all,
        Icons.calendar_month_outlined,
        kBlue,
        '$total',
        'Total Tasks',
        'All Pending'
      ),
      (
        _Filter.dueToday,
        Icons.event_outlined,
        kOrange,
        '$dueToday',
        'Due Today',
        'All Priorities'
      ),
      (
        _Filter.overdue,
        Icons.warning_amber_rounded,
        kRed,
        '$overdue',
        'Overdue',
        'Need Action'
      ),
      (
        _Filter.upcoming,
        Icons.schedule,
        kPurple,
        '$upcoming',
        'Upcoming',
        'Next 7 Days'
      ),
      (
        _Filter.completed,
        Icons.check_circle_outline,
        kGreen,
        '$completed',
        'Completed',
        'All Time'
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (ctx, i) {
            final (filterValue, icon, color, value, label, sub) = cards[i];
            final active = _filter == filterValue;
            return GestureDetector(
              onTap: () => setState(() {
                _filter = filterValue;
                _visible = 6;
              }),
              child: Container(
                width: 96,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: active ? color : kBorder, width: active ? 1.6 : 1),
                  boxShadow: active
                      ? [
                          BoxShadow(
                              color: color.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 3))
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            shape: BoxShape.circle),
                        child: Icon(icon, size: 15, color: color)),
                    const Spacer(),
                    Text(value,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: color)),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 9.5,
                            color: kDark,
                            fontWeight: FontWeight.w600)),
                    Text(sub,
                        style: TextStyle(
                            fontSize: 8.5,
                            color: color,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kBorder)),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: kMuted),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() {
                  _query = v;
                  _visible = 6;
                }),
                style: const TextStyle(fontSize: 12, color: kDark),
                decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Search task by customer, salesman, type…',
                    hintStyle: TextStyle(fontSize: 11.5, color: kMuted)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, _TaskItem item) {
    final due = item.date;
    final now = DateTime.now();
    String dueText;
    Color dueColor;
    if (item.isDone) {
      dueText = 'Completed';
      dueColor = kGreen;
    } else if (due.isBefore(now)) {
      // Checked before _isToday — a same-day item whose time has already
      // passed is overdue right now, not still "Due Today" for the rest
      // of the day (see the same fix on the stat counts/filter above).
      dueText = 'Overdue by ${_overdueLabel(now, due)}';
      dueColor = kRed;
    } else if (_isToday(due)) {
      dueText = 'Due Today';
      dueColor = kOrange;
    } else {
      final days = due.difference(now).inDays;
      dueText = days == 1 ? 'Due Tomorrow' : 'Due in $days Days';
      dueColor = _blue;
    }

    void openDetail() => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                UnifiedTaskDetailScreen(kind: item.kind, refId: item.refId)));

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: openDetail,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kBorder)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: item.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(item.icon, size: 18, color: item.color)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: _priorityColor(item.priority).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(item.priority,
                          style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: _priorityColor(item.priority))),
                    ),
                    const SizedBox(height: 4),
                    Text(item.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: _navy)),
                    Text(item.subtitle1,
                        style: const TextStyle(fontSize: 10.5, color: kMuted)),
                    Text(item.subtitle2,
                        style: const TextStyle(fontSize: 10.5, color: kMuted)),
                    const SizedBox(height: 4),
                    Text(dueText,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: dueColor)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (item.amountLabel != null) ...[
                    Text(_rupee.format(item.amountValue ?? 0),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: item.amountColor)),
                    Text(item.amountLabel!,
                        style: const TextStyle(fontSize: 9, color: kMuted)),
                    const SizedBox(height: 6),
                  ],
                  // A distinct second figure — never merged into the first,
                  // so "PTP Due Today" and "Overdue Amount" always read as
                  // two separate numbers, not one standing in for both.
                  if (item.secondAmountLabel != null) ...[
                    Text(_rupee.format(item.secondAmountValue ?? 0),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                            color: kBlue)),
                    Text(item.secondAmountLabel!,
                        style: const TextStyle(fontSize: 9, color: kMuted)),
                    const SizedBox(height: 6),
                  ],
                  if (!item.isDone)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20))),
                      onPressed: openDetail,
                      child: const Text('Take Action',
                          style: TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 4),
                  Text(DateFormat('dd MMM yyyy').format(due),
                      style: const TextStyle(fontSize: 9.5, color: kMuted)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
