const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { startTestApp, login, authHeaders } = require('./helpers/app');
const { resetDb } = require('./helpers/db');
const { teardownAll } = require('./helpers/teardown');
const ptpRepository = require('../src/repositories/ptpRepository');
const taskRepository = require('../src/repositories/taskRepository');

let app;

before(async () => {
  await resetDb();
  app = await startTestApp();
  for (const id of ['P1', 'P2', 'P5']) {
    await ptpRepository.update(id, { status: 'kept', amountReceived: 0 });
  }
  await taskRepository.update('T4', { status: 'completed', outcome: 'Neutralized for test setup', completedAt: new Date() });
});

after(async () => {
  await teardownAll(app);
});

test('RE and the resolution owner can chat back and forth with attachments on an Approved dispute', async () => {
  // 1. Salesperson raises a dispute.
  const salesToken = await login(app.baseUrl, 'mahesh');
  const outcomeRes = await fetch(`${app.baseUrl}/api/customers/C4/record-outcome`, {
    method: 'POST',
    headers: authHeaders(salesToken),
    body: JSON.stringify({ nextAction: 'Dispute Raised', reason: 'Dispute Raised', details: 'Reason: Damaged goods, Amt: 5000' }),
  });
  if (outcomeRes.status !== 200) assert.fail(`record-outcome failed: ${await outcomeRes.text()}`);

  // 2. RE approves it, assigning a resolution owner.
  const reToken = await login(app.baseUrl, 'amit.re');
  const listRes = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(reToken) });
  const disputes = await listRes.json();
  const dispute = disputes.find((d) => d.customerId === 'C4' && d.status === 'Pending Approval');
  assert.ok(dispute, 'expected a fresh Pending Approval dispute on C4');

  const approveRes = await fetch(`${app.baseUrl}/api/disputes/${dispute.id}/approve`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({
      resolutionOwner: 'ramesh-re',
      deadline: new Date(Date.now() + 2 * 86400000).toISOString(),
      description: 'Verify damaged goods claim with warehouse',
      note: 'Please check the delivery challan before confirming.',
    }),
  });
  if (approveRes.status !== 200) assert.fail(`approve failed: ${await approveRes.text()}`);

  // 3. Upload a "PDF" from the RE side (this is the exact call
  // ApiClient.uploadAttachment makes from the new attach button in
  // dispute_details_view.dart's _sendMessage bottom sheet) and post a
  // message to the resolution owner carrying it.
  const pdfForm = new FormData();
  pdfForm.append('file', new Blob([Buffer.from('%PDF-1.4 fake evidence')], { type: 'application/pdf' }), 'delivery-challan.pdf');
  const reUpload = await fetch(`${app.baseUrl}/api/attachments`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${reToken}` },
    body: pdfForm,
  });
  if (reUpload.status !== 201) assert.fail(`RE PDF upload failed: ${await reUpload.text()}`);
  const { path: rePdfPath } = await reUpload.json();
  assert.ok(rePdfPath.endsWith('.pdf'), `expected a .pdf-suffixed stored path, got ${rePdfPath}`);

  const reMsgRes = await fetch(`${app.baseUrl}/api/disputes/${dispute.id}/message`, {
    method: 'POST',
    headers: authHeaders(reToken),
    body: JSON.stringify({ body: 'Here is the delivery challan for reference.', attachmentPath: rePdfPath }),
  });
  if (reMsgRes.status !== 200) assert.fail(`RE message post failed: ${await reMsgRes.text()}`);

  // 4. Resolution owner reads the thread (as their resolution task would)
  // and replies with a photo attachment — the exact call
  // task_details_screen_v3.dart's "Message RE" makes.
  const ownerToken = await login(app.baseUrl, 'ramesh.re');
  const ownerListRes = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(ownerToken) });
  const ownerDisputes = await ownerListRes.json();
  const ownerView = ownerDisputes.find((d) => d.id === dispute.id);
  assert.ok(ownerView, 'resolution owner should be able to see the dispute they were assigned');
  // messages[0] is the mandatory assignment note approve() itself seeds
  // the thread with; messages[1] is the RE's attached follow-up.
  assert.equal(ownerView.messages.length, 2);
  assert.equal(ownerView.messages[1].body, 'Here is the delivery challan for reference.');
  assert.equal(ownerView.messages[1].attachmentPath, rePdfPath);
  assert.equal(ownerView.messages[1].authorRole, 'RECOVERY_EXECUTIVE');

  const imgForm = new FormData();
  imgForm.append('file', new Blob([Buffer.from('fake-jpeg-bytes')], { type: 'image/jpeg' }), 'warehouse-photo.jpg');
  const ownerUpload = await fetch(`${app.baseUrl}/api/attachments`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${ownerToken}` },
    body: imgForm,
  });
  if (ownerUpload.status !== 201) assert.fail(`owner image upload failed: ${await ownerUpload.text()}`);
  const { path: ownerImgPath } = await ownerUpload.json();

  const ownerMsgRes = await fetch(`${app.baseUrl}/api/disputes/${dispute.id}/message`, {
    method: 'POST',
    headers: authHeaders(ownerToken),
    body: JSON.stringify({ body: 'Confirmed with warehouse — photo attached.', attachmentPath: ownerImgPath }),
  });
  if (ownerMsgRes.status !== 200) assert.fail(`owner message post failed: ${await ownerMsgRes.text()}`);

  // 5. RE re-reads the thread and sees both messages in order, each with
  // the right attachment and author — the chat is genuinely two-way.
  const reListRes2 = await fetch(`${app.baseUrl}/api/disputes`, { headers: authHeaders(reToken) });
  const reDisputes2 = await reListRes2.json();
  const reView2 = reDisputes2.find((d) => d.id === dispute.id);
  assert.equal(reView2.messages.length, 3);
  assert.equal(reView2.messages[1].attachmentPath, rePdfPath);
  assert.equal(reView2.messages[2].attachmentPath, ownerImgPath);
  assert.equal(reView2.messages[2].authorId, 'ramesh-re');
  assert.equal(reView2.messages[2].body, 'Confirmed with warehouse — photo attached.');

  // 6. Fetching each stored attachment back through the same authed GET
  // the app's TaskAttachmentThumbnail/downloadAndOpenAttachment use
  // returns the right bytes and content-type.
  const getPdf = await fetch(`${app.baseUrl}/api/attachments/${rePdfPath}`, { headers: authHeaders(reToken) });
  assert.equal(getPdf.status, 200);
  assert.equal(getPdf.headers.get('content-type'), 'application/pdf');
  assert.ok((getPdf.headers.get('content-disposition') || '').includes('attachment'), 'a PDF should be served as a download, not inline');

  const getImg = await fetch(`${app.baseUrl}/api/attachments/${ownerImgPath}`, { headers: authHeaders(ownerToken) });
  assert.equal(getImg.status, 200);
  assert.equal(getImg.headers.get('content-type'), 'image/jpeg');
});
