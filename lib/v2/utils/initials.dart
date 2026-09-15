/// A safe 1–2 character avatar label for a display name.
///
/// Names coming from the BUSY sync are not guaranteed to be non-empty or
/// longer than one character, and a bare `name.substring(0, 2)` throws a
/// RangeError mid-build for those rows. This never throws.
String avatarInitials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length > 1) {
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
  final one = parts.first;
  return (one.length >= 2 ? one.substring(0, 2) : one).toUpperCase();
}
