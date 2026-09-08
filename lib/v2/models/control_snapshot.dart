class ControlSnapshot {
  final String id;
  final DateTime timestamp;
  final int overdueTasks;
  final int mandatoryActionsNotCompleted;
  final int brokenPtpWithoutNextAction;
  final double ownerlessExposure;
  final int l3CasesWithoutPlan;

  ControlSnapshot({
    required this.id,
    required this.timestamp,
    required this.overdueTasks,
    required this.mandatoryActionsNotCompleted,
    required this.brokenPtpWithoutNextAction,
    required this.ownerlessExposure,
    required this.l3CasesWithoutPlan,
  });
}
