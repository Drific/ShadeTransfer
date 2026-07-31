// test/encoding_test.dart

test('round-trip for random strings', () {
  for (int i = 0; i < 500; i++) {
    final len = 1 + (i % 20);
    final original = EncodingService.randomString(len);
    final decoded = EncodingService.decodeBigInt(original);
    final reencoded = EncodingService.encodeBigInt(decoded, minLength: len);
    expect(reencoded, original, reason: 'Failed at $i');
  }
});