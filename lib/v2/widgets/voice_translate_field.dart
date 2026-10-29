import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final List<TextInputFormatter>? inputFormatters;

  const VoiceTranslateField({
    super.key,
    required this.controller,
    required this.decoration,
    this.maxLines = 3,
    this.inputFormatters,
  });

  @override
  State<VoiceTranslateField> createState() => _VoiceTranslateFieldState();
}

class _VoiceTranslateFieldState extends State<VoiceTranslateField> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  bool _available = false;
  // Whatever was already in the field (typed, or from a previous dictation
  // session) before THIS listening session started. speech_to_text's
  // onResult only ever reports words recognized in the current session, so
  // without this, stopping and starting dictation again — or starting
  // dictation after typing something — silently wiped out everything that
  // came before it.
  String _baseText = '';

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

    _baseText = widget.controller.text;
    setState(() => _listening = true);

    await _speech.listen(
      // BCP-47 format (hyphen, not underscore) — the Android plugin passes
      // this straight to Locale.forLanguageTag(); "hi_IN" fails to parse
      // and silently falls back to the device's default (English) locale.
      listenOptions: stt.SpeechListenOptions(
        localeId: 'hi-IN',
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
      onResult: (result) {
        // result.recognizedWords is scoped to THIS session only — append it
        // to whatever was already there, never replace it outright.
        final combined = _baseText.isEmpty
            ? result.recognizedWords
            : (result.recognizedWords.isEmpty ? _baseText : '$_baseText ${result.recognizedWords}');
        var value = TextEditingValue(text: combined);
        // Dictation sets the controller directly, bypassing the TextField's
        // own formatter pipeline — apply the same formatters (e.g. a
        // word-count cap) here so speaking past the limit can't exceed it
        // either.
        for (final formatter in widget.inputFormatters ?? const []) {
          value = formatter.formatEditUpdate(widget.controller.value, value);
        }
        widget.controller.value = value.copyWith(selection: TextSelection.collapsed(offset: value.text.length));
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
      inputFormatters: widget.inputFormatters,
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
