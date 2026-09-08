# TP-RMS --- Recovery Executive (RE) Complete Flow & Build Specification

**Version:** 1.0\
**Source:** `TP_RMS_Master_Build_Book_v1.0(1).pdf` + the agreed TP-RMS
recovery workflow\
**Purpose:** This file is an AI/developer-ready specification for
building the complete Recovery Executive (RE) module.

> **Important source rule:** Where the Master Build Book explicitly
> defines a requirement, treat it as locked. Where it leaves thresholds,
> timings, integrations, or implementation details configurable/TBD, do
> not hard-code a new business rule. Examples in this document are
> illustrative unless explicitly marked as locked.

------------------------------------------------------------------------

# 1. Recovery Executive --- Role Definition

The Recovery Executive is the company-wide recovery control role.

The RE is responsible for:

-   Company-wide recovery visibility
-   Recovery supervision
-   Approvals
-   Recovery interventions
-   Task and escalation control
-   Salesmen Needing Attention
-   Company Recovery Queue
-   Customer 360 investigation
-   Dispute control
-   Financial-team dependencies in V1 because there is no Accounts login
-   Monitoring workflow exceptions
-   Escalating serious cases to Management

The RE is **not** the accounting source of truth.

**BUSY remains the financial source of truth.**

TP-RMS owns the operational recovery layer:

-   Recovery actions
-   Recovery outcomes
-   PTPs
-   Tasks
-   Disputes
-   Payment claims
-   Escalations
-   Accountability
-   Communication history
-   Risk/score views
-   Recovery state
-   Next action

------------------------------------------------------------------------

# 2. V1 Role Boundary

V1 contains four roles:

1.  Salesperson
2.  Recovery Executive
3.  Senior Management / Owner
4.  System Administrator

V1 does **not** contain:

-   Accounts login
-   Branch Manager login

The RE has company-wide recovery visibility.

Management has company-wide management visibility.

Admin has technical/system authority and does not automatically become a
recovery decision-maker.

Every material intervention, approval, reassignment, escalation,
override, correction, and configuration change must be auditable.

------------------------------------------------------------------------

# 3. The Difference Between Salesperson and RE

## Salesperson Mental Model

> "Which customer should I recover next?"

``` text
My Portfolio
    ↓
My Recovery Today
    ↓
Start Recovery
    ↓
Customer
    ↓
Action
    ↓
Outcome
    ↓
Next Action
```

## RE Mental Model

> "Where is recovery failing, who needs attention, and what intervention
> is required?"

``` text
Company Recovery
    ↓
Exceptions / Attention
    ↓
Salesman / Customer / Task / Dispute / Escalation
    ↓
Customer 360
    ↓
Authorized Intervention
    ↓
Owner + Deadline + Next Action
    ↓
Monitor
```

The RE should therefore be built as an **operational control system**,
not merely an analytics dashboard.

------------------------------------------------------------------------

# 4. RE Login Flow

``` text
RE opens TP-RMS
      ↓
Login
      ↓
Authenticate user
      ↓
Validate active user
      ↓
Validate role = Recovery Executive
      ↓
Create/validate session
      ↓
Load company-wide authorized recovery data
      ↓
Open Control Dashboard
```

Individual user accounts are mandatory.

Shared RE accounts are not allowed.

Backend authorization is mandatory. Hiding buttons in the frontend is
not sufficient security.

------------------------------------------------------------------------

# 5. First Screen After Login --- Control Dashboard

The RE should land on:

**Control Dashboard**

The first question should be:

> "What requires my intervention today?"

The dashboard should surface:

-   My Actions
-   Salesmen Needing Attention
-   Today Collection / Recovery control
-   Customer Exceptions
-   Approval Inbox
-   Broken PTP
-   Overdue Tasks
-   Disputes
-   Escalations
-   Owner Mapping Required
-   No Valid Next Action
-   Financial Sync / Data Freshness

The exact dashboard cards can be configured during UI design, but every
material metric must be explainable and drillable.

------------------------------------------------------------------------

# 6. Recommended RE Navigation

``` text
TP-RMS
│
├── Control Dashboard
│
├── Approval Inbox
│
├── Salesmen Needing Attention
│
├── Company Recovery Queue
│
├── Disputes
│
├── Escalations
│
├── My Tasks
│
├── Customer 360
│
└── Notifications
```

The Master Build Book explicitly defines the core RE screens around
Control Dashboard, Approval Inbox, Salesmen Needing Attention, Company
Recovery Queue, Disputes, My Tasks and Customer 360.

`Escalations` can be a separate menu item or an integrated control view,
provided RE escalation control is fully available.

------------------------------------------------------------------------

# 7. Control Dashboard --- Detailed Behavior

The dashboard should answer:

1.  What requires my attention?
2.  Which salesmen need attention?
3.  Which customers are stuck?
4.  Which PTPs are failing?
5.  Which tasks are overdue?
6.  Which disputes need action?
7.  Which escalations need intervention?
8.  Is any active due customer missing an owner?
9.  Is any active due customer missing a valid next action?
10. Is financial data fresh enough for decisions?

Example:

``` text
---------------------------------------------------------
RECOVERY EXECUTIVE
Good Morning, Rajesh
Last BUSY Sync: 10:32 AM
---------------------------------------------------------

MY ACTIONS
---------------------------------------------------------
Approvals Pending                  7
Overdue RE Tasks                   4
Escalations Requiring Action       3
Disputes Requiring Action          5
Financial Dependencies             2

TODAY RECOVERY CONTROL
---------------------------------------------------------
Recovery Target                    ₹85,00,000
Expected Collection                ₹32,00,000
Collected Today                    ₹18,50,000

EXCEPTIONS
---------------------------------------------------------
Broken PTP                         8
No Follow-Up                       3
Owner Mapping Required             1
No Valid Next Action               2
Critical Tasks                     4
L3/L4 Cases                        3

SALESMEN NEEDING ATTENTION
---------------------------------------------------------
Rahul     3 Broken PTP              Critical
Amit      5 Overdue Tasks            Critical
Vijay     Repeated No Answer         Warning

[VIEW ALL]

APPROVAL INBOX
---------------------------------------------------------
Disputes Awaiting Approval          5
PTP Corrections                     2
Task Extensions                     3

[OPEN APPROVALS]
```

------------------------------------------------------------------------

# 8. Financial Data on Dashboard

BUSY is the financial source of truth.

TP-RMS should read financial information such as:

-   Customer
-   Invoice
-   Outstanding
-   Due
-   Receipt
-   Bill-wise allocation
-   Credit/debit notes
-   Cancellations
-   Adjustments

TP-RMS must not directly rewrite financial truth.

Do not allow RE to:

-   Edit outstanding
-   Edit invoice balance
-   Create accounting receipts
-   Delete receipts
-   Create accounting credit notes
-   Write off debt
-   Manually mark a customer financially paid

If BUSY synchronization is stale, show the freshness clearly.

Example:

``` text
Financial Data: Fresh
Last Sync: 10:32 AM
```

or:

``` text
Financial Data: Stale / Preliminary
Last Successful Sync: Yesterday 6:15 PM
```

------------------------------------------------------------------------

# 9. Expected Collection vs Recovery Target

Do not treat these as identical.

## Recovery Target

Operational amount requiring recovery attention for the relevant date.

## Expected Collection

Amount expected from valid active payment commitments, such as valid PTP
commitments.

Example:

``` text
Overdue exposure                  ₹10,00,000
PTP due today                     ₹3,00,000
Overlap already counted           ₹1,00,000

Recovery Target                   ₹12,00,000
```

Expected Collection could separately be:

``` text
Valid PTP commitments today       ₹3,50,000
```

Do not double-count money across operational views.

------------------------------------------------------------------------

# 10. Salesmen Needing Attention

Purpose:

> Identify where recovery execution or process discipline requires RE
> attention.

This must not automatically treat a difficult customer as salesperson
failure.

Keep these separate:

``` text
CUSTOMER DIFFICULTY
        ≠
SALESPERSON NON-COMPLIANCE
```

Example:

``` text
SALESMEN NEEDING ATTENTION

Salesman     Problem                         Severity
-------------------------------------------------------
Rahul        3 Broken PTP                    Critical
Amit         5 Overdue Tasks                 Critical
Vijay        Repeated No Answer              Warning
Suresh       L3 Case Without Plan            Critical
Karan        Repeated Process Exceptions     Warning
```

------------------------------------------------------------------------

# 11. Salesman Drill-Down

When RE opens Rahul:

``` text
RAHUL

Assigned Customers: 120

TODAY
------------------------------------------------
Customers Handled
Meaningful Actions
PTPs Created
PTP Value
Tasks Completed
Tasks Overdue
No Answer Attempts
Physical Visits

RECOVERY EXCEPTIONS
------------------------------------------------
Broken PTP
No Follow-Up
Critical Tasks
L2 Cases
L3 Cases

PROCESS DISCIPLINE
------------------------------------------------
Missing Evidence
Late Actions
Overdue Tasks
Mandatory Actions Missed

CUSTOMER DIFFICULTY
------------------------------------------------
High-Risk Customers
Disputes
Payment Failures
Repeated Broken PTP
```

The system must retain enough underlying event data to distinguish
salesperson behavior from customer behavior.

------------------------------------------------------------------------

# 12. Company Recovery Queue

The RE has company-wide recovery visibility.

The operational queue is **customer-level**.

One customer must not appear once per invoice.

Example:

``` text
ABC Traders
10 overdue invoices
₹5,00,000 total due
```

Operational queue:

``` text
ONE CUSTOMER ROW
```

Financial drill-down:

``` text
ABC Traders
    ↓
Invoices
    ↓
Invoice-level balances
    ↓
Receipts / allocations
```

------------------------------------------------------------------------

# 13. Company Recovery Queue Example

``` text
COMPANY RECOVERY QUEUE

Priority | Customer      | Salesman | Exposure | State
---------------------------------------------------------
1        | ABC Traders   | Rahul    | ₹5,00,000 | Broken PTP
2        | XYZ Traders   | Amit     | ₹8,00,000 | L3
3        | PQR Stores    | Vijay    | ₹3,00,000 | Visit Required
4        | DEF Traders   | Suresh   | ₹2,00,000 | PTP Due
```

Each row should show enough information to answer:

-   Why is this customer here?
-   Who owns it?
-   What is the current exposure?
-   What is the current recovery state?
-   What is the next action?
-   Is escalation active?

------------------------------------------------------------------------

# 14. Queue Priority

The operational queue should follow the configured business priority.

Conceptually:

``` text
1. Management / Critical Instruction
2. Broken PTP
3. Critical or overdue visit/task
4. PTP Due
5. Overdue Follow-Up
6. High-Value Due
7. Other Due
8. Upcoming Due
```

Exact weights and thresholds must remain configurable if the Master
Build Book defines them as configurable.

------------------------------------------------------------------------

# 15. Customer 360

Customer 360 is the RE's main investigation screen.

It should show:

``` text
Customer Header
Financial Summary
Financial Freshness
Recovery State
Primary Next Action
Owner
Contacts
Invoices
Ageing
PTP History
Risk
Disputes
Tasks
Payment Claims
Reasons
Communications
Visits
Interventions
Unified Timeline
Escalation
```

Example:

``` text
ABC TRADERS

BUSY Code: CUST-1028
Salesman: Rahul
Risk: High
Escalation: L2
Financial Freshness: 10:32 AM

TOTAL OUTSTANDING       ₹5,00,000
TOTAL DUE               ₹4,00,000
FUTURE DUE              ₹1,00,000
OLDEST OVERDUE          45 DAYS

RECOVERY STATE
Broken PTP

PRIMARY NEXT ACTION
RE Supervision

PTP
₹2,00,000 — Broken

TASKS
2 Open
1 Overdue

DISPUTE
₹80,000 — Awaiting Resolution

CONTACT ATTEMPTS
3 No Answer

TIMELINE
Invoice Due
Call
PTP
PTP Due
BUSY Reconciliation
Broken PTP
Dispute
Escalation
RE Intervention
```

------------------------------------------------------------------------

# 16. Customer State and Next Action

Customer Timeline is historical.

Current Recovery State is operational state.

The RE must always be able to see:

``` text
CURRENT STATE
+
PRIMARY NEXT ACTION
+
OWNER
+
WHY
+
WHAT HAPPENS NEXT
```

A customer may have multiple secondary conditions, but operationally it
should have one primary next action.

------------------------------------------------------------------------

# 17. No Valid Next Action Exception

This is a critical RE exception.

If:

``` text
Active due exposure exists
+
Customer has an owner
+
No valid next action exists
```

show:

``` text
RE EXCEPTION

Customer:
ABC Traders

Outstanding:
₹5,00,000

Owner:
Rahul

Problem:
No valid operational next action exists.

[OPEN CUSTOMER]
```

The system must not silently remove the customer from recovery.

------------------------------------------------------------------------

# 18. Owner Mapping Required

If financial exposure exists without an active mapped owner:

``` text
OWNER MAPPING REQUIRED
```

Example:

``` text
UNMAPPED EXPOSURE

Customer:
ABC Traders

Outstanding:
₹5,00,000

Problem:
No active salesperson mapping

[RESOLVE MAPPING]
```

Unmapped exposure must remain visible.

------------------------------------------------------------------------

# 19. Approval Inbox

The RE Approval Inbox is a controlled decision queue.

Possible approval categories include:

-   PTP correction requests
-   Dispute approvals
-   Task extension decisions
-   Verification-required decisions
-   Other authorized workflow approvals

Example:

``` text
APPROVAL INBOX

PTP CORRECTIONS
---------------------------------
ABC Traders
Original PTP: ₹2,00,000
Requested correction: ₹1,50,000

DISPUTES
---------------------------------
XYZ Traders
Dispute: ₹80,000

TASK EXTENSIONS
---------------------------------
PQR Stores
Physical Visit
Original Deadline: 22 Aug, 5 PM
Requested: 23 Aug, 5 PM
```

------------------------------------------------------------------------

# 20. PTP Correction

A salesperson should not silently edit/delete a PTP.

Flow:

``` text
Salesperson
    ↓
PTP Correction Request
    ↓
RE Approval
    ↓
Approved / Rejected
    ↓
Audit
```

Example:

``` text
ORIGINAL PTP
₹5,00,000
22 Aug
3:00 PM

REQUESTED CORRECTION
₹4,00,000
23 Aug
3:00 PM

Reason:
Customer changed commitment
```

RE can:

``` text
[APPROVE]
[REJECT]
```

Original history remains.

------------------------------------------------------------------------

# 21. PTP Lifecycle

``` text
Scheduled
    ↓
Due
    ↓
Awaiting Reconciliation
    ↓
 ┌───────────────┬──────────────────┬─────────────┐
 ↓               ↓                  ↓
Kept        Partially Kept         Broken
```

Important:

The salesperson does not manually declare a mature PTP as Broken.

The system determines PTP result using trusted financial reconciliation.

If BUSY cannot be reliably checked:

``` text
Financial Sync Pending
```

Do not falsely mark the PTP Broken.

------------------------------------------------------------------------

# 22. Broken PTP Escalation

Default conceptual progression:

``` text
1st Broken PTP
    ↓
L1 — Salesperson Led

2nd Broken PTP
    ↓
L2 — RE Supervision

3rd Broken PTP
    ↓
L3 — RE Control

Serious L3
    ↓
L4 — Management Attention
```

Age/value/behavior rules may accelerate escalation if configured.

Historical highest escalation level must be retained.

------------------------------------------------------------------------

# 23. L2 --- RE Supervision

Example:

``` text
ABC Traders
Outstanding: ₹5,00,000

PTP #1 → Broken
PTP #2 → Broken

ESCALATION:
L2 — RE SUPERVISION
```

RE opens Customer 360 and reviews:

-   Financial exposure
-   PTP history
-   Payment history
-   Calls
-   No Answer attempts
-   Physical visits
-   Tasks
-   Disputes
-   Salesperson actions
-   Timeline
-   Risk

RE then performs an authorized intervention.

Possible actions, depending on configured permissions:

``` text
View Customer 360
Assign Task
Review Task
Create RE Instruction
Supervise Salesman
Review Dispute
Escalate
```

------------------------------------------------------------------------

# 24. L3 --- RE Control

Example:

``` text
PTP #1 → Broken
PTP #2 → Broken
PTP #3 → Broken

Escalation:
L3 — RE CONTROL
```

This is no longer normal salesperson-led recovery.

RE must take control according to the configured escalation workflow.

The case should have:

-   RE owner
-   Reason
-   Current plan
-   Next action
-   Deadline
-   Audit trail

------------------------------------------------------------------------

# 25. L4 --- Management Attention

L4 means:

``` text
MANAGEMENT ATTENTION
```

It must be a tracked operational case.

Example:

``` text
MANAGEMENT ATTENTION

Customer:
ABC Traders

Money at Risk:
₹25,00,000

Reason:
Repeated Broken PTP
High Exposure
L3 unresolved

Current Owner:
RE Rajesh

Next Action:
Management Review

Plan:
Executive intervention
```

Do not make L4 just a red badge.

------------------------------------------------------------------------

# 26. RE Interventions

RE actions must be controlled business commands.

Examples:

``` text
VIEW CUSTOMER 360
ASSIGN TASK
REASSIGN WHERE AUTHORIZED
APPROVE
REJECT
REQUEST CLARIFICATION
CREATE RE INSTRUCTION
SUPERVISE
ESCALATE
```

Do not provide arbitrary buttons such as:

``` text
[SET CUSTOMER = PAID]
[SET PTP = BROKEN]
[SET DISPUTE = RESOLVED]
```

Users trigger valid business events.

The workflow engine determines the resulting state.

------------------------------------------------------------------------

# 27. Task Engine

A task exists whenever somebody must do something.

Required task fields:

``` text
Customer
Owner
Deadline
Priority
Status
Source
```

Task types can include:

-   Customer Call
-   Physical Visit
-   Dispute Resolution
-   Document Follow-Up
-   Financial Team Follow-Up
-   Customer Detail Correction
-   Payment Verification
-   Management Instruction

------------------------------------------------------------------------

# 28. RE My Tasks

Example:

``` text
MY TASKS

CRITICAL
---------------------------------
Management Instruction
ABC Traders
Due: Today 5 PM

OVERDUE
---------------------------------
Dispute Resolution
XYZ Traders
Due: Yesterday

DUE TODAY
---------------------------------
Payment Verification
PQR Stores

Financial Team Follow-Up
DEF Traders
```

Task status and overdue calculation are separate.

------------------------------------------------------------------------

# 29. Overdue Task

Overdue is a calculated condition.

Example:

``` text
Task Status:
Pending

Deadline:
21 Aug, 5 PM

Current Time:
22 Aug, 9 AM
```

System:

``` text
OVERDUE = TRUE
```

Do not create an artificial lifecycle status called `OVERDUE` if overdue
is intended to be calculated from the deadline.

------------------------------------------------------------------------

# 30. Task Extension

Example:

``` text
Task:
Physical Visit

Original Deadline:
22 Aug, 5 PM

Requested New Deadline:
23 Aug, 5 PM

Reason:
Customer unavailable
```

Before RE approval:

``` text
Authoritative Deadline = 22 Aug, 5 PM
```

If that time passes:

``` text
Task = Overdue
```

After approval:

``` text
Authoritative Deadline = 23 Aug, 5 PM
```

The original deadline remains in audit history.

------------------------------------------------------------------------

# 31. Task Completion Does Not Mean Payment

Example:

``` text
Task:
Send Updated Ledger

Task:
Completed
```

Customer still owes:

``` text
₹3,00,000
```

Therefore:

``` text
Task = Completed
Customer = Still in Recovery
Next Action = Recovery Follow-Up
```

Never let task completion silently close financial exposure.

------------------------------------------------------------------------

# 32. Financial Team Follow-Up

V1 has no Accounts login.

Therefore financial-team dependencies remain owned in RMS by the RE.

Example:

``` text
Customer:
ABC Traders

Request:
Updated Ledger

Task:
Financial Team Follow-Up

Owner:
Recovery Executive

Deadline:
Today 4 PM
```

RE completes/co-ordinates the work.

After completion:

``` text
Ledger delivered
      ↓
Customer still owes ₹3,00,000
      ↓
Recovery Follow-Up
      ↓
Salesman
```

------------------------------------------------------------------------

# 33. No Answer --- RE View

No Answer is not a final recovery outcome.

Conceptual sequence:

``` text
Primary Contact
    ↓
Alternate / Carpenter
    ↓
Additional Controlled Contact
    ↓
Physical Visit
```

Each attempt requires configured evidence and system-captured:

-   Date/time
-   Contact
-   User
-   Attempt stage

Exact timing is configurable.

------------------------------------------------------------------------

# 34. No Answer Example

``` text
Attempt 1
Primary Contact
No Answer
Evidence Captured

Attempt 2
Alternate Contact
No Answer
Evidence Captured

Attempt 3
Additional Controlled Contact
No Answer
Evidence Captured
```

Then:

``` text
PHYSICAL VISIT REQUIRED
```

The system must not allow endless No Answer entries.

------------------------------------------------------------------------

# 35. Physical Visit

First physical visit is assigned to the salesperson by default.

Example:

``` text
Customer:
ABC Traders

Salesman:
Rahul

Reason:
Repeated valid No Answer

Task:
Physical Visit

Owner:
Rahul
```

RE can supervise/control the task where authorized.

------------------------------------------------------------------------

# 36. Physical Visit Outcomes

Physical Visit should reuse standard recovery outcomes.

Examples:

``` text
PTP
Will Confirm
Dispute
Unable To Commit
Wrong Address
Customer Not Available
```

Example:

``` text
VISIT
  ↓
Customer:
"I will pay ₹2,00,000 Friday."
  ↓
PTP
```

Visit task can be completed while the PTP remains active.

------------------------------------------------------------------------

# 37. Physical Visit → PTP Example

``` text
Physical Visit
Customer: ABC Traders

Outcome: PTP
Amount: ₹2,00,000
Date: 25 Aug
Time: 3 PM
```

System:

``` text
Physical Visit Task → Completed
PTP → Scheduled
Customer → Active Recovery
```

Financial closure occurs only after trusted financial confirmation.

------------------------------------------------------------------------

# 38. Wrong Address

If the customer is not at the recorded address:

``` text
Outcome:
Wrong Address
```

This does not close recovery.

Create a controlled detail-correction workflow.

Example:

``` text
TASK

Customer Detail Correction

Customer:
ABC Traders

Issue:
Address Incorrect

Owner:
Configured Owner

Deadline:
Configured Deadline
```

------------------------------------------------------------------------

# 39. Customer Not Available

If the customer is at the location but unavailable:

``` text
Outcome:
Customer Not Available
```

This does not close recovery.

The system must produce a valid next action.

------------------------------------------------------------------------

# 40. Dispute --- RE is Central

Salesperson raises the exact disputed amount.

Example:

``` text
Total Due:
₹5,00,000

Disputed:
₹80,000

Undisputed:
₹4,20,000
```

The RE approval workflow controls the disputed amount.

------------------------------------------------------------------------

# 41. Dispute Lifecycle

``` text
Raised
   ↓
Awaiting RE Approval
   ↓
Approved / Rejected
   ↓
Resolution Pending
   ↓
Resolution
   ↓
Awaiting Verification
   ↓
Resolved
   ↓
If still unpaid
   ↓
Return to Recovery
```

------------------------------------------------------------------------

# 42. Partial Dispute Example

Customer:

``` text
Total Due:
₹5,00,000
```

Dispute:

``` text
₹80,000
```

RE approves.

System keeps:

``` text
₹80,000
→ Dispute workflow

₹4,20,000
→ Normal recovery
```

The undisputed amount must not be blocked just because a partial dispute
exists.

------------------------------------------------------------------------

# 43. Dispute Resolution Owner

An approved dispute must have:

``` text
Resolution Owner
+
Deadline
```

Example:

``` text
Dispute:
₹80,000

Owner:
RE Rajesh

Deadline:
25 Aug, 5 PM
```

------------------------------------------------------------------------

# 44. Dispute Verification

After resolution:

``` text
Resolution Complete
      ↓
RE Verification
      ↓
Verified
```

If BUSY still shows the amount due:

``` text
Resolved
+
Still Unpaid
      ↓
Return to Recovery
```

Resolved does not mean paid.

------------------------------------------------------------------------

# 45. Payment Already Made

If customer says:

> "I already paid."

Do not immediately mark the customer Paid.

Create:

``` text
Payment Claim
Status:
Awaiting Verification
```

BUSY confirms the financial result.

------------------------------------------------------------------------

# 46. Payment Claim Lifecycle

``` text
Awaiting Verification
       ↓
BUSY Reconciliation
       ↓
 ┌──────────────────┬─────────────────────┐
 ↓                  ↓
Verified        Verification Failed
```

If BUSY data is unavailable:

``` text
Financial Sync Pending
```

Do not convert sync failure into a failed payment claim.

------------------------------------------------------------------------

# 47. Payment Claim Example

Customer claims:

``` text
₹1,00,000 paid
```

RE sees:

``` text
PAYMENT CLAIM

Claimed Amount:
₹1,00,000

Status:
Awaiting Verification

BUSY:
Not Yet Confirmed
```

RE cannot click:

``` text
MARK AS PAID
```

If BUSY later confirms:

``` text
Verified
```

Financial exposure updates from BUSY.

------------------------------------------------------------------------

# 48. Customer Credit Health

Customer Credit Health is separate from salesperson Recovery Score.

Pilot components can include:

``` text
Payment Timeliness
PTP Reliability
Current Ageing
Outstanding Exposure
Recent Payment Trend
Behavioural Exceptions
```

Pilot risk bands:

``` text
85–100  Low Risk
70–84   Moderate
50–69   High
<50     Critical
```

New customers can show:

``` text
Insufficient History
```

instead of false precision.

------------------------------------------------------------------------

# 49. Recovery Score vs Customer Risk

Never mix these.

``` text
SALESPERSON RECOVERY SCORE
        ↓
How disciplined is the employee's recovery process?

CUSTOMER CREDIT HEALTH
        ↓
How risky/reliable is the customer?
```

Example:

``` text
Customer:
Frequently pays late

Salesman:
Calls on time
Records PTP correctly
Visits when required
Completes tasks

Result:

Customer Risk = High
Salesman Process = Strong
```

------------------------------------------------------------------------

# 50. Notifications for RE

V1 internal channels:

-   In-App
-   Push
-   Selected Email

Employee WhatsApp is not the default internal channel.

Severity:

``` text
Info
Action Required
Warning
Critical
```

Notifications should be consolidated to prevent alert flooding.

Examples:

``` text
Second Broken PTP
→ RE Supervision

Third Broken PTP
→ RE Control / Critical

L4
→ Management Attention

5 PM Control
→ Consolidated RE summary
```

Reading a notification does not complete the work.

------------------------------------------------------------------------

# 51. 5 PM Control

At the configured daily control time, system checks incomplete mandatory
actions.

Example:

``` text
5 PM CONTROL

Overdue Tasks                       4
Mandatory Actions Not Completed    3
Broken PTP Without Next Action      1
Ownerless Exposure                  ₹2,00,000
L3 Cases Without Plan               1
```

The event remains historical.

If the salesperson later completes the work, the original missed-control
event must not disappear.

------------------------------------------------------------------------

# 52. Workflow Integrity Checks

The RE system must detect:

``` text
Ownerless Exposure
Ownerless Tasks
Stuck PTPs
Stuck Payment Claims
Ownerless Disputes
L3/L4 Without Plan
No Valid Next Action
Stale Financial Data
```

These are control exceptions.

------------------------------------------------------------------------

# 53. RE Daily Operating Flow

``` text
09:00
LOGIN
 ↓
CONTROL DASHBOARD
 ↓
Check financial freshness
 ↓
Check My Actions
 ↓
Check Salesmen Needing Attention
 ↓
Check Broken PTP
 ↓
Check L2/L3/L4
 ↓
Check Approval Inbox
 ↓
Check Company Recovery Queue
 ↓
Handle highest-impact cases
 ↓
Monitor Tasks / Disputes / Dependencies
 ↓
14:00
RE CONTROL SUMMARY
 ↓
Continue intervention
 ↓
17:00
5 PM CONTROL
 ↓
Record unresolved mandatory actions
 ↓
End-of-day monitoring
```

Exact working hours are configurable.

------------------------------------------------------------------------

# 54. Complete End-to-End Example

## Customer

``` text
ABC Traders
Outstanding: ₹10,00,000
Due: ₹8,00,000
Salesman: Rahul
```

## Day 1

Rahul calls.

Customer promises:

``` text
₹3,00,000
Tomorrow
3 PM
```

PTP:

``` text
Scheduled
```

RE sees the commitment in Expected Collection.

## Day 2

BUSY shows:

``` text
₹1,00,000 received
```

System:

``` text
PTP = Partially Kept
Remaining = ₹2,00,000
```

## Day 3

Rahul calls.

Customer says:

> "There is an invoice issue."

Rahul raises:

``` text
Dispute:
₹80,000
```

RE Approval Inbox shows the dispute.

RE approves.

System:

``` text
₹80,000 → Dispute Workflow
₹1,20,000 → Active Recovery
```

## Day 4

Dispute resolution completes.

RE verifies.

BUSY still shows:

``` text
₹80,000 due
```

System:

``` text
Resolved but Unpaid
→ Return ₹80,000 to Recovery
```

## Day 5

Rahul calls.

``` text
No Answer
```

Evidence captured.

## Day 6

Repeated No Answer.

Configured contact sequence is exhausted.

System:

``` text
Physical Visit Required
```

## Day 7

Rahul visits.

Customer says:

> "I will pay ₹2,00,000 Friday."

Visit:

``` text
Completed
```

PTP:

``` text
₹2,00,000
Friday
3 PM
Scheduled
```

## Day 8

Friday arrives.

BUSY shows no qualifying payment.

System:

``` text
PTP = Broken
```

If this is the second confirmed Broken PTP:

``` text
L2 — RE Supervision
```

RE receives the control signal.

RE opens Customer 360 and sees:

``` text
Financial
PTPs
Dispute
No Answer
Visit
Tasks
Timeline
Risk
Salesman activity
Escalation
```

RE performs an authorized intervention.

System records:

``` text
Intervention
Owner
Reason
Deadline
Next Action
Timeline
Audit
```

If the case remains serious:

``` text
L3 — RE Control
```

If it qualifies for management attention:

``` text
L4 — Management Attention
```

------------------------------------------------------------------------

# 55. What RE Can Actually Do

The RE should be able to:

## View

-   Company recovery
-   Salesmen
-   Customers
-   Customer 360
-   PTPs
-   Tasks
-   Disputes
-   Payment claims
-   Escalations
-   Risk
-   Timeline
-   Financial freshness

## Control

-   Approve authorized corrections
-   Approve/review disputes
-   Control escalation
-   Supervise recovery
-   Assign authorized tasks
-   Create RE instructions
-   Review/verify tasks
-   Manage financial-team dependencies
-   Reassign where authorized
-   Escalate to Management

## Monitor

-   Broken PTP
-   No Follow-Up
-   No Answer progression
-   Overdue tasks
-   Disputes
-   Payment claims
-   Ownerless exposure
-   Missing next actions
-   L2/L3/L4 cases
-   Daily control events

## Cannot Do

-   Rewrite BUSY outstanding
-   Edit invoice balances
-   Create accounting receipts
-   Delete accounting receipts
-   Write accounting credit notes
-   Write off debt
-   Manually mark financial payment as verified
-   Arbitrarily set final workflow states

------------------------------------------------------------------------

# 56. Reassignment

If a customer moves:

``` text
Rahul
  ↓
Amit
```

Amit gets:

``` text
Full customer history
```

Rahul's historical actions remain attributed to Rahul.

Current ownership changes.

Historical actor does not change.

Customer risk does not reset.

------------------------------------------------------------------------

# 57. Audit Requirements

Every material RE action must capture:

``` text
Who
What
When
Why
Source
Previous State
New State
```

Examples:

``` text
PTP Correction Approved
Dispute Approved
Task Extension Approved
Task Reassigned
Escalation Changed
Management Instruction Created
Intervention Created
```

History must remain traceable.

Do not silently rewrite history.

------------------------------------------------------------------------

# 58. Search and Filters

RE company-wide search should support authorized data.

Useful search:

``` text
Customer
BUSY Customer Code
Salesman
Branch
Escalation
PTP
Task
Dispute
```

Useful filters:

``` text
Salesman
Branch
Recovery State
Primary Next Action
Escalation Level
Broken PTP
PTP Due
No Follow-Up
Overdue Tasks
Disputes
Physical Visits
Payment Claims
Financial Sync Pending
Risk Band
```

------------------------------------------------------------------------

# 59. Reports and Drill-Down

Every important number must be drillable.

Example:

``` text
Broken PTP:
₹12,00,000
```

Click:

``` text
Company
 ↓
Branch
 ↓
Salesman
 ↓
Customer
 ↓
Invoice
 ↓
Source transaction
```

Dashboard totals must reconcile with underlying records.

------------------------------------------------------------------------

# 60. Export

Sensitive exports must be:

-   Role restricted
-   Audited
-   Controlled

Do not place unrestricted CSV/Excel export buttons everywhere.

Large exports can be asynchronous.

------------------------------------------------------------------------

# 61. Backend Architecture Principle

Recommended conceptual flow:

``` text
RE Desktop UI
      ↓
Authentication + Authorization
      ↓
Business API
      ↓
Workflow Engine
      ↓
 ┌─────────┬─────────┬──────────┬────────────┐
 ↓         ↓         ↓          ↓
Tasks     PTPs     Disputes   Escalations
 ↓         ↓         ↓          ↓
Timeline  Payments  Verification Notifications
```

Financial flow:

``` text
BUSY
 ↓
Sync
 ↓
Financial Mirror
 ↓
Recovery Rules
 ↓
RE Views
```

V1 should favor a modular-monolith architecture unless there is a
concrete reason to split services.

------------------------------------------------------------------------

# 62. Required Conceptual Entities

The RE workflow depends on entities such as:

``` text
users
roles
customer_assignments
customers
contacts

invoices
receipts
receipt_allocations
financial_adjustments
financial_snapshots

recovery_activities
recovery_outcomes
recovery_reasons
customer_recovery_states

ptps
ptp_status_events
ptp_correction_requests

recovery_tasks
task_events
task_extension_requests

disputes
dispute_invoice_links
dispute_events

payment_claims

escalation_events
management_attention_cases

communications
communication_status_events

notifications

customer_risk_snapshots
recovery_score_snapshots

timeline_events
audit_logs

configuration_versions
configuration_values

integration_sync_runs
system_events
event_outbox
```

Customer is the operational hub.

Invoice is the financial-detail hub.

------------------------------------------------------------------------

# 63. Backend Command Principle

Frontend should send business commands.

Conceptual examples:

``` text
PTP correction request
Dispute approval
Task extension decision
Task verification
Escalation intervention
Management instruction
```

The backend validates:

``` text
Role
Permissions
Current state
Required fields
Financial freshness
Workflow rules
Concurrency/version
```

Then the workflow engine creates the resulting state and events.

------------------------------------------------------------------------

# 64. Idempotency

RE actions must survive:

-   Double-click
-   Network retry
-   Browser retry
-   Mobile retry
-   Duplicate API requests

Example:

If RE clicks:

``` text
APPROVE
```

twice, expected result:

``` text
ONE approval
```

not:

``` text
TWO approvals
```

Use idempotency keys and state/version checks for important commands.

------------------------------------------------------------------------

# 65. State Integrity Rules

After every RE command, validate:

``` text
1. Does active due exposure still exist?
2. Does customer have an owner?
3. Does customer have a valid recovery state?
4. Does customer have a primary next action
   or valid waiting state?
5. Are required tasks owned?
6. Are deadlines valid?
7. Is escalation consistent?
8. Is audit written?
9. Is timeline updated?
10. Are dependent events/notifications generated?
```

If a critical rule fails:

``` text
DO NOT silently complete the transaction.
```

------------------------------------------------------------------------

# 66. Orphans the System Must Detect

Never allow these to become invisible:

``` text
Due exposure + no owner
Due exposure + no next action
Open task + no owner
Approved dispute + no resolution owner
Approved dispute + no deadline
L3/L4 + no plan
Broken PTP + no next recovery action
Payment claim stuck
Financial sync pending treated as failure
```

------------------------------------------------------------------------

# 67. UAT Scenarios

## UAT --- Broken PTP Escalation

``` text
1st Broken PTP → L1
2nd Broken PTP → L2
3rd Broken PTP → L3
```

## UAT --- BUSY Sync Failure

Matured PTP:

``` text
Financial Sync Pending
```

must not become:

``` text
Broken
```

## UAT --- No Answer

``` text
Primary
 ↓
Alternate / Controlled Contact
 ↓
Physical Visit Required
```

Evidence required.

## UAT --- Physical Visit to PTP

Visit outcome:

``` text
PTP
```

creates a normal PTP.

## UAT --- Partial Dispute

``` text
Due = ₹5L
Dispute = ₹80K
```

Expected:

``` text
₹4.20L active recovery
₹80K dispute
```

## UAT --- Resolved Dispute Still Unpaid

If BUSY still shows due:

``` text
Disputed amount → Recovery
```

## UAT --- Payment Already Made

Claim:

``` text
Awaiting Verification
```

Only trusted financial reconciliation can make it Verified.

## UAT --- False Payment Claim

No matching financial payment:

``` text
Verification Failed
```

Customer returns to recovery.

## UAT --- Internal Action

Ledger/document task completed while money remains due:

``` text
Task Completed
+
Recovery Follow-Up
```

## UAT --- Extension

Pending extension does not change original deadline until approved.

## UAT --- Reassignment

``` text
A → B
```

B sees full history.

A loses active access.

Historical actor remains A.

## UAT --- Management Attention

Serious L3 exception:

``` text
L4 Management Attention
+
Plan
+
Owner
+
Next Action
```

## UAT --- 5 PM Control

Incomplete mandatory actions are recorded.

Later completion does not erase the original missed-control event.

## UAT --- Dashboard Reconciliation

Every material metric drills:

``` text
Metric
 ↓
Customer
 ↓
Invoice
 ↓
Source
```

## UAT --- Unauthorized Access

Salesperson must not access:

``` text
Another salesperson's customer
RE endpoint
Management endpoint
Admin endpoint
```

Backend must enforce authorization.

## UAT --- Ownerless Exposure

Due exposure without mapping:

``` text
Owner Mapping Required
```

## UAT --- No Valid Next Action

Due customer with owner but no valid next action:

``` text
RE Exception
```

------------------------------------------------------------------------

# 68. Complete RE Test Story

Use this as a final integration test.

``` text
CUSTOMER:
ABC Traders

OUTSTANDING:
₹5,00,000

SALESPERSON:
Rahul
```

### Step 1 --- PTP

Rahul creates:

``` text
₹3,00,000
Tomorrow
3 PM
```

### Step 2 --- Partial Payment

BUSY confirms:

``` text
₹1,00,000
```

Expected:

``` text
PTP = Partially Kept
Remaining = ₹2,00,000
```

### Step 3 --- Dispute

Rahul raises:

``` text
₹80,000 dispute
```

RE approves.

Expected:

``` text
₹80,000 → Dispute
Remaining eligible due → Active Recovery
```

### Step 4 --- Dispute Resolution

Resolution completes.

RE verifies.

BUSY still shows ₹80,000 due.

Expected:

``` text
₹80,000 → Recovery
```

### Step 5 --- No Answer

Rahul attempts contact.

Expected:

``` text
No Answer
Evidence
Attempt Recorded
Next Controlled Contact
```

### Step 6 --- Repeated No Answer

Expected:

``` text
Physical Visit Required
```

### Step 7 --- Physical Visit

Rahul visits.

Customer gives:

``` text
PTP:
₹2,00,000
Friday
3 PM
```

Expected:

``` text
Visit Task = Completed
PTP = Scheduled
```

### Step 8 --- PTP Breaks

BUSY shows no qualifying payment.

Expected:

``` text
PTP = Broken
```

If this is the second broken PTP:

``` text
L2
```

### Step 9 --- RE Intervention

RE opens Customer 360.

Expected to see:

``` text
Financial
PTP History
Dispute
No Answer
Visit
Tasks
Timeline
Risk
Salesman Activity
Escalation
```

RE creates an authorized intervention.

Expected:

``` text
Intervention
Owner
Reason
Deadline
Next Action
Timeline
Audit
```

### Step 10 --- Further Escalation

If still unresolved and configured:

``` text
L3
```

If serious enough:

``` text
L4 Management Attention
```

------------------------------------------------------------------------

# 69. Non-Negotiable Build Laws

1.  BUSY is financial source of truth.
2.  RE cannot manually rewrite financial truth.
3.  Every active due receivable must have owner + state + next
    action/waiting workflow.
4.  Operational queue is customer-level.
5.  Invoice detail remains available underneath.
6.  Users trigger business events; they do not arbitrarily set final
    states.
7.  Broken PTP requires successful financial reconciliation.
8.  Financial Sync Pending must suppress false negative conclusions.
9.  No Answer requires configured evidence and controlled progression.
10. Repeated No Answer eventually reaches Physical Visit Required.
11. First physical visit is assigned to salesperson by default.
12. Visit outcomes reuse standard recovery workflows.
13. Task completion never equals financial closure.
14. Pending task extension does not change deadline until approved.
15. Dispute approval is mandatory.
16. Only approved disputed amount is shielded operationally.
17. Resolved but unpaid disputes return to recovery.
18. Payment Already Made does not immediately mean Paid.
19. Customer risk and salesperson discipline are separate.
20. Notifications do not complete work.
21. Historical actions remain traceable.
22. Reassignment changes current ownership, not historical attribution.
23. Every intervention and approval is audited.
24. Dashboard numbers must drill to source.
25. Technical failures must not become customer/salesperson faults.
26. Configuration may tune thresholds but cannot disable integrity
    rules.
27. No orphaned exposure.
28. No ownerless tasks.
29. No ownerless disputes.
30. No L3/L4 case without a plan.

------------------------------------------------------------------------

# 70. V1 Features That Must Not Be Silently Added

Do not silently add these to V1:

-   AI delay-risk prediction
-   AI best-call-time suggestions
-   AI next-best-action prediction
-   Generative reminder drafting
-   Native mobile app requirement
-   Full offline synchronization
-   Automated BUSY credit blocking
-   Legal recovery workflow
-   Predictive supplier-payment/cash planning
-   Unified sales + recovery incentive payout
-   Call recording without explicit legal/privacy approval

------------------------------------------------------------------------

# 71. Configurable / TBD Areas

Do not hard-code business rules where the source defines them as
configurable/TBD.

Examples:

-   Exact No Answer timing
-   No Answer thresholds
-   Will Confirm maximum window
-   High-value thresholds
-   Management Attention thresholds
-   Notification timings
-   5 PM control configuration
-   Reconciliation cut-off
-   Ageing thresholds
-   Reminder offsets
-   Recovery Score denominator
-   Customer Credit Health tuning
-   BUSY integration method
-   BUSY stable source IDs
-   WhatsApp provider
-   Hosting/authentication stack

Configuration lifecycle:

``` text
Draft
 ↓
Approved
 ↓
Scheduled
 ↓
Active
 ↓
Retired
```

Emergency immediate changes require reason and audit.

------------------------------------------------------------------------

# 72. Final RE Acceptance Rule

The RE module is complete only when the answer to this question is
**YES**:

> For every active receivable requiring recovery, can the Recovery
> Executive see the current financial exposure, current recovery state,
> last meaningful action, next action, accountable owner,
> PTP/dispute/task/escalation state, reason for the current state, and
> what will happen next --- while never overriding BUSY financial truth?

If yes, the RE workflow is operationally complete.

------------------------------------------------------------------------

# 73. Final AI Developer Instruction

Build the RE module as a **recovery control system**.

Do not build it as a generic dashboard.

Every operational problem must lead to:

``` text
PROBLEM
  ↓
CONTEXT
  ↓
AUTHORIZED ACTION
  ↓
OWNER
  ↓
DEADLINE
  ↓
NEXT ACTION
  ↓
AUDIT
```

The AI/developer should always preserve this hierarchy:

``` text
BUSY
Financial Truth
        ↓
TP-RMS
Operational Recovery Truth
        ↓
Customer Recovery State
        ↓
Primary Next Action
        ↓
Task / PTP / Dispute / Payment Claim / Escalation
        ↓
RE Supervision / Control
        ↓
Management Attention when required
```

The RE should be able to discover exceptions, understand the complete
customer context, take authorized action, and verify that a valid next
step exists.

**Never allow a customer with active due exposure to silently disappear
from operational management.**
