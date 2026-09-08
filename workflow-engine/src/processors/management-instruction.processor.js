import { createTask, appendAuditEvent, getCustomer } from '../store/repository.js';

export async function processManagementInstruction(job) {
  if (job.name !== 'assign') throw new Error(`Unknown management-instruction job name: "${job.name}"`);
  const { customerId, salesmanId, description, deadline, priority = 'Critical', actor } = job.data;
  if (!customerId || !salesmanId || !description || !deadline) {
    throw new Error('management-instruction assign job requires customerId, salesmanId, description, deadline');
  }
  getCustomer(customerId); // fail fast if unknown

  const task = createTask({
    type: 'managementInstruction',
    customerId,
    ownerId: salesmanId,
    deadline: new Date(deadline).toISOString(),
    priority,
    reason: description,
    status: 'pending',
    source: 'Management Instruction',
  });

  appendAuditEvent({
    customerId,
    type: 'RE_CREATED_INSTRUCTION',
    description: `Management instruction issued to ${salesmanId}: "${description}". This overrides the salesperson's own judgment on next action for this customer and must be completed and reported back by the deadline.`,
    actor: actor || 'Management',
    source: 'Management Instruction',
    relatedEntityType: 'Task',
    relatedEntityId: task.id,
  });

  return { taskId: task.id };
}
