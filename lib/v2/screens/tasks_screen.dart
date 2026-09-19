import 'package:flutter/material.dart';
import 'package:salesman_mobile/widgets/data_loading.dart' show LoadingAppBarStrip;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v3/screens/task_details_screen_v3.dart';
import 'package:intl/intl.dart';

class TasksScreen extends StatefulWidget {
  /// Which tab to open on ('All' | 'Today' | 'Overdue' | 'Completed' |
  /// 'Upcoming'). Lets other screens (e.g. the dashboard "Tasks Due Today"
  /// card) deep-link straight into the matching filter.
  final String initialFilter;

  const TasksScreen({super.key, this.initialFilter = 'All'});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  late String _selectedFilter = widget.initialFilter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final allTasks = store.myTasks;
    final notCompleted = allTasks.where((t) => t.status != TaskStatus.completed);
    // Overdue means "deadline already passed" (time-aware, not just "was
    // due before today") — a task due 5 minutes ago is overdue right now,
    // not merely "Today", and needs to actually surface as urgent rather
    // than sit unflagged in the Today tab for the rest of the day.
    final overdueTasks = notCompleted.where((t) => t.deadline.isBefore(now)).toList();
    final todayTasks = notCompleted.where((t) => !t.deadline.isBefore(now) && t.deadline.isBefore(endOfToday)).toList();
    final upcomingTasks = notCompleted.where((t) => !t.deadline.isBefore(now) && t.deadline.isAfter(endOfToday)).toList();
    final completedTasks = allTasks.where((t) => t.status == TaskStatus.completed).toList();

    List<AppTask> displayedTasks = allTasks;
    if (_selectedFilter == 'Today') displayedTasks = todayTasks;
    if (_selectedFilter == 'Overdue') displayedTasks = overdueTasks;
    if (_selectedFilter == 'Completed') displayedTasks = completedTasks;
    if (_selectedFilter == 'Upcoming') displayedTasks = upcomingTasks;
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      displayedTasks = displayedTasks.where((t) => t.reason.toLowerCase().contains(q) || t.customerName.toLowerCase().contains(q) || t.type.name.toLowerCase().contains(q)).toList();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0052CC),
        elevation: 0,
        title: const Text('My Tasks', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
        bottom: const LoadingAppBarStrip(),
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF0052CC),
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tabs and Search
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildTab('All', Icons.all_inbox, allTasks.length),
                        _buildTab('Today', Icons.today, todayTasks.length),
                        _buildTab('Overdue', Icons.warning_amber_rounded, overdueTasks.length),
                        _buildTab('Completed', Icons.check_circle_outline, completedTasks.length),
                        _buildTab('Upcoming', Icons.next_plan_outlined, upcomingTasks.length),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF8F9FB),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFFA0AEC0), size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        hintText: 'Search tasks, customers...',
                        hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.1))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.1))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.1))),
                      ),
                    ),
                  )
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEDF2F7)),
            
            // List
            Expanded(
              child: displayedTasks.isEmpty 
                ? const Center(child: Text('No tasks found.', style: TextStyle(color: Color(0xFF5A6B87))))
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: displayedTasks.length,
                    itemBuilder: (ctx, i) {
                      final t = displayedTasks[i];
                      return _buildTaskCard(t, store);
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildTab(String label, IconData icon, int count) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0052CC) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? const Color(0xFF0052CC) : Colors.grey.withOpacity(0.2)),
          boxShadow: isSelected ? [
            BoxShadow(color: const Color(0xFF0052CC).withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))
          ] : [],
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF5A6B87)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF1B2B48), fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: isSelected ? Colors.white.withOpacity(0.25) : const Color(0xFFF8F9FB), borderRadius: BorderRadius.circular(12)),
              child: Text(count.toString(), style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF1B2B48), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getTaskIconInfo(TaskType type) {
    switch (type) {
      case TaskType.customerCall: return {'icon': Icons.phone, 'color': const Color(0xFF0052CC), 'bg': const Color(0xFFE3F2FD)};
      case TaskType.physicalVisit: return {'icon': Icons.directions_walk, 'color': const Color(0xFFE53935), 'bg': const Color(0xFFFFEBEE)};
      case TaskType.disputeResolution: return {'icon': Icons.warning_amber_rounded, 'color': const Color(0xFFF57C00), 'bg': const Color(0xFFFFF3E0)};
      case TaskType.paymentVerification: return {'icon': Icons.verified, 'color': const Color(0xFF388E3C), 'bg': const Color(0xFFE8F5E9)};
      case TaskType.managementInstruction: return {'icon': Icons.assignment_ind, 'color': const Color(0xFF8E24AA), 'bg': const Color(0xFFF3E5F5)};
      default: return {'icon': Icons.task, 'color': const Color(0xFF5A6B87), 'bg': const Color(0xFFF8F9FB)};
    }
  }

  /// Dispute-linked tasks come from the server as `type: customerCall` with
  /// a "DISPUTE CLARIFICATION NEEDED: …" / "DISPUTE RESOLUTION: …" reason —
  /// render them by their real purpose, not as a phone-call task. Returns
  /// null for an ordinary task.
  Map<String, String>? _disputeTaskMeta(AppTask t) {
    const clar = 'DISPUTE CLARIFICATION NEEDED:';
    const reso = 'DISPUTE RESOLUTION:';
    if (t.reason.startsWith(clar)) {
      return {'kind': 'clarify', 'title': 'Dispute — clarification needed', 'related': 'Dispute Clarification', 'desc': t.reason.substring(clar.length).trim()};
    }
    if (t.reason.startsWith(reso)) {
      return {'kind': 'resolve', 'title': 'Dispute — resolve', 'related': 'Dispute Resolution', 'desc': t.reason.substring(reso.length).trim()};
    }
    return null;
  }

  /// "Related To" is the recorded outcome this task came out of — not the
  /// raw task type. Derived from the task's source + reason (which the
  /// server stamps when the follow-up is created).
  String _relatedOutcomeLabel(AppTask t) {
    final r = t.reason.toLowerCase();
    final s = t.source;
    if (r.contains('broken ptp') || r.contains('ptp was broken') || r.contains('ptp broke') || s == 'PTP Verification') {
      return 'PTP Broken';
    }
    if (r.contains('re-collect') || r.contains('dispute rejected')) return 'Dispute Rejected';
    if (s == 'Dispute Review') return 'Dispute Raised';
    if (s == 'Payment Claim Review' || r.contains('payment claim')) return 'Payment Already Made';
    if (s == 'Internal Action Review' || r.contains('internal action')) return 'Internal Action';
    if (s == 'Recovery Reconcile' || s == 'Recovery' || r.startsWith('recover ₹') || r.contains('record a new outcome')) return 'Recovery — Balance Due';
    if (t.type == TaskType.physicalVisit &&
        (r.contains('non-response') || r.contains('non response') || s == 'Record Outcome')) {
      return 'No Answer'; // 3rd-attempt physical visit
    }
    if (s == 'Record Outcome') {
      if (r.contains('no answer') || r.contains('not reachable') || r.contains('non-response')) return 'No Answer';
      if (r.contains('refused') || r.contains('unable to commit')) return 'Customer Refused';
      // Every other Record-Outcome follow-up is a scheduled call-back from a
      // "Will Confirm / Follow-up" outcome (the reason is just its date/time).
      return 'Follow-up Scheduled';
    }
    // Fall back to a readable task-type label.
    return t.type.name.replaceAll(RegExp(r'(?<!^)(?=[A-Z])'), ' ').toUpperCase();
  }

  Widget _buildTaskCard(AppTask t, AppStore store) {
    final isCompleted = t.status == TaskStatus.completed;
    final isCritical = t.priority == 'Critical';
    final disputeMeta = _disputeTaskMeta(t);
    final iconInfo = disputeMeta == null
        ? _getTaskIconInfo(t.type)
        : (disputeMeta['kind'] == 'clarify'
            ? {'icon': Icons.help_outline, 'color': const Color(0xFFF57C00), 'bg': const Color(0xFFFFF3E0)}
            : {'icon': Icons.gavel_outlined, 'color': const Color(0xFF4F46E5), 'bg': const Color(0xFFEEF2FF)});
    final cardTitle = disputeMeta?['title'] ?? t.reason;
    final relatedTo = disputeMeta?['related'] ?? _relatedOutcomeLabel(t);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ]
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreenV3(task: t)));
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: isCompleted ? const Color(0xFFE8F5E9) : iconInfo['bg'] as Color, borderRadius: BorderRadius.circular(12)),
                      child: Icon(isCompleted ? Icons.check_circle : iconInfo['icon'] as IconData, color: isCompleted ? const Color(0xFF388E3C) : iconInfo['color'] as Color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isCritical && !isCompleted)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: const Color(0xFFFFEBEE), borderRadius: BorderRadius.circular(4)),
                              child: const Text('Urgent', style: TextStyle(color: Color(0xFFE53935), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          Text(cardTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: const Color(0xFF1B2B48), decoration: isCompleted ? TextDecoration.lineThrough : null)),
                          if (disputeMeta != null && (disputeMeta['desc'] ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(disputeMeta['desc']!, style: const TextStyle(fontSize: 12.5, color: Color(0xFF5A6B87))),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: Color(0xFFEDF2F7)),
                const SizedBox(height: 12),

                // Tabular Data
                _buildDataRow(Icons.person_outline, 'Customer', t.customerName, Icons.category_outlined, 'Related To', relatedTo),
                const SizedBox(height: 12),
                _buildDataRow(Icons.calendar_today_outlined, 'Due On', DateFormat('dd MMM, HH:mm').format(t.deadline), Icons.info_outline, 'Status', isCompleted ? 'Completed' : 'Pending', vColor2: isCompleted ? const Color(0xFF388E3C) : const Color(0xFFF57C00)),
                if (!isCompleted) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0052CC),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => TaskDetailsScreenV3(task: t)));
                      },
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('View Task', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(IconData icon1, String l1, String v1, IconData icon2, String l2, String v2, {Color? vColor1, Color? vColor2}) {
    return Row(
      children: [
        Expanded(child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon1, size: 16, color: const Color(0xFF5A6B87)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l1, style: const TextStyle(color: Color(0xFF5A6B87), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(v1, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: vColor1 ?? const Color(0xFF1B2B48), fontSize: 13, fontWeight: FontWeight.bold)),
                ]
              ),
            ),
          ]
        )),
        Expanded(child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon2, size: 16, color: const Color(0xFF5A6B87)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l2, style: const TextStyle(color: Color(0xFF5A6B87), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(v2, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: vColor2 ?? const Color(0xFF1B2B48), fontSize: 13, fontWeight: FontWeight.bold)),
                ]
              ),
            ),
          ]
        )),
      ],
    );
  }
}
