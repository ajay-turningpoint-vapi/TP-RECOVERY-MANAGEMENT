import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:salesman_mobile/widgets/app_message.dart';

/// Opens the device's dialer pre-filled with [phoneNumber] — the shared
/// click-to-call entry point every screen with a customer/salesman phone
/// number uses, so there's exactly one place that handles sanitizing the
/// number and the "no dialer app / couldn't launch" failure case.
Future<void> callNumber(BuildContext context, String? phoneNumber) async {
  if (phoneNumber == null || phoneNumber.trim().isEmpty) {
    showAppMessage(context, message: 'No phone number on file for this contact.', isError: true);
    return;
  }

  // BUSY-sourced numbers sometimes carry more than one number in one
  // string (e.g. '9925015086 (a/c Mithun.bhai),9638867777') — see the
  // server's own widened-column comment on customers.contact_number for
  // the same real data. Dial only the first one; a raw tel: URI with
  // commas/parentheses in it fails to launch at all on most dialers.
  final firstNumber = phoneNumber.split(RegExp(r'[,/]')).first;
  final digitsOnly = firstNumber.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digitsOnly.isEmpty) {
    showAppMessage(context, message: 'This phone number could not be dialed.', isError: true);
    return;
  }

  final uri = Uri(scheme: 'tel', path: digitsOnly);
  try {
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      showAppMessage(context, message: 'Could not open the dialer on this device.', isError: true);
    }
  } catch (_) {
    if (context.mounted) {
      showAppMessage(context, message: 'Could not open the dialer on this device.', isError: true);
    }
  }
}

/// The first dialable number out of a (possibly multi-number) BUSY string,
/// as digits only (keeps a leading +). Empty if nothing usable.
String _firstDialableDigits(String phoneNumber) {
  final firstNumber = phoneNumber.split(RegExp(r'[,/]')).first;
  return firstNumber.replaceAll(RegExp(r'[^0-9+]'), '');
}

/// Opens a WhatsApp chat with [phoneNumber]. A bare 10-digit number is
/// assumed Indian (+91), matching the customer base; anything already
/// carrying a country code (11+ digits, or a leading +) is used as-is.
Future<void> whatsAppNumber(BuildContext context, String? phoneNumber) async {
  if (phoneNumber == null || phoneNumber.trim().isEmpty) {
    showAppMessage(context, message: 'No phone number on file for this contact.', isError: true);
    return;
  }
  var digits = _firstDialableDigits(phoneNumber).replaceAll('+', '');
  if (digits.length == 10) digits = '91$digits';
  if (digits.isEmpty) {
    showAppMessage(context, message: 'This phone number could not be used for WhatsApp.', isError: true);
    return;
  }
  final uri = Uri.parse('https://wa.me/$digits');
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      showAppMessage(context, message: 'Could not open WhatsApp on this device.', isError: true);
    }
  } catch (_) {
    if (context.mounted) {
      showAppMessage(context, message: 'Could not open WhatsApp on this device.', isError: true);
    }
  }
}

/// Tapping a customer/salesman phone number: ask whether to Call or message
/// on WhatsApp, then route to [callNumber] / [whatsAppNumber].
Future<void> contactActions(BuildContext context, String? phoneNumber) async {
  if (phoneNumber == null || phoneNumber.trim().isEmpty) {
    showAppMessage(context, message: 'No phone number on file for this contact.', isError: true);
    return;
  }
  final display = phoneNumber.split(RegExp(r'[,/]')).first.trim();
  await showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Text(display, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1B2B48))),
          const SizedBox(height: 4),
          const Text('How do you want to reach this contact?', style: TextStyle(fontSize: 12, color: Color(0xFF5A6B87))),
          const SizedBox(height: 8),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE3EDFB), child: Icon(Icons.call, color: Color(0xFF0052CC))),
            title: const Text('Call', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Open the phone dialer'),
            onTap: () {
              Navigator.pop(sheetCtx);
              callNumber(context, phoneNumber);
            },
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFDCFCE7), child: Icon(Icons.chat, color: Color(0xFF16A34A))),
            title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Open a WhatsApp chat'),
            onTap: () {
              Navigator.pop(sheetCtx);
              whatsAppNumber(context, phoneNumber);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// A phone number rendered as a tappable, visually-obvious call target —
/// the standard click-to-call row used across customer/salesman detail
/// screens instead of a plain `Text(phone)`.
class CallablePhoneNumber extends StatelessWidget {
  final String? phoneNumber;
  final TextStyle? style;
  final Color iconColor;
  final double iconSize;

  const CallablePhoneNumber({
    super.key,
    required this.phoneNumber,
    this.style,
    this.iconColor = const Color(0xFF2563EB),
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final hasNumber = phoneNumber != null && phoneNumber!.trim().isNotEmpty;
    return InkWell(
      onTap: hasNumber ? () => contactActions(context, phoneNumber) : null,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call, size: iconSize, color: hasNumber ? iconColor : Colors.grey),
          const SizedBox(width: 4),
          Text(
            hasNumber ? phoneNumber! : 'No phone number',
            style: (style ?? const TextStyle(fontSize: 12)).copyWith(
              color: hasNumber ? iconColor : Colors.grey,
              decoration: hasNumber ? TextDecoration.underline : null,
            ),
          ),
        ],
      ),
    );
  }
}
