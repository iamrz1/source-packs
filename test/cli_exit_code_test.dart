import 'dart:io';

import 'package:test/test.dart';

void main() {
  // `main`'s return value is ignored by the Dart VM. Every failure used to exit
  // 0, so neither CI nor the live check could ever fail.
  test('the command line exits with the code a command returns', () async {
    final result = await Process.run('dart', ['run', 'bin/pack.dart']);

    expect(result.exitCode, 64);
  });
}
