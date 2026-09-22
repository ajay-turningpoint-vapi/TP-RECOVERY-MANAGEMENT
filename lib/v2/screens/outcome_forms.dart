import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:salesman_mobile/v2/theme/app_theme.dart';
import 'package:salesman_mobile/v2/stores/app_store.dart';
import 'package:salesman_mobile/services/attachment_picker.dart';
import 'package:salesman_mobile/v2/widgets/voice_translate_field.dart';

final _money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// Shared rule for the three amount inputs (PTP promise, dispute, payment
/// already made): a salesman can never record an amount larger than what
/// the customer actually owes. Returns an error string, or null if OK.
/// [maxOutstanding] <= 0 means "unknown" — skip the ceiling check.
String? _amountCeilingError(double amt, double maxOutstanding) {
  if (maxOutstanding > 0 && amt > maxOutstanding) {
    return 'Cannot exceed total outstanding (${_money.format(maxOutstanding)})';
  }
  return null;
}

class BaseOutcomeForm extends StatefulWidget {
  final String title;
  final Widget child;
  // Returns true if validation passed and the outcome was actually
  // submitted upstream; false if validation failed (field errors were set
  // via setState) — the swipe button uses this to decide whether to lock
  // in as confirmed or snap back with a vibration. Awaited by the swipe
  // button, which holds a spinner at the end of the track until the real
  // submit (network or local SQLite write) actually finishes — otherwise
  // "SAVED" would appear before the write is done, hiding a slow
  // connection or a later failure behind a false success state.
  final Future<bool> Function() onSave;
  final String saveText;

  const BaseOutcomeForm({
    super.key,
    required this.title,
    required this.child,
    required this.onSave,
    this.saveText = 'Save Outcome',
  });

  @override
  State<BaseOutcomeForm> createState() => _BaseOutcomeFormState();
}

class _BaseOutcomeFormState extends State<BaseOutcomeForm> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 16, right: 16, top: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(widget.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B2B48))),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text('* All fields marked are mandatory',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 10, color: Color(0xFF5A6B87))),
              ),
            ],
          ),
          const SizedBox(height: 20),
          widget.child,
          const SizedBox(height: 32),
          SwipeToConfirmButton(label: widget.saveText.toUpperCase(), onConfirmed: widget.onSave),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// "Slide to confirm" replacement for the old tap-to-save button — makes an
/// irreversible action (recording an outcome) require a deliberate drag
/// gesture instead of one accidental tap, and gives clear live feedback
/// (thumb tracks the finger, track fills in behind it) as the user swipes.
///
/// Validation-gated: [onConfirmed] runs the form's own validation
/// synchronously and returns whether it passed. Only on a true result does
/// the thumb lock in as confirmed — a failed validation snaps the thumb
/// back with a shake and a vibration instead, so the button never shows
/// "SAVED" for an outcome that was actually rejected.
class SwipeToConfirmButton extends StatefulWidget {
  final String label;
  final Future<bool> Function() onConfirmed;
  final double height;

  const SwipeToConfirmButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.height = 56,
  });

  @override
  State<SwipeToConfirmButton> createState() => _SwipeToConfirmButtonState();
}

class _SwipeToConfirmButtonState extends State<SwipeToConfirmButton> with TickerProviderStateMixin {
  late AnimationController _snapCtrl;
  // Idle "this is swipeable" hint — a slow, continuous back-and-forth
  // nudge on the arrow so the button reads as live/interactive even
  // before anyone touches it, not a static bar.
  late AnimationController _hintCtrl;
  // Brief horizontal shake played over the whole track on a validation
  // failure, alongside the haptic buzz.
  late AnimationController _shakeCtrl;

  double _dragX = 0; // current thumb offset, px
  double _maxDrag = 0; // set from LayoutBuilder each build
  bool _confirmed = false;
  bool _dragging = false;
  // True from the moment the swipe gesture commits until onConfirmed's
  // Future actually resolves — the thumb is locked at the end of the
  // track showing a spinner, not yet "SAVED".
  bool _pending = false;

  static const double _thumbSize = 46;
  static const Color _trackColor = Color(0xFF0052CC);
  static const Color _doneColor = Color(0xFF2E7D32);
  static const Color _errorColor = Color(0xFFDC2626);

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _hintCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    _hintCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _snapBack() {
    final anim = Tween<double>(begin: _dragX, end: 0).animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    void tick() => setState(() => _dragX = anim.value);
    anim.addListener(tick);
    _snapCtrl.forward(from: 0).whenCompleteOrCancel(() => anim.removeListener(tick));
  }

  // Locks the thumb at the end of the track without marking the action
  // confirmed — used both while the real submit is still pending (spinner
  // shown at the end position) and, separately, once it actually succeeds.
  void _animateToEnd() {
    final anim = Tween<double>(begin: _dragX, end: _maxDrag).animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut));
    void tick() => setState(() => _dragX = anim.value);
    anim.addListener(tick);
    _snapCtrl.forward(from: 0).whenCompleteOrCancel(() => anim.removeListener(tick));
  }

  /// Validation failed — buzz the device and shake the whole track red
  /// while the thumb snaps all the way back to zero, so the rejection is
  /// unmistakable rather than a silent no-op.
  void _rejectWithShake() {
    // Two haptics — heavyImpact reads on phones where the plain vibrate()
    // long-buzz is suppressed by system touch-feedback settings.
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();
    _snapBack();
    _shakeCtrl.forward(from: 0);
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    setState(() => _dragging = false);
    if (_maxDrag <= 0 || _dragX < _maxDrag * 0.82) {
      _snapBack();
      return;
    }
    // Validation runs the instant the user commits the swipe — never after
    // the thumb has already visually locked in. Once validation passes,
    // the thumb locks at the end showing a spinner (not yet "SAVED") until
    // the real submit — network call or local SQLite write — actually
    // finishes, so a slow connection never looks like a completed save.
    setState(() => _pending = true);
    _animateToEnd();
    bool passed;
    try {
      passed = await widget.onConfirmed();
    } catch (_) {
      passed = false;
    }
    if (!mounted) return;
    setState(() => _pending = false);
    if (passed) {
      setState(() => _confirmed = true);
    } else {
      _rejectWithShake();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _maxDrag = constraints.maxWidth - _thumbSize - 6;
        final progress = _maxDrag > 0 ? (_dragX / _maxDrag).clamp(0.0, 1.0) : 0.0;
        final trackColor = Color.lerp(_trackColor, _doneColor, progress)!;

        return AnimatedBuilder(
          animation: Listenable.merge([_hintCtrl, _shakeCtrl]),
          builder: (context, _) {
            // Decaying left-right shake — 4 quick oscillations that taper
            // off to zero by the time the controller finishes.
            final shakeT = _shakeCtrl.value;
            final shakeOffset = math.sin(shakeT * math.pi * 8) * (1 - shakeT) * 10;
            final shaking = _shakeCtrl.isAnimating;
            final trackColorNow = shaking ? Color.lerp(trackColor, _errorColor, (1 - shakeT).clamp(0.0, 1.0))! : trackColor;
            // Idle hint: the arrow gently nudges right and back, only when
            // untouched, not confirmed, not pending, and not mid-shake.
            final hintNudge = (!_dragging && !_confirmed && !_pending && !shaking) ? _hintCtrl.value * 8 : 0.0;

            return Transform.translate(
              offset: Offset(shaking ? shakeOffset : 0, 0),
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: trackColorNow,
                  borderRadius: BorderRadius.circular(widget.height / 2),
                ),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    // Label — fades out as the thumb approaches so it never
                    // looks like the thumb is covering unread text.
                    Center(
                      child: AnimatedOpacity(
                        opacity: _confirmed ? 0 : (1 - progress * 1.3).clamp(0.0, 1.0),
                        duration: const Duration(milliseconds: 100),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_confirmed ? 'SAVED' : (_pending ? 'SAVING…' : widget.label),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.0)),
                            if (!_confirmed && !_pending) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.double_arrow_rounded, color: Colors.white70, size: 18),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_confirmed)
                      const Center(
                        child: Icon(Icons.check_circle, color: Colors.white, size: 24),
                      ),
                    // Draggable thumb — only while the action is still
                    // pending. Once confirmed it's removed so the button
                    // shows just the single big centred check, not also a
                    // small white-disc tick sitting on the track.
                    if (!_confirmed)
                      AnimatedPositioned(
                        duration: (_snapCtrl.isAnimating || _dragging) ? Duration.zero : const Duration(milliseconds: 60),
                        left: 3 + _dragX + hintNudge,
                        top: 3,
                        child: GestureDetector(
                          onHorizontalDragStart: _pending ? null : (_) => setState(() => _dragging = true),
                          onHorizontalDragUpdate: _pending
                              ? null
                              : (details) {
                                  setState(() {
                                    _dragX = (_dragX + details.delta.dx).clamp(0.0, _maxDrag);
                                  });
                                },
                          onHorizontalDragEnd: _pending ? null : _handleDragEnd,
                          child: Container(
                            width: _thumbSize,
                            height: _thumbSize,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                            child: _pending
                                ? Padding(
                                    padding: const EdgeInsets.all(13),
                                    child: CircularProgressIndicator(strokeWidth: 2.2, color: trackColorNow),
                                  )
                                : Icon(
                                    Icons.arrow_forward_rounded,
                                    color: trackColorNow,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Helper methods for date/time/image
Future<DateTime?> _pickDate(BuildContext context, {DateTime? initialDate}) async {
  return showDatePicker(
    context: context,
    initialDate: initialDate ?? DateTime.now(),
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
}

Future<TimeOfDay?> _pickTime(BuildContext context, {TimeOfDay? initialTime}) async {
  return showTimePicker(
    context: context,
    initialTime: initialTime ?? TimeOfDay.now(),
  );
}

/// Lets the salesman either open the camera or pick an existing screenshot
/// from the gallery — used for every "Capture / Upload Evidence" button in
/// the Record Outcome forms.
Future<XFile?> _pickImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          const Text('Add evidence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48))),
          const SizedBox(height: 2),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE3EDFB), child: Icon(Icons.photo_camera, color: Color(0xFF0052CC))),
            title: const Text('Take photo', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Open the camera'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFDCFCE7), child: Icon(Icons.photo_library, color: Color(0xFF16A34A))),
            title: const Text('Choose from gallery', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Pick an existing screenshot'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return ImagePicker().pickImage(source: source, imageQuality: 85);
}

// Camera / gallery / PDF picker — see lib/services/attachment_picker.dart's
// pickEvidenceFile, shared with the dispute chat threads.

// 1. PTP
class PtpOutcomeForm extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  final double maxOutstanding;

  /// Pre-fills "Person Spoken To" (e.g. the contact from this customer's
  /// last recorded interaction). The salesman can still edit it.
  final String? initialPerson;

  const PtpOutcomeForm({super.key, required this.onSubmit, this.maxOutstanding = 0, this.initialPerson});
  @override
  State<PtpOutcomeForm> createState() => _PtpOutcomeFormState();
}

class _PtpOutcomeFormState extends State<PtpOutcomeForm> {
  final _amountCtrl = TextEditingController();
  late final _personCtrl = TextEditingController(text: widget.initialPerson ?? '');
  final _notesCtrl = TextEditingController();
  String _mode = 'Phone Call';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _amountError;
  String? _personError;
  String? _dateTimeError;

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B2B48))),
    );
  }

  InputDecoration _getInputDeco(String hint, {Widget? suffixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA0AEC0), fontSize: 14),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0052CC))),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateStr = _selectedDate == null ? 'Select Date' : DateFormat('dd MMM yyyy').format(_selectedDate!);
    String timeStr = _selectedTime == null ? 'Select Time' : _selectedTime!.format(context);

    return BaseOutcomeForm(
      title: 'PTP Details',
      onSave: () async {
        setState(() {
          _amountError = null;
          _personError = null;
          _dateTimeError = null;
        });
        bool hasError = false;

        if (_selectedDate == null || _selectedTime == null) {
          setState(() => _dateTimeError = 'Please select both Date and Time');
          hasError = true;
        }
        final amt = double.tryParse(_amountCtrl.text) ?? 0.0;
        if (amt <= 0) {
          setState(() => _amountError = 'Must be greater than 0');
          hasError = true;
        } else if (_amountCeilingError(amt, widget.maxOutstanding) != null) {
          setState(() => _amountError = _amountCeilingError(amt, widget.maxOutstanding));
          hasError = true;
        }
        if (_personCtrl.text.trim().isEmpty) {
          setState(() => _personError = 'Required');
          hasError = true;
        }

        if (hasError) return false;

        await widget.onSubmit({
          'amount': amt,
          'person': _personCtrl.text.trim(),
          'mode': _mode,
          'date': _selectedDate,
          'time': _selectedTime,
          'notes': _notesCtrl.text.trim(),
        });
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLabel('Promise Amount *'),
          TextField(controller: _amountCtrl, decoration: _getInputDeco('Enter promised amount').copyWith(errorText: _amountError, helperText: widget.maxOutstanding > 0 ? 'Max ${_money.format(widget.maxOutstanding)} (total outstanding)' : null), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Promise Date *'),
                    InkWell(
                      onTap: () async {
                        final d = await _pickDate(context);
                        if (d != null) setState(() => _selectedDate = d);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(dateStr, style: TextStyle(color: _selectedDate == null ? const Color(0xFFA0AEC0) : const Color(0xFF1B2B48), fontSize: 14)),
                            const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFF5A6B87)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Promise Time *'),
                    InkWell(
                      onTap: () async {
                        final t = await _pickTime(context);
                        if (t != null) setState(() => _selectedTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withOpacity(0.3)), borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(timeStr, style: TextStyle(color: _selectedTime == null ? const Color(0xFFA0AEC0) : const Color(0xFF1B2B48), fontSize: 14)),
                            const Icon(Icons.access_time, size: 18, color: Color(0xFF5A6B87)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_dateTimeError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_dateTimeError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
          const SizedBox(height: 16),

          _buildLabel('Person Spoken To *'),
          TextField(controller: _personCtrl, decoration: _getInputDeco('Enter name of person spoken to').copyWith(errorText: _personError)),
          const SizedBox(height: 16),

          _buildLabel('Mode of Communication *'),
          DropdownButtonFormField<String>(
            dropdownColor: Colors.white,
            style: const TextStyle(color: Color(0xFF1B2B48), fontSize: 14),
            value: _mode,
            decoration: _getInputDeco('Select mode'),
            items: ['Phone Call', 'WhatsApp'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => _mode = v!),
          ),
          const SizedBox(height: 16),
          
          _buildLabel('Notes (Optional)'),
          TextField(controller: _notesCtrl, maxLines: 2, decoration: _getInputDeco('Add any additional notes here')),
        ],
      ),
    );
  }
}

// 2. Will Confirm
class WillConfirmForm extends StatefulWidget {
  final Future<void> Function(DateTime, TimeOfDay) onSubmit;
  const WillConfirmForm({super.key, required this.onSubmit});
  @override
  State<WillConfirmForm> createState() => _WillConfirmFormState();
}

class _WillConfirmFormState extends State<WillConfirmForm> {
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _dateTimeError;

  @override
  Widget build(BuildContext context) {
    String dateStr = _selectedDate == null ? 'Select Follow-up Date' : DateFormat('yyyy-MM-dd').format(_selectedDate!);
    String timeStr = _selectedTime == null ? 'Select Follow-up Time' : _selectedTime!.format(context);

    return BaseOutcomeForm(
      title: 'Will Confirm',
      onSave: () async {
        setState(() => _dateTimeError = null);
        if (_selectedDate == null || _selectedTime == null) {
          setState(() => _dateTimeError = 'Please select Date and Time');
          return false;
        }
        await widget.onSubmit(_selectedDate!, _selectedTime!);
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Customer needs to check/approve. A follow-up is required.', style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await _pickDate(context);
              if (d != null) setState(() => _selectedDate = d);
            }, 
            icon: const Icon(Icons.calendar_month),
            label: Text(dateStr),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final t = await _pickTime(context);
              if (t != null) setState(() => _selectedTime = t);
            }, 
            icon: const Icon(Icons.access_time),
            label: Text(timeStr),
          ),
          if (_dateTimeError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_dateTimeError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
        ],
      ),
    );
  }
}

// 3. Payment Already Made
class PaymentAlreadyMadeForm extends StatefulWidget {
  final Future<void> Function(double, XFile?) onSubmit;
  final double maxOutstanding;
  const PaymentAlreadyMadeForm({super.key, required this.onSubmit, this.maxOutstanding = 0});
  @override
  State<PaymentAlreadyMadeForm> createState() => _PaymentAlreadyMadeFormState();
}

class _PaymentAlreadyMadeFormState extends State<PaymentAlreadyMadeForm> {
  final _amountCtrl = TextEditingController();
  XFile? _imageFile;
  String? _amountError;
  String? _imageError;

  @override
  Widget build(BuildContext context) {
    return BaseOutcomeForm(
      title: 'Payment Already Made',
      onSave: () async {
        setState(() {
          _amountError = null;
          _imageError = null;
        });
        bool hasError = false;

        final amt = double.tryParse(_amountCtrl.text) ?? 0.0;
        if (amt <= 0) {
          setState(() => _amountError = 'Must be greater than 0');
          hasError = true;
        } else if (_amountCeilingError(amt, widget.maxOutstanding) != null) {
          setState(() => _amountError = _amountCeilingError(amt, widget.maxOutstanding));
          hasError = true;
        }
        if (_imageFile == null) {
          setState(() => _imageError = 'Evidence screenshot is required');
          hasError = true;
        }

        if (hasError) return false;
        await widget.onSubmit(amt, _imageFile);
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Customer claims payment was already transferred.', style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 16),
          TextField(controller: _amountCtrl, decoration: InputDecoration(labelText: 'Claimed Amount (₹)', errorText: _amountError, helperText: widget.maxOutstanding > 0 ? 'Max ${_money.format(widget.maxOutstanding)} (total outstanding)' : null), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          if (_imageFile == null)
            OutlinedButton.icon(
              onPressed: () async {
                final file = await pickEvidenceFile(context);
                if (file != null) setState(() => _imageFile = file);
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Evidence'),
            )
          else
            _AttachmentPreview(
              file: _imageFile!,
              onEdit: () async {
                final file = await pickEvidenceFile(context);
                if (file != null) setState(() => _imageFile = file);
              },
            ),
          if (_imageError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_imageError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
        ],
      ),
    );
  }
}

// 4. Dispute
class DisputeForm extends StatefulWidget {
  final Future<void> Function(double, String, XFile?) onSubmit;
  final double maxOutstanding;
  const DisputeForm({super.key, required this.onSubmit, this.maxOutstanding = 0});
  @override
  State<DisputeForm> createState() => _DisputeFormState();
}

class _DisputeFormState extends State<DisputeForm> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  XFile? _imageFile;
  String? _amountError;
  String? _reasonError;

  @override
  Widget build(BuildContext context) {
    return BaseOutcomeForm(
      title: 'Dispute / Issue',
      onSave: () async {
        setState(() {
          _amountError = null;
          _reasonError = null;
        });
        bool hasError = false;

        final amt = double.tryParse(_amountCtrl.text) ?? 0.0;
        if (amt <= 0) {
          setState(() => _amountError = 'Must be greater than 0');
          hasError = true;
        } else if (_amountCeilingError(amt, widget.maxOutstanding) != null) {
          setState(() => _amountError = _amountCeilingError(amt, widget.maxOutstanding));
          hasError = true;
        }
        if (_reasonCtrl.text.trim().isEmpty) {
          setState(() => _reasonError = 'Required');
          hasError = true;
        }

        if (hasError) return false;
        await widget.onSubmit(amt, _reasonCtrl.text.trim(), _imageFile);
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: _amountCtrl, decoration: InputDecoration(labelText: 'Disputed Amount (₹)', errorText: _amountError, helperText: widget.maxOutstanding > 0 ? 'Max ${_money.format(widget.maxOutstanding)} (total outstanding)' : null), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          VoiceTranslateField(controller: _reasonCtrl, decoration: InputDecoration(labelText: 'Detailed Reason for Dispute', errorText: _reasonError), maxLines: 3),
          const SizedBox(height: 16),
          if (_imageFile == null)
            OutlinedButton.icon(
              onPressed: () async {
                final file = await pickEvidenceFile(context);
                if (file != null) setState(() => _imageFile = file);
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Evidence (Optional)'),
            )
          else
            _AttachmentPreview(
              file: _imageFile!,
              onEdit: () async {
                final file = await pickEvidenceFile(context);
                if (file != null) setState(() => _imageFile = file);
              },
            ),
        ],
      ),
    );
  }
}

// 5. Internal Action
class InternalActionForm extends StatefulWidget {
  final Future<void> Function(String, XFile?) onSubmit;
  const InternalActionForm({super.key, required this.onSubmit});
  @override
  State<InternalActionForm> createState() => _InternalActionFormState();
}

class _InternalActionFormState extends State<InternalActionForm> {
  String _dependency = 'Updated Ledger Required';
  final _otherCtrl = TextEditingController();
  String? _otherError;
  XFile? _attachment;

  @override
  Widget build(BuildContext context) {
    return BaseOutcomeForm(
      title: 'Internal Action Required',
      onSave: () async {
        setState(() => _otherError = null);
        if (_dependency == 'Other' && _otherCtrl.text.trim().isEmpty) {
          setState(() => _otherError = 'Please enter the dependency');
          return false;
        }
        await widget.onSubmit(_dependency == 'Other' ? _otherCtrl.text.trim() : _dependency, _attachment);
        return true;
      },
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            dropdownColor: Colors.white,
            style: const TextStyle(color: Color(0xFF1B2B48), fontSize: 16),
            value: _dependency,
            decoration: const InputDecoration(labelText: 'Required Dependency'),
            items: [
              'Updated Ledger Required',
              'Invoice Correction',
              'Document Required',
              'Financial Clarification',
              'Customer Detail Correction',
              'Other',
            ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => _dependency = v!),
          ),
          if (_dependency == 'Other') ...[
            const SizedBox(height: 16),
            TextField(
              controller: _otherCtrl,
              decoration: InputDecoration(labelText: 'Please specify', errorText: _otherError),
              maxLines: 2,
            ),
          ],
          const SizedBox(height: 16),
          if (_attachment == null)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () async {
                final f = await pickEvidenceFile(context);
                if (f != null) setState(() => _attachment = f);
              },
              icon: const Icon(Icons.attach_file),
              label: const Text('Attach photo or PDF (optional)', maxLines: 1, overflow: TextOverflow.ellipsis),
            )
          else ...[
            const SizedBox(height: 10),
            _AttachmentPreview(
              file: _attachment!,
              onEdit: () async {
                final f = await pickEvidenceFile(context);
                if (f != null) setState(() => _attachment = f);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Small inline preview for a just-picked evidence file: a thumbnail for an
/// image, a red PDF card for a PDF (which comes back as a bytes-backed
/// [XFile] with no readable path, so there's nothing to render but the
/// icon + name).
class _AttachmentPreview extends StatelessWidget {
  final XFile file;
  // When set, overlays a small edit button on the preview's top-right
  // corner (re-opens the same picker to swap the file) — the only way to
  // change a picked attachment once it's shown; there's deliberately no
  // separate "Attached: <name>" pill/border/checkmark above the preview
  // anymore, since the thumbnail itself already shows what was picked.
  final VoidCallback? onEdit;
  const _AttachmentPreview({required this.file, this.onEdit});

  bool get _isPdf =>
      file.mimeType == 'application/pdf' ||
      file.name.toLowerCase().endsWith('.pdf');

  Widget _editButton() {
    return Positioned(
      top: 6,
      right: 6,
      child: Material(
        color: Colors.black.withOpacity(0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onEdit,
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Icon(Icons.edit, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPdf) {
      return Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.picture_as_pdf, color: Color(0xFFDC2626), size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: Color(0xFF1B2B48))),
                      const SizedBox(height: 2),
                      const Text('PDF document attached',
                          style: TextStyle(fontSize: 10.5, color: Color(0xFFB91C1C))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onEdit != null) _editButton(),
        ],
      );
    }
    // Image evidence — camera/gallery XFiles have a real path on disk.
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(file.path),
            height: 120,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              height: 120,
              alignment: Alignment.center,
              color: const Color(0xFFF1F5F9),
              child: const Icon(Icons.image_outlined, color: Color(0xFF94A3B8), size: 32),
            ),
          ),
        ),
        if (onEdit != null) _editButton(),
      ],
    );
  }
}

// 6. No Answer
class NoAnswerForm extends StatefulWidget {
  final Future<void> Function(XFile?) onSubmit;
  final int attemptNumber;
  const NoAnswerForm({super.key, required this.onSubmit, required this.attemptNumber});
  @override
  State<NoAnswerForm> createState() => _NoAnswerFormState();
}

class _NoAnswerFormState extends State<NoAnswerForm> {
  XFile? _imageFile;
  String? _imageError;

  String _attemptStageLabel(int attempt) {
    if (attempt <= 1) return 'Primary Contact';
    if (attempt == 2) return 'Alternate Contact / Carpenter';
    return 'Additional Controlled Contact';
  }

  @override
  Widget build(BuildContext context) {
    return BaseOutcomeForm(
      title: 'No Answer',
      onSave: () async {
        setState(() => _imageError = null);
        if (_imageFile == null) {
          setState(() => _imageError = 'Screenshot evidence is required');
          return false;
        }
        // Was widget.onSubmit() — the captured screenshot was required by
        // this very validation, then silently discarded: never uploaded,
        // never stored, never visible anywhere. Now actually threaded
        // through to record-outcome (see AppStore.recordOutcome's
        // screenshot param) so it lands in Customer History for real.
        await widget.onSubmit(_imageFile);
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Current Attempt: ${_attemptStageLabel(widget.attemptNumber)} (Attempt ${widget.attemptNumber})\n\nProof of call (screenshot) is required.'
            // Was hardcoded to >= 3, but the server's real threshold
            // (customerService.recordOutcome's NO_ANSWER_THRESHOLD) is 2 —
            // this warning never appeared on the actual call that triggers
            // the auto-created Physical Visit, only on a later attempt
            // number that (since the server resets the counter once the
            // threshold fires) could never actually be reached.
            '${widget.attemptNumber >= AppStore.noAnswerThreshold ? '\n\nThis is the final controlled attempt — a Physical Visit will be created automatically.' : ''}',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _imageFile != null ? AppTheme.accentEmerald : null),
            onPressed: () async {
              final file = await _pickImage(context);
              if (file != null) setState(() => _imageFile = file);
            }, 
            icon: Icon(_imageFile != null ? Icons.check : Icons.add_a_photo_outlined),
            label: Text(_imageFile != null ? 'Attached: ${_imageFile!.name}' : 'Add Call Screenshot'),
          ),
          if (_imageFile != null)
            FutureBuilder(
              future: _imageFile!.readAsBytes(),
              builder: (ctx, AsyncSnapshot snap) {
                if (snap.hasData) return Padding(padding: const EdgeInsets.only(top: 8), child: Image.memory(snap.data, height: 80));
                return const SizedBox();
              },
            ),
          if (_imageError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_imageError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12))),
        ],
      ),
    );
  }
}

// 7. Unable To Commit
// No next-action date/time picker — the system now decides the call-back
// schedule automatically (server: customerService.js's 'Customer Refused'
// branch + missedDeadlineService.sweepRefusedCycle's growing 2/3/4/5-day
// cadence), not the salesperson.
class UnableToCommitForm extends StatefulWidget {
  final Future<void> Function(String, String) onSubmit;
  const UnableToCommitForm({super.key, required this.onSubmit});
  @override
  State<UnableToCommitForm> createState() => _UnableToCommitFormState();
}

class _UnableToCommitFormState extends State<UnableToCommitForm> {
  String _reason = 'Cash flow problem';
  final _notesCtrl = TextEditingController();
  String? _notesError;

  @override
  Widget build(BuildContext context) {
    return BaseOutcomeForm(
      title: 'Unable To Commit',
      onSave: () async {
        setState(() => _notesError = null);
        if (_reason == 'Other' && _notesCtrl.text.trim().isEmpty) {
          setState(() => _notesError = 'Notes required for "Other" reason');
          return false;
        }
        await widget.onSubmit(_reason, _notesCtrl.text.trim());
        return true;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            dropdownColor: Colors.white,
            style: const TextStyle(color: Color(0xFF1B2B48), fontSize: 16),
            value: _reason,
            decoration: const InputDecoration(labelText: 'Structured Reason'),
            items: [
              'Cash flow problem',
              'Owner unavailable',
              'Awaiting external funds',
              'Other'
            ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
            onChanged: (v) => setState(() => _reason = v!),
          ),
          const SizedBox(height: 16),
          VoiceTranslateField(controller: _notesCtrl, decoration: InputDecoration(labelText: 'Additional Notes', errorText: _notesError), maxLines: 2),
        ],
      ),
    );
  }
}
