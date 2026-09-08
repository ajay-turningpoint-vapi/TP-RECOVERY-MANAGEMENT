# TP-RMS — Complete Salesman Recovery Workflow Specification

> **Purpose:** This document defines the complete Version 1 salesman workflow for the Turning Point Recovery Management System (TP-RMS). It is written so an AI coding agent can use it as implementation context and preserve the intended business flow.

---

# 1. Core Business Model

TP-RMS is an **action and accountability layer around receivables**.

The system must separate three concepts:

1. **Recovery Queue** — Which customer should the salesman handle now?
2. **Recovery Action and Outcome** — What did the salesman do and what happened?
3. **Task** — What specific work must somebody complete by a deadline?

## Golden Rule

> If somebody must do something, it must become an owned obligation with a deadline and outcome; it must not remain only as a remark.

Another critical rule:

> Every active due customer must have a valid operational state, accountable owner, and next action.

Task completion does **not** automatically mean financial closure. Only trusted BUSY financial synchronization can change the financial truth.

---

# 2. The Main Salesman Daily Loop

```text
LOGIN
  ↓
MY RECOVERY TODAY
  ↓
Review urgent work and current workload
  ↓
START RECOVERY
  ↓
System selects highest-priority eligible customer
  ↓
Show customer + financial context + current state + primary next action
  ↓
Salesman performs recovery action
  ↓
Salesman records a valid outcome
  ↓
System applies business rules
  ├── PTP
  ├── Follow-up
  ├── Task
  ├── Payment verification
  ├── Dispute
  ├── Escalation
  └── Physical visit
  ↓
System guarantees a valid next operational state
  ↓
Next highest-priority customer
  ↓
Repeat
```

The salesman should not randomly choose work as the primary workflow. The system's Recovery Queue determines the next highest-priority customer.

---

# 3. Login Flow

## Step 1 — Authenticate

When the salesman logs in:

- Validate credentials/session.
- Confirm the user is active.
- Confirm the user role is `SALESPERSON`.
- Load only the customers currently assigned to that salesman.
- Historical activity remains attributable even after reassignment.

The salesman must not be able to access another salesman's active customer portfolio.

## Step 2 — Build today's operational workload

The system evaluates the salesman's assigned customers and open obligations, including:

- Management or critical instructions.
- Broken PTPs.
- Critical or overdue tasks.
- Critical or overdue physical visits.
- PTP due.
- Overdue follow-ups.
- High-value due.
- Other due.
- Upcoming due.
- Existing tasks assigned to the salesman.

## Step 3 — Show `My Recovery Today`

Example UI:

```text
GOOD MORNING, RAHUL

RECOVERY TARGET
₹12,50,000

EXPECTED COLLECTION TODAY
₹4,00,000

CUSTOMERS REQUIRING ACTION
25

URGENT
- 1 Management Instruction
- 2 Broken PTP
- 1 Physical Visit Due
- 3 Follow-ups Overdue

[ START RECOVERY ]

MY TASKS
- Visit ABC Traders — Due Today
- Customer detail correction — Due Today
- Management instruction — Due Today
```

`Recovery Target` and `Expected Collection` are separate concepts. A customer must not be counted multiple times merely because it has multiple invoices.

---

# 4. Recovery Queue

## Purpose

The Recovery Queue answers:

> **Which customer should the salesman handle now?**

A customer appears once in the operational queue even if that customer has many overdue invoices.

The system shows:

- Customer.
- Total Outstanding.
- Total Due.
- Oldest Overdue.
- Active PTP, if any.
- Current Recovery Status.
- One Primary Next Action.
- Reason why this customer/action has priority.

Example:

```text
CUSTOMER: ABC TRADERS

Total Outstanding: ₹5,00,000
Total Due: ₹4,00,000
Oldest Overdue: 45 days
Active PTP: ₹2,00,000 due yesterday

CURRENT RECOVERY STATUS
Action Required

PRIMARY NEXT ACTION
CALL CUSTOMER

Reason:
PTP matured and no confirmed payment has been received.

[ CALL CUSTOMER ]
[ VIEW CUSTOMER 360 ]
```

---

# 5. START RECOVERY

When the salesman clicks `START RECOVERY`:

1. The backend selects the highest-priority eligible customer.
2. The customer screen opens.
3. The salesman sees enough context to perform the action.
4. The primary action is made obvious.
5. The salesman performs the action.
6. The salesman must record a meaningful outcome.
7. Saving the outcome must leave the customer in a valid operational state.
8. The system then moves the salesman to the next highest-priority customer.

The salesman opening a customer is not completion. A meaningful action/outcome is required.

---

# 6. Outcome Model

After the salesman performs a recovery action, the system asks:

```text
WHAT HAPPENED?

[ Promise To Pay ]
[ Will Confirm ]
[ Payment Already Made ]
[ Dispute / Issue ]
[ Internal Action Required ]
[ No Answer ]
[ Unable To Commit ]
```

These outcomes are not all the same as tasks.

The outcome determines what the system must do next.

---

# 7. Flow: Promise To Pay (PTP)

## Example

Customer says:

> "I will pay ₹2,00,000 tomorrow at 3 PM."

The salesman records the structured PTP.

Example:

```text
Amount: ₹2,00,000
Date: Tomorrow
Time: 3:00 PM
Person Spoken To: Amit Shah
Payment Mode: Bank Transfer
```

The system creates:

```text
PTP STATUS = SCHEDULED
```

## PTP lifecycle

```text
Scheduled
  ↓
Due
  ↓
Awaiting Reconciliation
  ├── Kept
  ├── Partially Kept
  ├── Broken
  └── Financial Sync Pending
```

### Kept

Trusted financial reconciliation confirms the promised payment according to the applicable rules.

### Partially Kept

Example:

```text
Promise: ₹5,00,000
Received: ₹2,00,000
Remaining: ₹3,00,000
```

The PTP becomes `Partially Kept`.

The remaining ₹3,00,000 remains active in recovery and must receive a valid next action.

### Broken

No qualifying payment is found after trusted financial reconciliation.

The customer returns to recovery action and escalation rules may apply.

### Financial Sync Pending

If trusted BUSY financial data is not sufficiently fresh, the system must not falsely mark the PTP Broken.

## Critical implementation rule

The salesman must not manually mark a PTP as Kept or Broken.

---

# 8. Flow: Will Confirm

## Example

Customer says:

> "I need to check with my partner. Call me tomorrow at 11 AM."

The salesman selects `Will Confirm`.

The system must require a follow-up schedule.

```text
Follow-up Date: Tomorrow
Follow-up Time: 11:00 AM
Owner: Rahul
```

The customer cannot remain indefinitely in `Will Confirm`.

The system creates a future recovery obligation.

Example:

```text
CUSTOMER FOLLOW-UP

Customer: ABC Traders
Action: Follow up
Owner: Rahul
Due: Tomorrow 11:00 AM
```

At the due time, this customer becomes eligible for priority recovery work.

---

# 9. Flow: No Answer

## Example

The salesman calls the primary customer contact.

The customer does not answer.

The salesman selects:

```text
NO ANSWER
```

The system requires the configured proof and captures relevant metadata.

Example:

```text
Attempt Stage: Primary Contact
Proof: Screenshot required
Captured:
- Date
- Time
- Contact
- User
- Attempt stage
```

No Answer must not become an unlimited excuse for inactivity.

## No Answer progression

```text
Attempt 1
Primary Contact
  ↓
No Answer
  ↓
Next controlled contact action

Attempt 2
Alternate Contact / Carpenter
  ↓
No Answer
  ↓
Next controlled contact action

Attempt 3+
Additional controlled contact
  ↓
Configured non-response threshold reached
  ↓
PHYSICAL VISIT REQUIRED
```

Exact timing and threshold are configurable.

---

# 10. Flow: Physical Visit

A physical visit is a specific owned obligation.

Example:

```text
TASK TYPE: Physical Visit
Customer: ABC Traders
Owner: Rahul
Deadline: 22 August, 5 PM
Priority: High
Reason: Repeated No Answer
```

The salesman completes the visit and records the result.

Physical visit outcomes reuse the normal recovery outcome engine:

- Promise To Pay.
- Will Confirm.
- Dispute.
- Unable To Commit.

## Example

```text
Rahul visits ABC Traders.

Customer says:
"I will pay ₹1,50,000 on Friday."

Physical Visit Completed
  ↓
PTP Created
  ↓
Customer State = PTP Scheduled
```

A visit being completed does not mean the customer's money is recovered.

---

# 11. Flow: Payment Already Made

## Example

Customer says:

> "I already transferred the payment yesterday."

The salesman selects:

```text
PAYMENT ALREADY MADE
```

The salesman may record the claim and available evidence.

The system creates:

```text
PAYMENT CLAIM
STATUS: AWAITING VERIFICATION
```

The salesman cannot mark the customer as financially paid.

## Verification flow

```text
Payment Claim
  ↓
Awaiting Verification
  ↓
Trusted BUSY reconciliation
  ├── Payment found → Verified
  ├── Payment not found → Verification Failed
  │                       ↓
  │                    Return customer to recovery
  └── Financial data not fresh → Financial Sync Pending
```

Only trusted financial synchronization changes the financial truth.

---

# 12. Flow: Dispute / Customer Issue

## Example

Customer says:

> "I am not paying ₹80,000 because the material was damaged."

The salesman selects:

```text
DISPUTE
```

The salesman records the structured dispute.

Example:

```text
Disputed Amount: ₹80,000
Reason: Material damaged
Related Invoice: INV-123
Evidence: Photos/documents if applicable
```

The system creates:

```text
DISPUTE = RAISED
```

Then the dispute enters the approval/resolution workflow.

```text
Raised
  ↓
Awaiting RE Approval
  ↓
Approved / Resolution Pending
  ↓
In Resolution
  ↓
Awaiting Verification
  ↓
Resolved
  ↓
If still unpaid → Returned to Recovery
```

## Partial dispute example

```text
Total Due: ₹5,00,000
Approved Dispute: ₹80,000

Active Recovery: ₹4,20,000
Dispute Resolution: ₹80,000
```

The undisputed amount continues in active recovery.

The disputed amount must receive a specific resolution owner and deadline.

If the dispute is resolved but the money remains unpaid, that amount returns to recovery.

---

# 13. Flow: Internal Action Required

## Example

Customer says:

> "I will pay after you send the corrected ledger."

The salesman selects:

```text
INTERNAL ACTION REQUIRED
```

The system asks for the required dependency.

Examples:

- Ledger required.
- Invoice correction.
- Document required.
- Financial clarification.
- Customer detail correction.
- Other configured internal reason.

Example:

```text
Customer: ABC Traders
Problem: Ledger balance does not match customer records.
Required Action: Check/correct ledger.
Owner: Recovery Executive
Deadline: Today 4 PM
```

The system creates an owned task.

## Task lifecycle

```text
Pending
  ↓
In Progress
  ↓
Completed
or
Completed Awaiting Verification
  ↓
Closed

Reopened where required
```

`Overdue` is a calculated condition, not a separate workflow status.

## Critical rule after completion

Suppose the ledger task is completed.

```text
Task Completed
  ↓
Check whether money remains due
  ├── No → Customer may become financially clear only through trusted financial truth
  └── Yes
       ↓
     Automatically schedule/maintain valid recovery follow-up
       ↓
     Customer returns to an active recovery path
```

Completing internal work never silently ends recovery if money is still due.

---

# 14. Flow: Customer Detail Correction

## Example

The salesman visits a customer but finds the address is wrong.

The salesman records the relevant outcome.

The system creates a correction obligation or Recovery Executive attention.

Example:

```text
TASK TYPE: Customer Detail Correction
Customer: ABC Traders
Issue: Wrong address
Owner: Appropriate owner
Deadline: Configured/assigned
```

Wrong customer details must not close recovery.

After correction, the customer must continue through a valid recovery path if money remains due.

---

# 15. Flow: Unable To Commit

## Example

Customer says:

> "I cannot promise a payment date."

The salesman selects:

```text
UNABLE TO COMMIT
```

The system records a structured reason.

Example:

```text
Reason: Cash flow problem
Details: Customer expects funds next week but cannot commit to a date.
```

The customer must not disappear from recovery.

The system must create or maintain a valid next action.

Example:

```text
NEXT ACTION
Follow up after 3 days

Owner: Rahul
Deadline: 25 August, 11 AM
```

---

# 16. Flow: Partial Payment

Example:

```text
PTP Promise: ₹5,00,000
BUSY confirms receipt: ₹2,00,000
```

Result:

```text
PTP = PARTIALLY KEPT
Remaining Exposure = ₹3,00,000
```

The remaining money stays in recovery.

The system must determine the next action, for example:

```text
CONTACT CUSTOMER
Reason: ₹3,00,000 remains unpaid
```

---

# 17. Flow: Broken PTP

Example:

```text
Customer promised: ₹2,00,000
PTP date: 20 August
Trusted reconciliation: No qualifying payment
```

Result:

```text
PTP = BROKEN
```

Escalation progression may be:

```text
1st Broken PTP
→ L1: Salesperson Led

2nd Broken PTP
→ L2: Recovery Executive Supervision

3rd Broken PTP
→ L3: Recovery Executive Control
```

The customer remains in recovery.

Example:

```text
PRIMARY NEXT ACTION
Call Customer

Reason:
PTP Broken

Priority:
High
```

---

# 18. Flow: Management Instruction

Management can create a specific required action.

Example:

> "Rahul must personally visit ABC Traders today and report the outcome."

The system creates:

```text
TASK TYPE: Management Instruction
Customer: ABC Traders
Owner: Rahul
Deadline: Today, 5 PM
Instruction: Personally visit customer and report outcome.
```

The task remains open until the required action and outcome are properly recorded.

---

# 19. Recovery Queue vs My Tasks

These are different concepts.

## A. Recovery Queue

Question answered:

> Which customer should I work on now?

Example:

```text
1. ABC Traders
   Primary Action: Call Customer

2. XYZ Enterprises
   Primary Action: Follow-up

3. PQR Stores
   Primary Action: Contact Customer
```

A customer appears once with one primary action.

## B. My Tasks

Question answered:

> What specific obligation has been assigned to me and must be completed by a deadline?

Examples:

```text
Physical Visit
ABC Traders
Due Today 3 PM

Customer Detail Correction
XYZ Enterprises
Due Today 4 PM

Management Instruction
PQR Stores
Due Today
```

The explicit Version 1 task types are:

1. Customer Call.
2. Physical Visit.
3. Dispute Resolution.
4. Document Follow-Up.
5. Financial Team Follow-Up.
6. Customer Detail Correction.
7. Payment Verification.
8. Management Instruction.

The implementation may use additional operational categories such as Internal Action or Recovery Follow-Up only if they are deliberately modeled as subtypes/source categories rather than silently changing the defined business taxonomy.

---

# 20. What Is a Task?

A task should represent a specific obligation requiring accountability.

Recommended conceptual definition:

> A Task is a specific piece of work that requires a specific owner to perform an action for a customer or recovery case before a defined deadline, with tracked status and outcome/evidence where required.

A task should contain at minimum:

```text
Task ID
Task Type
Customer
Related Invoice(s), if applicable
Source / Trigger
Owner
Assigned By or System
Priority
Deadline
Status
Outcome
Evidence Required?
Verification Required?
Created At
Completed At
Task History
```

## Task status model

```text
Pending
→ In Progress
→ Completed
or
Completed Awaiting Verification
→ Closed

Reopened where required
```

Overdue is calculated from the deadline and completion/closure state.

An extension request must contain:

- New date.
- New time.
- Reason.

The original deadline remains effective until the extension is approved.

If a task owner becomes inactive, reassignment is required.

---

# 21. What Is NOT Automatically a Task?

Do not confuse events with tasks.

## Notification

Example:

> "You have 10 overdue tasks."

This is not a task.

Reading or acknowledging the notification does not complete the underlying obligation.

## Opening a customer

Opening Customer 360 is not task completion.

## Financial receipt

A BUSY receipt is a financial event, not a salesman task.

## PTP record

A PTP is its own business object with its own lifecycle. It may trigger future recovery work but should not automatically be treated as the same database entity as a generic task.

## Dashboard alert

An alert informs. It does not represent completion of work.

---

# 22. Complete Example — One Salesman's Day

Assume:

```text
Salesman: Rahul
Date: 21 August
```

## 9:00 AM — Login

Rahul sees:

```text
MY RECOVERY TODAY

Recovery Target: ₹12,50,000
Expected Collection: ₹4,00,000
Customers requiring action: 25

Urgent:
- 1 Management Instruction
- 2 Broken PTP
- 1 Physical Visit Due
```

Rahul clicks:

```text
START RECOVERY
```

---

## Customer 1 — ABC Traders

Context:

```text
Outstanding: ₹5,00,000
Reason: Broken PTP
Primary Action: Call Customer
```

Rahul calls.

Customer says:

> "I can pay ₹1,00,000 tomorrow."

Rahul records a PTP.

```text
Amount: ₹1,00,000
Date: Tomorrow
Time: 2 PM
Mode: Bank Transfer
```

System:

```text
PTP = SCHEDULED
```

The system moves to the next customer.

---

## Customer 2 — XYZ Enterprises

Context:

```text
Outstanding: ₹3,00,000
Primary Action: Follow-up
```

Customer says:

> "Send me the latest ledger first."

Rahul selects:

```text
INTERNAL ACTION REQUIRED
```

System creates:

```text
TASK TYPE: Financial Team Follow-Up
Owner: Recovery Executive
Deadline: Today 4 PM
```

Later:

```text
Ledger task completed
  ↓
₹3,00,000 still due
  ↓
Recovery follow-up remains/gets scheduled
```

---

## Customer 3 — PQR Stores

Rahul calls.

No answer.

```text
Attempt: Primary Contact
Proof: Recorded/uploaded as required
```

System:

```text
NEXT CONTROLLED ACTION
Alternate Contact
Tomorrow 10 AM
```

---

## Customer 4 — DEF Traders

Configured non-response threshold has already been reached.

System:

```text
PRIMARY ACTION
PHYSICAL VISIT
```

Rahul visits.

Customer says:

> "We have an issue with ₹50,000 worth of material."

Rahul records:

```text
DISPUTE
Amount: ₹50,000
```

System:

```text
₹50,000 → Dispute workflow
Remaining eligible due amount → Active recovery
```

---

## Customer 5 — GHI Stores

Customer says:

> "I already paid yesterday."

Rahul records:

```text
PAYMENT ALREADY MADE
```

System:

```text
PAYMENT CLAIM
STATUS = AWAITING VERIFICATION
```

Rahul cannot mark the customer as paid.

---

## Customer 6 — JKL Enterprises

Customer says:

> "Call me next Monday. I need approval."

Rahul records:

```text
WILL CONFIRM
```

System requires:

```text
Follow-up Date: Monday
Follow-up Time: 11 AM
Owner: Rahul
```

A future recovery obligation is created.

---

# 23. End-of-Day Concept

The system may show an operational summary such as:

```text
TODAY'S ACTIVITY

Customers Handled: 18 / 25
Meaningful Actions: 18
PTP Created: 5
PTP Amount: ₹4,50,000
Physical Visits: 2
Disputes Raised: 1
Internal Dependencies: 3
Payment Claims: 2
No Answer: 4
Tasks Completed: 3
Tasks Overdue: 1
Remaining Recovery Work: 7 Customers
```

This is reporting only. It must not alter the underlying workflow or treat notifications as completion.

---

# 24. AI Implementation Rules

The following rules are mandatory implementation logic.

```text
WHEN SALESMAN LOGS IN:

1. Authenticate the user.

2. Confirm the user is active and has SALESPERSON role.

3. Load only customers assigned to that salesman.

4. Load and calculate:
   - Recovery Queue
   - Open Tasks
   - Overdue Tasks
   - Physical Visits
   - PTP Due
   - Broken PTP
   - Scheduled Follow-ups
   - Management Instructions

5. Show My Recovery Today.

WHEN SALESMAN CLICKS START RECOVERY:

6. Select the highest-priority eligible customer.

7. Show:
   - Customer financial summary
   - Current Recovery State
   - One Primary Next Action
   - Reason for the action

8. Salesman performs the recovery action.

9. Salesman must record a valid meaningful outcome.

OUTCOME RULES:

10. Promise To Pay:
    - Create structured PTP.
    - PTP enters Scheduled.
    - At maturity, use trusted financial reconciliation.
    - Result is Kept, Partially Kept, Broken, or Financial Sync Pending.
    - Salesman cannot manually mark Kept/Broken.

11. Will Confirm:
    - Require follow-up date/time.
    - Create/maintain future recovery obligation.

12. Payment Already Made:
    - Create Payment Claim.
    - Set Awaiting Verification.
    - Trusted BUSY reconciliation verifies or fails the claim.
    - If verification fails, return customer to recovery.
    - If financial data is stale/unavailable, use Financial Sync Pending protection.

13. Dispute:
    - Create dispute record.
    - Route through Recovery Executive approval.
    - Approved dispute requires resolution owner/deadline.
    - Eligible undisputed amount continues in recovery.
    - Resolved but unpaid exposure returns to recovery.

14. Internal Action Required:
    - Create appropriate dependency/task.
    - Assign owner.
    - Set deadline.
    - Track completion/verification.
    - If money remains due, ensure valid next recovery follow-up.

15. No Answer:
    - Require configured evidence.
    - Record attempt stage.
    - Move through controlled contact sequence.
    - At configured threshold, create/require Physical Visit.

16. Physical Visit:
    - Assign to responsible owner according to policy.
    - Record visit outcome.
    - Reuse PTP / Will Confirm / Dispute / Unable To Commit logic.

17. Unable To Commit:
    - Record structured reason.
    - Determine and store valid future next action.

AFTER EVERY OUTCOME:

18. Update Customer Recovery State.

19. Update timeline/event history with source attribution.

20. Create/update task, follow-up, escalation, PTP, dispute, or verification state as required.

21. Never leave due exposure without a valid owner and operational next action.

22. Task completion does not imply financial closure.

23. Only trusted BUSY synchronization can change authoritative financial exposure.

24. Move to the next highest-priority eligible customer.
```

---

# 25. Final Conceptual Architecture

```text
SALESMAN
   │
   ▼
MY RECOVERY TODAY
   │
   ├──────────────► MY TASKS
   │                   │
   │                   ▼
   │              Complete specific
   │              owned obligations
   │
   ▼
RECOVERY QUEUE
   │
   ▼
PRIMARY NEXT ACTION
   │
   ▼
CUSTOMER INTERACTION
   │
   ▼
RECORD OUTCOME
   │
   ├── PTP
   │      ↓
   │   Reconciliation lifecycle
   │
   ├── Will Confirm
   │      ↓
   │   Scheduled recovery follow-up
   │
   ├── Payment Already Made
   │      ↓
   │   Payment verification
   │
   ├── Dispute
   │      ↓
   │   Approval + resolution
   │
   ├── Internal Action Required
   │      ↓
   │   Owned task/dependency
   │
   ├── No Answer
   │      ↓
   │   Controlled contact sequence
   │      ↓
   │   Physical Visit when threshold reached
   │
   └── Unable To Commit
          ↓
       Valid future next action
          │
          ▼
SYSTEM VALIDATES THAT CUSTOMER HAS:
- Current recovery state
- Accountable owner
- Valid next action
          │
          ▼
NEXT CUSTOMER
```

---

# 26. Non-Negotiable System Principles

1. **One customer appears once in the Recovery Queue with one primary action.**
2. **Recovery Queue, Outcome, and Task are separate concepts.**
3. **A notification is not a task.**
4. **Reading an alert does not complete work.**
5. **A task requires ownership, deadline, and tracked outcome.**
6. **Overdue is calculated, not manually selected as a workflow status.**
7. **A due customer must not silently disappear without an owner and next action.**
8. **Task completion does not equal payment collection.**
9. **PTP, Task, Dispute, Payment Claim, and Escalation have separate state machines.**
10. **Only trusted BUSY financial synchronization can change financial truth.**
11. **The system must preserve historical actor attribution and audit history.**
12. **Automated rules must avoid duplicate business transactions when the same action is retried.**
13. **The system must create a coherent next operational state after every meaningful event.**

---

# 27. Final Rule for the Coding AI

> **Do not implement TP-RMS as a generic CRM task manager.**

The correct mental model is:

```text
RECOVERY QUEUE
= Who needs attention now?

RECOVERY ACTION
= What did the salesman do?

OUTCOME
= What happened?

TASK
= What specific work is somebody accountable to complete by a deadline?

CUSTOMER RECOVERY STATE
= What is the customer's current operational position?

PRIMARY NEXT ACTION
= What must happen next?

BUSY FINANCIAL DATA
= Authoritative source of financial truth.
```

At every moment, for every active receivable, the system should be able to answer:

```text
What is the current financial exposure?
What is the current recovery state?
What was the last meaningful action?
What is the next action?
Who is accountable?
Is there an active PTP, dispute, task, payment claim, or escalation?
What happens next?
```



---

# 28. Detailed Scenario Examples for AI Understanding

This section contains complete end-to-end examples. These examples are intentionally repetitive and explicit so an AI coding agent can understand exactly **what the salesman sees, what he does, what object the system creates, and what happens next**.

## Example 1 — First Login and First Customer

### Situation

```text
Salesman: Rahul
Assigned Customers: 250
Customers requiring action today: 25
```

### Rahul logs in

The system calculates:

```text
Broken PTP: 2
PTP Due Today: 1
Overdue Follow-ups: 3
Physical Visits Due: 1
Management Instructions: 1
Open Tasks: 5
```

Rahul sees:

```text
MY RECOVERY TODAY

25 Customers Require Attention

URGENT
🔴 1 Management Instruction
🔴 2 Broken PTP
🔴 1 Physical Visit Due
🟠 3 Overdue Follow-ups

[ START RECOVERY ]
```

Rahul clicks `START RECOVERY`.

The system selects ABC Traders because it has the highest current priority.

```text
ABC TRADERS

Outstanding: ₹5,00,000
Due: ₹4,00,000
Oldest Overdue: 45 days

Current State:
PTP BROKEN

Primary Next Action:
CALL CUSTOMER

Reason:
Customer promised payment yesterday.
No qualifying payment has been confirmed.
```

Rahul calls the customer.

He cannot simply press `Next Customer` without recording what happened.

---

## Example 2 — PTP Created, Then Fully Kept

### Customer interaction

Customer says:

> "I will pay ₹2,00,000 tomorrow before 3 PM."

Rahul records:

```text
Outcome: Promise To Pay

Amount: ₹2,00,000
Promise Date: 22 August
Promise Time: 3:00 PM
Contact Person: Amit Shah
Payment Mode: Bank Transfer
```

### System state

```text
PTP ID: PTP-1001
Status: SCHEDULED
Customer State: Waiting for PTP / Monitoring
Next Important Event: 22 August, 3 PM
```

### At maturity

After the PTP becomes due:

```text
System checks trusted BUSY data
```

BUSY shows:

```text
Receipt: ₹2,00,000
Customer: ABC Traders
```

System result:

```text
PTP STATUS = KEPT
Outstanding is refreshed from BUSY
```

If the customer still has money due, the customer remains operationally active according to the next recovery rules.

---

## Example 3 — PTP Partially Kept

Customer promises:

```text
₹5,00,000
```

At maturity BUSY confirms:

```text
₹2,00,000 received
```

System calculates:

```text
Promised Amount: ₹5,00,000
Received Amount: ₹2,00,000
Remaining Amount: ₹3,00,000
```

Result:

```text
PTP STATUS = PARTIALLY KEPT

Customer is NOT closed.
₹3,00,000 remains active.
```

The system creates/maintains:

```text
Primary Next Action:
Contact Customer

Reason:
Partial payment received.
₹3,00,000 remains unpaid.
```

The system must never treat the full ₹5,00,000 as recovered.

---

## Example 4 — PTP Broken

Customer promised:

```text
Amount: ₹2,00,000
Date: 20 August
```

The promise date passes.

Trusted reconciliation finds:

```text
Received: ₹0
```

System:

```text
PTP STATUS = BROKEN
```

Customer state changes:

```text
Action Required
```

Priority increases according to the configured recovery rules.

The next queue item may show:

```text
ABC TRADERS

🔴 HIGH PRIORITY

Reason:
PTP of ₹2,00,000 was broken.

Primary Next Action:
CALL CUSTOMER
```

Rahul calls again and records a new outcome.

---

## Example 5 — Will Confirm

Customer says:

> "I need approval from my partner. Call me tomorrow at 11 AM."

Rahul selects:

```text
Outcome: WILL CONFIRM
```

The system does not allow saving without scheduling the next contact.

Required:

```text
Follow-up Date: 22 August
Follow-up Time: 11:00 AM
Owner: Rahul
```

Created object:

```text
Recovery Follow-up
Customer: ABC Traders
Owner: Rahul
Due: 22 August, 11 AM
```

At 11 AM the customer becomes eligible for the Recovery Queue.

Rahul calls.

Possible next outcomes:

```text
PTP
Will Confirm again, subject to business rules
Dispute
Payment Already Made
Unable To Commit
```

The customer must not stay forever in `Will Confirm`.

---

## Example 6 — No Answer Progression

### Attempt 1

Rahul calls:

```text
Contact: Primary Number
Outcome: No Answer
```

System requires the configured evidence.

System records:

```text
Attempt Number: 1
Contact Type: Primary
Date/Time: Captured
Evidence: Captured/Uploaded as required
```

System schedules the next controlled attempt.

### Attempt 2

Rahul contacts an alternate number.

```text
Outcome: No Answer
Attempt Number: 2
```

### Attempt 3

Rahul contacts another configured contact.

```text
Outcome: No Answer
Attempt Number: 3
```

Configured threshold is reached.

System creates:

```text
TASK

Type: Physical Visit
Customer: ABC Traders
Owner: Rahul
Priority: High
Deadline: Tomorrow 5 PM
Reason: Non-response threshold reached
```

The customer is no longer simply shown as endless `No Answer`.

---

## Example 7 — Physical Visit Ends in PTP

Rahul opens:

```text
MY TASKS

🔴 Physical Visit
Customer: ABC Traders
Deadline: Today 5 PM
```

Rahul visits the customer.

Customer says:

> "I can pay ₹1,50,000 on Friday."

Rahul records:

```text
Visit Outcome: Promise To Pay
Amount: ₹1,50,000
Date: Friday
```

System:

```text
Physical Visit Task → Completed
PTP → Scheduled
Customer State → Waiting for PTP / Monitoring
```

Important:

```text
Visit completed ≠ Payment collected
```

The visit task is complete because Rahul performed the visit and recorded the required outcome. Financial recovery remains dependent on payment verification.

---

## Example 8 — Physical Visit Ends in Dispute

Rahul visits DEF Traders.

Customer says:

> "I am disputing ₹50,000 because the material was damaged."

Rahul records:

```text
Visit Outcome: Dispute
Disputed Amount: ₹50,000
Reason: Material damaged
```

System:

```text
Physical Visit Task → Completed
Dispute → Raised
Dispute → Awaiting Approval
```

If total due was ₹5,00,000:

```text
₹4,50,000 → Continues in active recovery
₹50,000 → Dispute workflow
```

---

## Example 9 — Payment Already Made but Not Yet Verified

Customer says:

> "I paid ₹1,00,000 yesterday."

Rahul selects:

```text
Outcome: Payment Already Made
```

Rahul attaches available proof.

System creates:

```text
Payment Claim

Claimed Amount: ₹1,00,000
Status: Awaiting Verification
```

The customer must not immediately be marked `Paid`.

### Case A — BUSY finds payment

```text
BUSY Receipt: ₹1,00,000
```

Result:

```text
Payment Claim = Verified
Financial exposure = refreshed from BUSY
```

### Case B — BUSY does not find payment

```text
Payment Claim = Verification Failed
```

The customer returns to active recovery.

### Case C — BUSY data is stale

```text
Payment Claim = Financial Sync Pending
```

The system waits for reliable financial synchronization rather than falsely deciding the payment status.

---

## Example 10 — Internal Action Required: Ledger

Customer says:

> "Send me the updated ledger and then I will discuss payment."

Rahul selects:

```text
Outcome: Internal Action Required
```

He records:

```text
Required Action: Updated Ledger
Customer: XYZ Enterprises
```

System creates:

```text
TASK

Type: Financial Team Follow-Up
Customer: XYZ Enterprises
Owner: Recovery Executive
Deadline: Today 4 PM
Status: Pending
```

The Recovery Executive completes the task:

```text
Status: Completed
Outcome: Updated ledger sent to customer
```

System checks:

```text
Is money still due?
YES: ₹3,00,000
```

Therefore:

```text
Customer cannot disappear.

Next Recovery Action:
Follow up with customer

Owner: Rahul
Due: Configured date/time
```

---

## Example 11 — Wrong Address

Rahul goes to the customer's listed address.

The business is not there.

Rahul records:

```text
Visit Outcome: Wrong Address
```

System creates:

```text
TASK

Type: Customer Detail Correction
Customer: ABC Traders
Issue: Address incorrect
Owner: Appropriate owner
Deadline: Configured
```

After the address is corrected:

```text
Customer details updated
  ↓
If money remains due
  ↓
Recovery resumes
```

Wrong address must not be treated as recovery completion.

---

## Example 12 — Customer Cannot Commit

Customer says:

> "My business is facing cash flow problems. I cannot give you a payment date."

Rahul selects:

```text
Outcome: Unable To Commit
Reason: Cash Flow Problem
Notes: Customer expects funds next week but cannot commit.
```

The system must not leave:

```text
Status: Unable To Commit
Next Action: None
```

Instead:

```text
Current State: Unable To Commit
Next Action: Follow up
Owner: Rahul
Deadline: 25 August, 11 AM
```

---

## Example 13 — Management Instruction

Management creates:

```text
Instruction:
Rahul must personally visit ABC Traders today and obtain a clear payment position.
```

System creates:

```text
TASK

Type: Management Instruction
Owner: Rahul
Customer: ABC Traders
Deadline: Today 5 PM
Priority: Critical
```

Rahul performs the visit.

He must record the result.

Example:

```text
Outcome: Will Confirm
Customer asks for follow-up tomorrow at 10 AM
```

System:

```text
Management Instruction Task → Completed
New Recovery Follow-up → Scheduled
```

Completing the management task does not mean the receivable is closed.

---

## Example 14 — Task vs Recovery Queue

Rahul has this task:

```text
TASK:
Physical Visit ABC Traders
Due: Today 3 PM
```

Separately, the Recovery Queue contains:

```text
XYZ Enterprises
Primary Next Action: Call Customer
Reason: Follow-up overdue
```

These are different.

Rahul may first need to complete the critical physical visit task because of priority.

After that:

```text
START/NEXT RECOVERY
  ↓
System selects XYZ Enterprises
```

Do not merge every customer queue item into the Task table.

---

## Example 15 — Same Customer Has Multiple Things Happening

ABC Traders has:

```text
Outstanding: ₹10,00,000
Broken PTP: ₹2,00,000
Approved Dispute: ₹1,00,000
Open Physical Visit: Due today
Payment Claim: ₹50,000 awaiting verification
```

The system must not create five duplicate customer rows in the Recovery Queue.

Instead:

```text
RECOVERY QUEUE

ABC TRADERS
Primary Next Action: Physical Visit
Reason: Critical visit due today
```

Customer 360 can show all related objects:

```text
Financial Exposure
PTPs
Disputes
Payment Claims
Tasks
History
Contacts
Timeline
```

The queue shows one primary action while Customer 360 shows the complete context.

---

## Example 16 — Complete Day from Login to End of Day

### 9:00 AM

Rahul logs in.

```text
Customers requiring action: 25
Open tasks: 5
Broken PTP: 2
```

### 9:05 AM — Customer A

```text
ABC Traders
Action: Call
```

Outcome:

```text
PTP ₹1,00,000 tomorrow
```

System schedules PTP monitoring.

### 9:20 AM — Customer B

```text
XYZ Enterprises
Action: Follow-up
```

Outcome:

```text
Needs ledger
```

System creates internal dependency task.

### 9:40 AM — Customer C

```text
PQR Stores
Action: Call
```

Outcome:

```text
No Answer
```

System records attempt and schedules next controlled contact.

### 10:00 AM — Critical Task

```text
Physical Visit: DEF Traders
```

Rahul visits.

Outcome:

```text
Dispute ₹50,000
```

System starts dispute workflow.

### 11:30 AM — Customer E

```text
GHI Stores
Action: Contact
```

Customer claims payment already made.

System creates:

```text
Payment Claim → Awaiting Verification
```

### 1:00 PM — Customer F

```text
JKL Enterprises
```

Outcome:

```text
Will Confirm
Follow-up: Monday 11 AM
```

### 4:00 PM — Ledger Task Completed by RE

System sees:

```text
XYZ still owes ₹3,00,000
```

System schedules:

```text
Recovery Follow-up for Rahul
```

### End of Day

```text
Customers Handled: 18
PTPs Created: 5
PTP Value: ₹4,50,000
Physical Visits Completed: 2
Disputes Raised: 1
Payment Claims: 2
Internal Dependencies Created: 3
No Answer Attempts: 4
Tasks Completed: 3
Remaining Recovery Customers: 7
```

---

# 29. Example Decision Matrix

| Salesman Outcome | Example Customer Statement | System Creates/Updates | What Happens Next |
|---|---|---|---|
| Promise To Pay | "I will pay ₹2 lakh tomorrow." | PTP | Wait for maturity and financial reconciliation |
| Partial PTP Payment | ₹5 lakh promised, ₹2 lakh received | PTP = Partially Kept | Remaining amount stays in recovery |
| Broken PTP | No payment found after due date | PTP = Broken | Customer becomes high-priority recovery work |
| Will Confirm | "Call me tomorrow at 11." | Scheduled follow-up | Customer returns when follow-up is due |
| No Answer | Customer does not answer | Contact attempt | Continue controlled contact sequence |
| Repeated No Answer | Threshold reached | Physical Visit Task | Assigned owner must visit |
| Payment Already Made | "I paid yesterday." | Payment Claim | Verify using trusted financial data |
| Dispute | "₹50,000 is disputed." | Dispute | Approval + resolution workflow |
| Internal Action | "Send corrected ledger." | Owned task/dependency | Complete work, then continue recovery if money remains |
| Wrong Address | Customer not found at address | Detail correction task | Correct details, then continue recovery |
| Unable To Commit | "I cannot promise a date." | Structured outcome + next action | Scheduled future recovery action |
| Management Instruction | "Visit customer today." | Management Instruction Task | Perform action and record outcome |

---

# 30. Simplified Object Relationship Example

Use this mental model:

```text
Customer
  │
  ├── Financial Exposure
  │
  ├── Recovery State
  │
  ├── Primary Next Action
  │
  ├── Recovery Actions
  │      └── Outcomes
  │
  ├── PTPs
  │
  ├── Follow-ups
  │
  ├── Tasks
  │      ├── Physical Visit
  │      ├── Document Follow-Up
  │      ├── Financial Team Follow-Up
  │      ├── Customer Detail Correction
  │      └── Management Instruction
  │
  ├── Disputes
  │
  ├── Payment Claims
  │
  └── Timeline / Audit History
```

The same customer can have multiple related objects, but the Recovery Queue should still determine one primary action at a time.

---

# 31. Final End-to-End Example for Implementation Testing

Create this test scenario:

```text
Customer: ABC Traders
Assigned Salesman: Rahul
Total Outstanding: ₹10,00,000
Due Amount: ₹8,00,000
```

### Day 1

Rahul calls.

```text
Outcome: PTP
Amount: ₹3,00,000
Due Date: Tomorrow
```

### Day 2

BUSY shows only ₹1,00,000 received.

Expected:

```text
PTP = Partially Kept
Remaining PTP exposure = ₹2,00,000
Customer still active
Next action required
```

### Day 3

Rahul calls.

Customer says:

> "The remaining amount has an invoice issue."

Rahul raises:

```text
Dispute = ₹2,00,000
```

Expected:

```text
Dispute workflow begins
Remaining eligible non-disputed due continues in recovery
```

### Day 4

Dispute is resolved, but customer still has not paid the disputed ₹2,00,000.

Expected:

```text
Dispute resolution is complete
BUT financial exposure remains
Customer returns to recovery
New valid next action exists
```

### Day 5

Rahul attempts contact repeatedly.

```text
No Answer → Attempt 1
No Answer → Attempt 2
No Answer → Attempt 3
```

Expected:

```text
Physical Visit Required
Owned task created
```

### Day 6

Rahul completes the visit.

Customer says:

> "Send me an updated ledger."

Expected:

```text
Physical Visit Task = Completed
Financial/Document Follow-Up Task = Created
Owner + Deadline assigned
```

### Day 7

Ledger is sent.

Expected:

```text
Internal Task = Completed
Money still due = YES
Customer automatically remains/returns to recovery path
Follow-up assigned to Rahul
```

This scenario should pass without the customer ever becoming operationally invisible.

---

# 32. Absolute Implementation Test

For every active due customer, run this check after every workflow transition:

```text
IF customer has active due exposure:

    VERIFY:
    1. Customer has a valid Recovery State.
    2. Customer has an accountable owner.
    3. Customer has a valid Primary Next Action
       OR a valid scheduled state such as active PTP,
       pending verification, approved dispute resolution, etc.
    4. No workflow event falsely marks the financial exposure as closed.
    5. All required tasks have owner, deadline and status.
    6. Customer remains traceable in Customer 360 and timeline.
```

If any check fails:

```text
DO NOT silently remove the customer from operational management.
```

The system must either generate the required next action or surface the exception for controlled handling.
