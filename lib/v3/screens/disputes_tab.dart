import 'package:flutter/material.dart';
import 'package:salesman_mobile/v3/screens/disputes_list_view.dart';
import 'package:salesman_mobile/v3/screens/dispute_details_view.dart';
import 'package:salesman_mobile/v3/screens/dispute_assign_view.dart';

/// Disputes lives as one page inside the RE bottom-nav IndexedStack (see
/// ReScaffoldV3). List → Details → Approve & Assign are swapped as *internal*
/// state here rather than pushed as new routes, so the bottom nav bar stays
/// visible across the whole flow — matching the reference design.
class DisputesTab extends StatefulWidget {
  const DisputesTab({super.key});

  @override
  State<DisputesTab> createState() => _DisputesTabState();
}

enum _DisputeView { list, details, assign }

class _DisputesTabState extends State<DisputesTab> {
  _DisputeView _view = _DisputeView.list;
  String? _selectedId;

  void _openDetails(String id) => setState(() {
        _selectedId = id;
        _view = _DisputeView.details;
      });

  void _backToList() => setState(() {
        _selectedId = null;
        _view = _DisputeView.list;
      });

  void _openAssign() => setState(() => _view = _DisputeView.assign);

  void _backToDetails() => setState(() => _view = _DisputeView.details);

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _DisputeView.list:
        return DisputesListView(onOpenDispute: _openDetails);
      case _DisputeView.details:
        return DisputeDetailsView(
          disputeId: _selectedId!,
          onBack: _backToList,
          onApproveAssign: _openAssign,
          onDecided: _backToList,
        );
      case _DisputeView.assign:
        return DisputeAssignView(
          disputeId: _selectedId!,
          onBack: _backToDetails,
          onConfirmed: _backToList,
        );
    }
  }
}
