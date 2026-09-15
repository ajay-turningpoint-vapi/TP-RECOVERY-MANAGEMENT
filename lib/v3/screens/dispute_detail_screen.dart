import 'package:flutter/material.dart';
import 'package:salesman_mobile/v3/screens/dispute_details_view.dart';
import 'package:salesman_mobile/v3/screens/dispute_assign_view.dart';

/// Pushable host for the full dispute-review flow (Details → Approve &
/// Assign). `DisputeDetailsView` / `DisputeAssignView` are normally swapped
/// in-place inside the Disputes tab; this wraps them in their own Scaffold
/// so the RE Tasks list / Approvals list can open the same screen directly.
class DisputeDetailScreen extends StatefulWidget {
  final String disputeId;
  const DisputeDetailScreen({super.key, required this.disputeId});

  @override
  State<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends State<DisputeDetailScreen> {
  bool _assign = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _assign
          ? DisputeAssignView(
              disputeId: widget.disputeId,
              onBack: () => setState(() => _assign = false),
              onConfirmed: () => Navigator.pop(context),
            )
          : DisputeDetailsView(
              disputeId: widget.disputeId,
              onBack: () => Navigator.pop(context),
              onApproveAssign: () => setState(() => _assign = true),
              onDecided: () => Navigator.pop(context),
            ),
    );
  }
}
