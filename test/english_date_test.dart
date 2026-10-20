import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/hebrew_utils.dart';

void main() {
  test('an English Hebrew date uses English month and Arabic numbers', () {
    final jewish = JewishDate()..setJewishDate(5786, 5, 23);

    final text = formatHebrewDate(jewish, english: true);

    expect(text, contains('23'));
    expect(text, contains('Av'));
    expect(text, contains('5786'));
    expect(text, isNot(contains('אב')));
  });
}
