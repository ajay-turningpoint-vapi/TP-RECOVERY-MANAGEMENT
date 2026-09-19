import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// A text field with an optional mic button: salesman speaks in Hindi and
/// the recognized Hindi text fills the field live as they talk. The mic is
/// purely additive — the field behaves like a normal [TextField] and can
/// always be typed into directly, so a device with no mic/speech support
/// just falls back to the keyboard.
class VoiceTranslateField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final int maxLines;

  const VoiceTranslateField({
    super.key,
    required this.controller,
    required this.decoration,
    this.maxLines = 3,
  });

  @override
  State<VoiceTranslateField> createState() => _VoiceTranslateFieldState();
}

class _VoiceTranslateFieldState extends State<VoiceTranslateField> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _available = false;

  Future<bool> _ensureInitialized() async {
    if (_available) return true;
    _available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'notListening' || status == 'done') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    return _available;
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final ok = await _ensureInitialized();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice input isn\'t available on this device — please type instead.')),
      );
      return;
    }

    setState(() => _listening = true);

    await _speech.listen(
      // BCP-47 format (hyphen, not underscore) — the Android plugin passes
      // this straight to Locale.forLanguageTag(); "hi_IN" fails to parse
      // and silently falls back to the device's default (English) locale.
      localeId: 'hi-IN',
      cancelOnError: true,
      partialResults: true,
      listenMode: stt.ListenMode.dictation,
      onResult: (result) {
        widget.controller.text = result.recognizedWords;
        widget.controller.selection = TextSelection.collapsed(offset: widget.controller.text.length);
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      maxLines: widget.maxLines,
      decoration: widget.decoration.copyWith(
        suffixIcon: IconButton(
          icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Colors.red : null),
          tooltip: _listening ? 'Stop' : 'हिंदी में बोलें',
          onPressed: _toggleListening,
        ),
      ),
    );
  }
}
