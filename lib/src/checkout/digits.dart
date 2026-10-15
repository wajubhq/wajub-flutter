import 'package:flutter/services.dart';

/// The `0` of each script whose ten decimal digits follow one another in
/// Unicode: Arabic-Indic, Persian, N'Ko, the Indic scripts, Thai, Lao,
/// Tibetan, Myanmar, Khmer, Mongolian, and the full-width forms.
const _zeros = [
  0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0x0DE6, //
  0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, //
  0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10, //
];

/// [input] with every decimal digit written `0`–`9`: a payer on an Arabic,
/// Persian or other keyboard types the number they see. Other numeric signs
/// (`½`, `Ⅳ`) are left as they are, for the checks to refuse.
String asciiDigits(String input) => String.fromCharCodes(input.runes.map((rune) {
      for (final zero in _zeros) {
        if (rune >= zero && rune <= zero + 9) return 0x30 + rune - zero;
      }
      return rune;
    }));

/// Whether [text] is made of `0`–`9` only, between [min] and [max] of them.
bool isAsciiDigits(String text, {int min = 1, int? max}) => RegExp('^[0-9]{$min,${max ?? ''}}\$').hasMatch(text);

/// A text field filter that writes every decimal digit typed as `0`–`9`.
class AsciiDigitsFormatter extends TextInputFormatter {
  const AsciiDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = asciiDigits(newValue.text);
    if (text == newValue.text) return newValue;
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
