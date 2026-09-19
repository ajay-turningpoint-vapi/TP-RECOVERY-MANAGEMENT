import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/v3/screens/request_detail_scaffold.dart';

final _rupee = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
const _navy = Color(0xFF1B2B48);
const _blue = Color(0xFF2563EB);

String _bucketOf(String status) {
  switch (status) {
    case 'Pending Approval':
      return 'OPEN';
    case 'Approved':
    case 'In Resolution':
    case 'Awaiting Verification':
    case 'Need More Information':
      return 'IN PROGRESS';
    case 'Resolved':
      return 'RESOLVED';
    case 'Rejected':
    case 'Returned to Recovery':
      return 'REJECTED';
    default:
      return 'OPEN';
  }
}

Color _bucketColor(String bucket) {
  switch (bucket) {
    case 'OPEN':
      return kRed;
    case 'IN PROGRESS':
      return _blue;
    case 'RESOLVED':
      return kGreen;
    default:
      return kMuted;
  }
}

Color _priorityColor(String priority) {
  switch (priority) {
    case 'High':
      return kRed;
    case 'Medium':
      return kOrange;
    default:
      return kGreen;
  }
}

class DisputesListView extends StatefulWidget {
  final void Function(String disputeId) onOpenDispute;
  const DisputesListView({super.key, required this.onOpenDispute});

  @override
  State<DisputesListView> createState() => _DisputesListViewState();
}

class _DisputesListViewState extends State<DisputesListView> {
  String _bucket = 'ALL';
  String _query = '';
  bool _showBanner = true;
  int _visible = 4;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    List<Map<String, dynamic>> disputes = store.visibleDisputes;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      disputes = disputes.where((d) =>
          (d['customer'] as String).toLowerCase().contains(q) ||
          (d['invoice'] as String? ?? '').toLowerCase().contains(q) ||
          (d['id'] as String).toLowerCase().contains(q)).toList();
    }

    final buckets = {
      'ALL': store.visibleDisputes.length,
      'OPEN': store.visibleDisputes.where((d) => _bucketOf(d['status']) == 'OPEN').length,
      'IN PROGRESS': store.visibleDisputes.where((d) => _bucketOf(d['status']) == 'IN PROGRESS').length,
      'RESOLVED': store.visibleDisputes.where((d) => _bucketOf(d['status']) == 'RESOLVED').length,
      'REJECTED': store.visibleDisputes.where((d) => _bucketOf(d['status']) == 'REJECTED').length,
    };

    if (_bucket != 'ALL') {
      disputes = disputes.where((d) => _bucketOf(d['status']) == _bucket).toList();
    }
    disputes = [...disputes]..sort((a, b) => (b['raisedDate'] as DateTime).compareTo(a['raisedDate'] as DateTime));

    final shown = disputes.take(_visible).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _navy,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('DISPUTES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _navy, letterSpacing: 0.3)),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.filter_alt_outlined, size: 16, color: _blue),
            label: const Text('Filter', style: TextStyle(color: _blue, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: buckets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemBuilder: (ctx, i) {
                  final key = buckets.keys.elementAt(i);
                  final active = _bucket == key;
                  return GestureDetector(
                    onTap: () => setState(() { _bucket = key; _visible = 4; }),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$key (${buckets[key]})', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: active ? _blue : kMuted)),
                        const SizedBox(height: 4),
                        if (active) Container(height: 2, width: 20, color: _blue),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
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
                        fillColor: kBg,
                        prefixIcon: const Icon(Icons.search, size: 18, color: kMuted),
                        prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                        contentPadding: const EdgeInsets.symmetric(vertical: 9),
                        hintText: 'Search by Customer / Invoice / Dispute ID',
                        hintStyle: const TextStyle(fontSize: 11.5, color: kMuted),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.swap_vert, size: 15, color: _blue),
                const SizedBox(width: 4),
                const Text('Sort by', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: kDark)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_showBanner)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFBFDBFE))),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info, size: 16, color: _blue),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Disputes should be raised only for valid reasons.\nAll disputes are reviewed by Recovery Executive.', style: TextStyle(fontSize: 11.5, color: Color(0xFF1E40AF)))),
                                GestureDetector(onTap: () => setState(() => _showBanner = false), child: const Icon(Icons.close, size: 16, color: _blue)),
                              ],
                            ),
                          ),
                        if (shown.isEmpty)
                          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No disputes in this category.', style: TextStyle(color: kMuted)))),
                        ...shown.map((d) => _disputeCard(context, d)),
                        if (disputes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Showing 1 to ${shown.length} of ${disputes.length} Disputes', style: const TextStyle(fontSize: 11.5, color: kMuted)),
                                if (shown.length < disputes.length) ...[
                                  const SizedBox(width: 10),
                                  GestureDetector(
                                    onTap: () => setState(() => _visible += 4),
                                    child: const Text('Load More  ⌄', style: TextStyle(fontSize: 11.5, color: _blue, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _disputeCard(BuildContext context, Map<String, dynamic> d) {
    final bucket = _bucketOf(d['status']);
    final color = _bucketColor(bucket);
    final priority = (d['priority'] as String?) ?? 'Medium';
    return GestureDetector(
      onTap: () => widget.onOpenDispute(d['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 20, backgroundColor: avatarColorFor(d['customer']).withOpacity(0.15), child: Text(initialsFor(d['customer']), style: TextStyle(color: avatarColorFor(d['customer']), fontWeight: FontWeight.bold))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['customer'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: _navy)),
                      const SizedBox(height: 2),
                      Text('${(d['invoice'] as String?) ?? 'No invoice'}  ·  ${d['customerCode']}', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                      Text('Raised: ${DateFormat('dd MMM yyyy').format(d['raisedDate'])}', style: const TextStyle(fontSize: 10, color: kMuted)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text(bucket, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                    ),
                    const SizedBox(height: 6),
                    const Text('Amount in Dispute', style: TextStyle(fontSize: 9, color: kMuted)),
                    Text(_rupee.format(d['amount']), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: bucket == 'RESOLVED' ? kGreen : kRed)),
                  ],
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: kBorder)),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reason', style: TextStyle(fontSize: 9.5, color: kMuted)),
                      Text(d['reason'], style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Priority', style: TextStyle(fontSize: 9.5, color: kMuted)),
                      Row(children: [
                        Icon(Icons.circle, size: 7, color: _priorityColor(priority)),
                        const SizedBox(width: 4),
                        Text(priority, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: _priorityColor(priority))),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Last Updated: ${DateFormat('dd MMM yyyy').format(d['lastUpdated'])}  ·  ', style: const TextStyle(fontSize: 10.5, color: kMuted)),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(d['statusDetail'] ?? d['status'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _blue)),
                const Icon(Icons.chevron_right, size: 16, color: kMuted),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
