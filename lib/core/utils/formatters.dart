import 'package:flutter/services.dart';
import 'money.dart';

/// Interactive input formatter for currency amounts and quantities.
///
/// Automatically inserts thousands separators (`1,000,000.00`) as the user types,
/// preserving cursor position seamlessly and preventing float rounding issues.
///
/// Converts any Arabic-Indic numerals (`٠-٩`) to standard digits automatically.
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  /// Whether fractional/decimal digits are permitted.
  final bool allowDecimals;

  /// Maximum number of decimal places allowed (default 2 for currency).
  final int maxDecimalDigits;

  /// Separator character for thousands (default `,`).
  final String thousandSeparator;

  /// Separator character for decimals (default `.`).
  final String decimalSeparator;

  /// Creates a formatter with support for decimals (e.g., Financial amounts).
  ThousandsSeparatorInputFormatter({
    this.allowDecimals = true,
    this.maxDecimalDigits = 2,
    this.thousandSeparator = ',',
    this.decimalSeparator = '.',
  });

  /// Factory specifically configured for integer inventory quantities (no decimals).
  factory ThousandsSeparatorInputFormatter.integerOnly({
    String thousandSeparator = ',',
  }) {
    return ThousandsSeparatorInputFormatter(
      allowDecimals: false,
      maxDecimalDigits: 0,
      thousandSeparator: thousandSeparator,
    );
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // 1. Normalize Arabic-Indic digits to ASCII standard digits
    final normalized = _normalizeDigits(newValue.text);

    // 2. Sanitize: allow only digits and at most one decimal point if enabled
    final buffer = StringBuffer();
    int decimalPointCount = 0;
    int digitsBeforeCursorInRaw = 0;
    final int selectionEnd = newValue.selection.end;

    final bool isCommaThousandSep = thousandSeparator == ',';

    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      final bool isDigit = char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57;
      final bool isDecimalPoint =
          char == '.' || char == '٫' || (!isCommaThousandSep && char == ',');

      if (!allowDecimals && isDecimalPoint) {
        break;
      }

      final bool isDot = allowDecimals && isDecimalPoint;

      if (isDigit) {
        buffer.write(char);
        if (i < selectionEnd) {
          digitsBeforeCursorInRaw++;
        }
      } else if (isDot && decimalPointCount == 0) {
        buffer.write(decimalSeparator);
        decimalPointCount++;
        if (i < selectionEnd) {
          digitsBeforeCursorInRaw++;
        }
      }
    }

    final rawSanitized = buffer.toString();
    if (rawSanitized.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // 3. Split into integer and decimal portions
    final List<String> parts = rawSanitized.split(decimalSeparator);
    String integerPart = parts[0];
    String? fractionalPart = parts.length > 1 ? parts[1] : null;

    if (fractionalPart != null && fractionalPart.length > maxDecimalDigits) {
      fractionalPart = fractionalPart.substring(0, maxDecimalDigits);
    }

    // Format integer part with thousands separators
    final formattedInteger = _formatIntegerThousands(
      integerPart,
      thousandSeparator,
    );

    // Reconstruct full formatted string
    final StringBuffer formattedResult = StringBuffer(formattedInteger);
    if (parts.length > 1) {
      formattedResult.write(decimalSeparator);
      if (fractionalPart != null && fractionalPart.isNotEmpty) {
        formattedResult.write(fractionalPart);
      }
    }

    final String finalFormattedText = formattedResult.toString();

    // 4. Calculate new cursor offset preserving position relative to raw content
    int newCursorOffset = 0;
    int rawCharsEncountered = 0;

    for (int i = 0; i < finalFormattedText.length; i++) {
      final char = finalFormattedText[i];
      final bool isRawChar =
          (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) ||
          char == decimalSeparator;

      if (isRawChar) {
        rawCharsEncountered++;
      }

      if (rawCharsEncountered == digitsBeforeCursorInRaw) {
        newCursorOffset = i + 1;
        break;
      }
    }

    if (digitsBeforeCursorInRaw == 0) {
      newCursorOffset = 0;
    } else if (rawCharsEncountered < digitsBeforeCursorInRaw ||
        newCursorOffset > finalFormattedText.length) {
      newCursorOffset = finalFormattedText.length;
    }

    return TextEditingValue(
      text: finalFormattedText,
      selection: TextSelection.collapsed(offset: newCursorOffset),
    );
  }

  // ---------------------------------------------------------------------------
  // Static Extraction & Conversion Helpers
  // ---------------------------------------------------------------------------

  /// Extracts the monetary value in integer subunits (rawUnits, x100).
  ///
  /// Examples:
  /// - `"1,250.50"` -> `125050`
  /// - `"1,250"`    -> `125000`
  /// - `"1,250.5"`  -> `125050`
  /// - `""`         -> `0`
  static int extractRawUnits(String? formattedText) {
    if (formattedText == null || formattedText.trim().isEmpty) return 0;
    final money = Money.tryParse(formattedText);
    return money?.rawUnits ?? 0;
  }

  /// Extracts the clean whole integer portion (e.g. for item quantities).
  ///
  /// Examples:
  /// - `"1,250"`    -> `1250`
  /// - `"1,250.75"` -> `1250`
  /// - `""`         -> `0`
  static int extractInteger(String? formattedText) {
    if (formattedText == null || formattedText.trim().isEmpty) return 0;
    final normalized = _normalizeDigits(formattedText);
    final cleanDigits = StringBuffer();

    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      if (char == '.' || char == '٫') break; // Stop at fractional point
      if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        cleanDigits.write(char);
      }
    }

    return int.tryParse(cleanDigits.toString()) ?? 0;
  }

  /// Extracts a validated [Money] instance directly from formatted input text.
  static Money extractMoney(
    String? formattedText, {
    String currency = Money.defaultCurrency,
  }) {
    return Money(extractRawUnits(formattedText), currency: currency);
  }

  /// Formats an integer subunit value into a display string for text editing controllers.
  static String formatRawUnits(int rawUnits) {
    final money = Money(rawUnits);
    return money.format(includeSymbol: false);
  }

  /// Formats a plain whole integer (quantity) with thousands separators.
  static String formatCount(int count, {String thousandSeparator = ','}) {
    return _formatIntegerThousands(count.toString(), thousandSeparator);
  }

  // ---------------------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------------------

  static String _formatIntegerThousands(String digits, String separator) {
    if (digits.isEmpty) return '0';
    // Remove leading zeros if not single zero
    final clean = digits.replaceAll(RegExp(r'^0+(?=\d)'), '');
    if (clean.length <= 3) return clean;

    final buffer = StringBuffer();
    final remainder = clean.length % 3;

    if (remainder > 0) {
      buffer.write(clean.substring(0, remainder));
      if (remainder < clean.length) buffer.write(separator);
    }

    for (int i = remainder; i < clean.length; i += 3) {
      buffer.write(clean.substring(i, i + 3));
      if (i + 3 < clean.length) buffer.write(separator);
    }

    return buffer.toString();
  }

  static String _normalizeDigits(String input) {
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    String output = input;
    for (int i = 0; i < 10; i++) {
      output = output.replaceAll(arabic[i], english[i]);
    }
    return output;
  }
}

/// Convenient helper for formatting monetary amounts as clean numbers without currency labels.
abstract final class CurrencyFormatter {
  static String format(Money money, {bool includeSymbol = false}) {
    return money.format(includeSymbol: includeSymbol);
  }
}

/// Standard date formatting utilities for consistent Arabic/ERP date display.
abstract final class DateFormatter {
  static String formatDate(DateTime date) {
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

/// Phone number input formatter strictly enforcing digits-only input.
///
/// - Completely strips letters, symbols, spaces, and punctuation.
/// - Automatically converts Arabic-Indic digits (`٠-٩`) to ASCII digits.
/// - Limits length to valid phone number size (default 10 digits for Saudi numbers).
/// - Optionally formats as structured spacing: `050 123 4567`.
class PhoneNumberFormatter extends TextInputFormatter {
  /// Maximum number of digits allowed. Default is 10 (e.g. `05XXXXXXXX`).
  final int maxLength;

  /// Whether to apply human-readable spacing: e.g. `050 123 4567`.
  final bool formatSpacing;

  /// Creates a [PhoneNumberFormatter].
  PhoneNumberFormatter({this.maxLength = 10, this.formatSpacing = true});

  /// The standard underlying digits-only filter.
  static final TextInputFormatter digitsOnly =
      FilteringTextInputFormatter.digitsOnly;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // 1. Normalize Arabic digits and filter digits only
    final normalized = _normalizeDigits(newValue.text);
    final buffer = StringBuffer();

    for (int i = 0; i < normalized.length; i++) {
      final char = normalized[i];
      if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        if (buffer.length < maxLength) {
          buffer.write(char);
        }
      }
    }

    final digits = buffer.toString();
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    if (!formatSpacing) {
      return TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }

    // 2. Format as 05X XXX XXXX (or groups of 3-3-4)
    final formatted = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 3 || i == 6) {
        formatted.write(' ');
      }
      formatted.write(digits[i]);
    }

    final resultText = formatted.toString();
    return TextEditingValue(
      text: resultText,
      selection: TextSelection.collapsed(offset: resultText.length),
    );
  }

  /// Formats a phone number string with human-readable spacing (e.g. `050 123 4567`).
  static String formatSaudi(String? text) {
    if (text == null || text.isEmpty) return '';
    final digits = cleanDigits(text);
    if (digits.length <= 3) return digits;
    final formatted = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i == 3 || i == 6) {
        formatted.write(' ');
      }
      formatted.write(digits[i]);
    }
    return formatted.toString();
  }

  /// Extracts pure digits from any formatted phone string.
  static String cleanDigits(String? text) {
    if (text == null) return '';
    final normalized = _normalizeDigits(text);
    return normalized.replaceAll(RegExp(r'\D'), '');
  }

  /// Validates whether the given string is a valid Saudi mobile number:
  /// Starts with `05` and consists of exactly 10 digits.
  static bool isValidSaudiMobile(String? text) {
    if (text == null) return false;
    final digits = cleanDigits(text);
    return RegExp(r'^05\d{8}$').hasMatch(digits);
  }

  /// Validates general phone number length constraints (9 to 15 digits).
  static bool isValidGeneralPhone(
    String? text, {
    int minLength = 9,
    int maxLength = 15,
  }) {
    if (text == null) return false;
    final digits = cleanDigits(text);
    return digits.length >= minLength && digits.length <= maxLength;
  }

  static String _normalizeDigits(String input) {
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    String output = input;
    for (int i = 0; i < 10; i++) {
      output = output.replaceAll(arabic[i], english[i]);
    }
    return output;
  }
}
