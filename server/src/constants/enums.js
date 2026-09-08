// Mirrors the enums used throughout the Flutter app (lib/v2/models) so the
// API surface stays a drop-in match for the existing client logic.

const ROLES = ['SALESPERSON', 'RECOVERY_EXECUTIVE', 'MANAGEMENT'];

const TASK_STATUS = ['pending', 'inProgress', 'completed', 'completedAwaitingVerification', 'closed'];

const TASK_TYPE = [
  'customerCall',
  'physicalVisit',
  'disputeResolution',
  'documentFollowUp',
  'financialTeamFollowUp',
  'customerDetailCorrection',
  'paymentVerification',
  'managementInstruction',
];

const PTP_STATUS = ['scheduled', 'pendingVerification', 'kept', 'partiallyKept', 'broken', 'financialSyncPending'];

const RECOVERY_STATE = ['Action Required', 'Waiting / Monitoring', 'RE Control'];

const ESCALATION_LEVEL = ['none', 'L1', 'L2', 'L3', 'L4'];

module.exports = { ROLES, TASK_STATUS, TASK_TYPE, PTP_STATUS, RECOVERY_STATE, ESCALATION_LEVEL };
