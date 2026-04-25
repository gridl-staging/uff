import 'dart:math';

String generateUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  String toHex(int value) => value.toRadixString(16).padLeft(2, '0');
  final hexPairs = bytes.map(toHex).toList(growable: false);
  return [
    hexPairs.sublist(0, 4).join(),
    hexPairs.sublist(4, 6).join(),
    hexPairs.sublist(6, 8).join(),
    hexPairs.sublist(8, 10).join(),
    hexPairs.sublist(10, 16).join(),
  ].join('-');
}
