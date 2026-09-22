import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/widgets/app_message.dart';
import 'package:salesman_mobile/widgets/data_loading.dart' show LoadingAppBarStrip;

const _bg = Color(0xFFF8FAFC);
const _dark = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _blue = Color(0xFF2563EB);

class FivePmControlScreen extends StatelessWidget {
  const FivePmControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final snapshots = store.controlSnapshots;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('5 PM Control', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _dark)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: _dark,
        bottom: const LoadingAppBarStrip(color: Color(0xFF2563EB)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = _buildBody(context, store, fmt, snapshots);
          if (constraints.maxWidth > 600) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: content,
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppStore store, NumberFormat fmt, List snapshots) {
    return Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  store.runFivePmControl();
                  showAppMessage(context, message: '5 PM Control snapshot recorded.');
                },
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Run Control Now', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('History is immutable — later completion does not erase a recorded control event.', style: TextStyle(fontSize: 11, color: _muted, fontStyle: FontStyle.italic)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: snapshots.isEmpty
                ? const Center(child: Text('No control snapshots recorded yet.', style: TextStyle(color: _muted)))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: snapshots.length,
                    itemBuilder: (ctx, i) {
                      final s = snapshots[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat('EEEE, dd MMM yyyy — hh:mm a').format(s.timestamp), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _dark)),
                            const Divider(height: 20, color: _border),
                            _row('Overdue Tasks', '${s.overdueTasks}'),
                            _row('Mandatory Actions Not Completed', '${s.mandatoryActionsNotCompleted}'),
                            _row('Broken PTP Without Next Action', '${s.brokenPtpWithoutNextAction}'),
                            _row('Ownerless Exposure', fmt.format(s.ownerlessExposure)),
                            _row('L3 Cases Without Plan', '${s.l3CasesWithoutPlan}'),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
        ],
      ),
    );
  }
}
