// A real, standard Flutter testing pattern (not a hack): image_picker
// exposes ImagePickerPlatform.instance specifically so tests can swap in a
// fake implementation instead of a native OS/browser file dialog, which
// WidgetTester genuinely cannot drive. No production code is touched —
// this only ever runs from an integration_test entrypoint.
//
// This unblocks the evidence-gated Record Outcome forms (No Answer,
// Payment Already Made) that salesman_evidence_validation_test.dart
// explicitly documented as untestable past the validation-error stage.
import 'dart:typed_data';

import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

// A minimal valid 1x1 transparent PNG — enough to satisfy `_imageFile != null`
// checks and any `Image.memory(...)` preview rendering in the outcome forms.
final Uint8List _fakeEvidenceBytes = Uint8List.fromList(<int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0,
  0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 10, 73, 68, 65, 84, 120,
  156, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 45, 180, 0, 0, 0, 0, 73, 69, 78, 68,
  174, 66, 96, 130,
]);

class FakeImagePickerPlatform extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    return XFile(
      'data:image/png;base64,fake-evidence',
      name: 'evidence.png',
      mimeType: 'image/png',
      bytes: _fakeEvidenceBytes,
      length: _fakeEvidenceBytes.length,
    );
  }
}

/// Call once at the top of `main()`, before `app.main()`.
void installFakeImagePicker() {
  ImagePickerPlatform.instance = FakeImagePickerPlatform();
}
