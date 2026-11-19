import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planify/main.dart';

TextEditingValue v(String t, int at) => TextEditingValue(text: t, selection: TextSelection.collapsed(offset: at));

void main() {
  test('Enter on a bullet starts the next one', () {
    final r = continueBullet(v('- milk', 6), v('- milk\n', 7));
    expect(r.text, '- milk\n- ');
    expect(r.selection.baseOffset, 9);
  });

  test('Enter on an empty bullet ends the list', () {
    final r = continueBullet(v('- milk\n- ', 9), v('- milk\n- \n', 10));
    expect(r.text, '- milk\n');
    expect(r.selection.baseOffset, 7);
  });

  test('Enter mid-list in the middle of text', () {
    final r = continueBullet(v('- ab\nend', 3), v('- a\nb\nend', 4));
    expect(r.text, '- a\n- b\nend');
  });

  test('plain text and non-newline edits are untouched', () {
    expect(continueBullet(v('hi', 2), v('hi\n', 3)).text, 'hi\n');
    expect(continueBullet(v('- a', 3), v('- ab', 4)).text, '- ab');
  });
}
