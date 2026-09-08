import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:salesman_mobile/v2/models/task.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'};

bool _isImageFile(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return _imageExtensions.contains(ext);
}

String _mimeTypeFor(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    default:
      return 'image/jpeg';
  }
}

/// Opens any attachment (image or PDF) for real viewing — images in an
/// in-app full-screen viewer, PDFs handed to the platform's own PDF viewer
/// via a data: URI (no extra native PDF-rendering plugin required).
Future<void> viewAttachment(BuildContext context, Map<String, dynamic> f) async {
  final fileName = f['fileName'] as String;
  final bytes = f['bytes'] as Uint8List;
  if (_isImageFile(fileName)) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
    return;
  }
  final uri = Uri.parse('data:${_mimeTypeFor(fileName)};base64,${base64Encode(bytes)}');
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    showAppMessage(context, message: 'Could not open this file on this device.');
  }
}

const kTeal = Color(0xFF0D9488);
const kAmber = Color(0xFFB45309);
const kPink = Color(0xFFDB2777);
const kIndigo = Color(0xFF4F46E5);

String taskTypeLabel(TaskType t) {
  switch (t) {
    case TaskType.customerCall:
      return 'Customer Call';
    case TaskType.physicalVisit:
      return 'Physical Visit';
    case TaskType.disputeResolution:
      return 'Dispute Resolution';
    case TaskType.documentFollowUp:
      return 'Document Follow-Up';
    case TaskType.financialTeamFollowUp:
      return 'Financial Team Follow-Up';
    case TaskType.customerDetailCorrection:
      return 'Customer Detail Correction';
    case TaskType.paymentVerification:
      return 'Payment Verification';
    case TaskType.managementInstruction:
      return 'Management Instruction';
  }
}

IconData taskTypeIcon(TaskType t) {
  switch (t) {
    case TaskType.customerCall:
      return Icons.call_outlined;
    case TaskType.physicalVisit:
      return Icons.location_on_outlined;
    case TaskType.disputeResolution:
      return Icons.description_outlined;
    case TaskType.documentFollowUp:
      return Icons.file_present_outlined;
    case TaskType.financialTeamFollowUp:
      return Icons.account_balance_outlined;
    case TaskType.customerDetailCorrection:
      return Icons.edit_location_alt_outlined;
    case TaskType.paymentVerification:
      return Icons.fact_check_outlined;
    case TaskType.managementInstruction:
      return Icons.campaign_outlined;
  }
}

const kDark = Color(0xFF0F172A);
const kNavy = Color(0xFF1B2B48);
const kMuted = Color(0xFF64748B);
const kBorder = Color(0xFFEEF1F5);
const kBg = Color(0xFFF8FAFC);
const kBlue = Color(0xFF2563EB);
const kRed = Color(0xFFDC2626);
const kOrange = Color(0xFFEA580C);
const kPurple = Color(0xFF7C3AED);
const kGreen = Color(0xFF16A34A);

const List<Color> kAvatarPalette = [
  Color(0xFF2563EB),
  Color(0xFF16A34A),
  Color(0xFF9333EA),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
];

Color avatarColorFor(String name) => kAvatarPalette[name.hashCode.abs() % kAvatarPalette.length];

String initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  return parts.map((p) => p.isNotEmpty ? p[0] : '').take(2).join().toUpperCase();
}

/// Shared visual shell for every "tap a row in Needs Your Attention" detail
/// screen — keeps title/banner/section/bottom-action-bar styling identical
/// across categories while letting each screen supply its own real content
/// and RE actions.
class RequestDetailScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final String bannerText;
  final String priorityLabel;
  final Color color;
  final IconData bannerIcon;
  final List<Widget> children;
  final List<Widget> actions;

  const RequestDetailScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bannerText,
    required this.priorityLabel,
    required this.color,
    required this.bannerIcon,
    required this.children,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    // Deliberately NOT a Scaffold here. Every caller of this shell is itself
    // already pushed as a route inside the app's one MaterialApp Navigator
    // (which supplies its own Scaffold-hosting page) — nesting a *second*
    // Scaffold in this position previously reproduced the exact same
    // confirmed Flutter rendering bug documented in dispute_details_view.dart:
    // the AppBar and body silently fail to paint (though they still exist
    // in the widget/semantics tree with correct geometry), leaving only the
    // bottom action row visible. A plain Material/Column reproducing the
    // same visual chrome avoids the nested-Scaffold entirely.
    // A single Material wraps the whole shell — everything below the
    // header (buttons, text fields, etc. in `children`/`actions`) needs a
    // Material ancestor too, or it throws "No Material widget found." The
    // header's own nested Material (for its elevation/shadow) is still
    // fine to nest inside this one; only Scaffold nesting was the actual
    // problem documented above.
    return Material(
      color: kBg,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            elevation: 1,
            shadowColor: Colors.black.withOpacity(0.06),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: kNavy),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kNavy, letterSpacing: 0.2)),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: color.withOpacity(0.07),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(bannerIcon, size: 15, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(bannerText,
                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600, height: 1.3)),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                  child: Text(priorityLabel, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...children,
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
          if (actions.isNotEmpty)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: const Border(top: BorderSide(color: kBorder)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, -4))],
                ),
                child: Row(
                  children: [
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: SizedBox(height: 48, child: actions[i])),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Row(
          children: [
            Container(width: 3, height: 12, decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 7),
            Text(text,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: kNavy, letterSpacing: 0.4)),
          ],
        ),
      );
}

class InfoCard extends StatelessWidget {
  final List<Widget> children;
  final Color? tint;
  final Color? borderColor;
  const InfoCard({super.key, required this.children, this.tint, this.borderColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tint ?? Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor ?? kBorder),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class KeyValueRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final bool divider;
  const KeyValueRow(this.label, this.value, {super.key, this.valueColor = kDark, this.divider = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 118, child: Text(label, style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500))),
                Expanded(
                  child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: valueColor)),
                ),
              ],
            ),
            if (divider) const Padding(padding: EdgeInsets.only(top: 6), child: Divider(height: 1, color: kBorder)),
          ],
        ),
      );
}

class TimelineEvent {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final DateTime date;
  final String tag;
  final Color tagColor;
  TimelineEvent({required this.icon, required this.color, required this.title, this.subtitle, required this.date, required this.tag, required this.tagColor});
}

class ActivityTimeline extends StatelessWidget {
  final List<TimelineEvent> events;
  const ActivityTimeline(this.events, {super.key});

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const InfoCard(children: [Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No recent activity.', style: TextStyle(color: kMuted, fontSize: 12))))]);
    }
    return Column(
      children: events.asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        final isLast = i == events.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: e.color.withOpacity(0.12), shape: BoxShape.circle), child: Icon(e.icon, size: 13, color: e.color)),
                  if (!isLast) Expanded(child: Container(width: 1.4, color: kBorder)),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: kDark)),
                            if (e.subtitle != null) Text(e.subtitle!, style: const TextStyle(fontSize: 10.5, color: kMuted)),
                            const SizedBox(height: 2),
                            Text(DateFormat('dd MMM yyyy, hh:mm a').format(e.date), style: const TextStyle(fontSize: 9.5, color: kMuted, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: e.tagColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(e.tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: e.tagColor)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Evidence/attachments for any Tasks-screen item (No Answer evidence,
/// visit photos, dispute proof — spec §33-34). Uses image_picker so this is
/// a real capture flow, not decorative file rows.
class AttachmentsSection extends StatefulWidget {
  final String refId;
  const AttachmentsSection({super.key, required this.refId});

  @override
  State<AttachmentsSection> createState() => _AttachmentsSectionState();
}

class _AttachmentsSectionState extends State<AttachmentsSection> {
  bool _busy = false;

  Future<void> _pick(AppStore store, ImageSource source) async {
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 70);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        store.addAttachment(widget.refId, picked.name, bytes);
      }
    } catch (_) {
      if (mounted) {
        showAppMessage(context, message: 'Could not access camera/gallery on this device.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickDocument(AppStore store) async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
      final picked = result?.files.single;
      if (picked != null && picked.bytes != null) {
        store.addAttachment(widget.refId, picked.name, picked.bytes!);
      }
    } catch (_) {
      if (mounted) {
        showAppMessage(context, message: 'Could not access files on this device.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final files = store.attachmentsForItem(widget.refId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('ATTACHMENTS')),
            Text('${files.length}', style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.bold)),
          ],
        ),
        InfoCard(children: [
          if (files.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('No evidence attached yet.', style: TextStyle(fontSize: 11.5, color: kMuted))),
          ...files.map((f) {
            final fileName = f['fileName'] as String;
            final isImage = _isImageFile(fileName);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => viewAttachment(context, f),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: isImage
                          ? Image.memory(f['bytes'] as Uint8List, width: 40, height: 40, fit: BoxFit.cover)
                          : Container(
                              width: 40,
                              height: 40,
                              color: kRed.withOpacity(0.1),
                              child: const Icon(Icons.picture_as_pdf, color: kRed, size: 20),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fileName, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: kDark), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${f['author']} · ${DateFormat('dd MMM, hh:mm a').format(f['timestamp'])} · Tap to view', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: kMuted),
                      onPressed: () => store.removeAttachment(widget.refId, fileName, f['timestamp']),
                    ),
                  ],
                ),
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: kBlue), foregroundColor: kBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _busy ? null : () => _pick(store, ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 16),
                  label: const Text('Camera', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: kBlue), foregroundColor: kBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _busy ? null : () => _pick(store, ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 16),
                  label: const Text('Gallery', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: kRed), foregroundColor: kRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  onPressed: _busy ? null : () => _pickDocument(store),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('PDF', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }
}

/// Add-a-note section shared across every RE request/task detail screen —
/// shows previously-added notes (was previously silently dropped in
/// unified_task_detail_screen.dart's private version — notes were saved
/// but never displayed back) plus a field to add a new one.
class NotesSection extends StatefulWidget {
  final String refId;
  const NotesSection({super.key, required this.refId});

  @override
  State<NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<NotesSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final notes = store.notesForItem(widget.refId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('NOTES')),
            Text('${notes.length}', style: const TextStyle(fontSize: 11, color: kMuted, fontWeight: FontWeight.bold)),
          ],
        ),
        InfoCard(children: [
          if (notes.isNotEmpty) ...[
            ...notes.map((n) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n['note'] as String, style: const TextStyle(fontSize: 12, color: kDark)),
                      const SizedBox(height: 2),
                      Text('${n['author']} · ${DateFormat('dd MMM, hh:mm a').format(n['timestamp'] as DateTime)}', style: const TextStyle(fontSize: 9.5, color: kMuted)),
                    ],
                  ),
                )),
            const Divider(height: 20),
          ],
          TextField(
            controller: _controller,
            maxLines: 3,
            style: const TextStyle(fontSize: 12.5),
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.all(10), hintText: 'Write your notes here…'),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kNavy, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () {
                if (_controller.text.trim().isEmpty) return;
                store.addItemNote(widget.refId, _controller.text.trim());
                _controller.clear();
                showAppMessage(context, message: 'Note added.');
              },
              child: const Text('Save Note', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ]),
      ],
    );
  }
}
