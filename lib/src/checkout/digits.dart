import 'package:flutter/services.dart';

/// The `0` of every run of ten decimal digits Unicode has (general category
/// Nd, Unicode 16): Arabic-Indic, Persian, the Indic scripts, Thai, the
/// full-width forms and every other script.
const _zeros = [
  0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66, 0x0DE6, //
  0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1A80, 0x1A90, 0x1B50, 0x1BB0, //
  0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xA9D0, 0xA9F0, 0xAA50, 0xABF0, 0xFF10, 0x104A0, 0x10D30, 0x10D40, //
  0x11066, 0x110F0, 0x11136, 0x111D0, 0x112F0, 0x11450, 0x114D0, 0x11650, 0x116C0, 0x116D0, 0x116DA, 0x11730, //
  0x118E0, 0x11950, 0x11BF0, 0x11C50, 0x11D50, 0x11DA0, 0x11F50, 0x16130, 0x16A60, 0x16AC0, 0x16B50, 0x16D70, //
  0x1CCF0, 0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0x1E140, 0x1E2F0, 0x1E4F0, 0x1E5F1, 0x1E950, 0x1FBF0,
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
