import 'package:flutter/foundation.dart';

/// Financial monetary representation with strict fixed-point integer arithmetic.
///
/// **Non-negotiable rule:** Floating-point numbers (`double`/`float`) are NEVER
/// used for storing or computing money amounts. This eliminates IEEE-754 precision
/// drift (e.g., 0.1 + 0.2 != 0.3) and ensures accounting and audit safety.
///
/// Stored in subunits (e.g., Halalas / Cents / Piastres) where:
/// `1.00 Currency Unit = 100 rawUnits` (Scale = 100).
@immutable
class Money implements Comparable<Money> {
  /// Default currency code (Saudi Riyal).
  static const String defaultCurrency = 'SAR';

  /// Arabic symbol for SAR.
  static const String defaultArabicSymbol = 'ر.س';

  /// Scale factor: 100 raw subunits per major currency unit.
  static const int scale = 100;

  /// The raw integer amount in minor currency subunits (e.g., Halalas / Cents).
  final int rawUnits;

  /// ISO 4217 Currency code or custom currency key.
  final String currency;

  /// Creates a [Money] value directly from [rawUnits] in minor currency subunits.
  const Money(this.rawUnits, {this.currency = defaultCurrency});

  /// Creates a [Money] value from minor units (alias for primary constructor).
  const Money.fromSubunits(int rawUnits, {String currency = defaultCurrency})
    : this(rawUnits, currency: currency);

  /// Creates a [Money] instance from whole major units (e.g., 50 -> 50.00).
  factory Money.fromMajor(int majorUnits, {String currency = defaultCurrency}) {
    return Money(majorUnits * scale, currency: currency);
  }

  /// Creates a [Money] instance from distinct major and minor units.
  ///
  /// For example, `Money.fromParts(10, 50)` produces 10.50 (1050 rawUnits).
  /// If [isNegative] is true, the resulting value will be negative.
  factory Money.fromParts(
    int major,
    int minor, {
    bool isNegative = false,
    String currency = defaultCurrency,
  }) {
    if (minor < 0 || minor >= scale) {
      throw ArgumentError.value(
        minor,
        'minor',
        'Minor unit must be between 0 and ${scale - 1}',
      );
    }
    final total = (major.abs() * scale) + minor;
    return Money(isNegative ? -total : total, currency: currency);
  }

  /// Zero money instance for the default currency.
  static const Money zero = Money(0);

  /// Factory for zero money in a specific currency.
  factory Money.zeroCurrency([String currency = defaultCurrency]) =>
      Money(0, currency: currency);

  // ---------------------------------------------------------------------------
  // Strict String Parsing (Zero Double / Pure Integer)
  // ---------------------------------------------------------------------------

  /// Parses a financial string into a [Money] object strictly using integer arithmetic.
  ///
  /// Supports:
  /// - Standard numbers: `'1234.56'`, `'1234'`, `'1234.5'`
  /// - Formatted strings with thousands commas: `'1,234.56'`
  /// - Arabic-Indic digits: `'١٢٣٤٫٥٦'` or `'١,٢٣٤.٥٦'`
  /// - Accounting parentheses for negative values: `'(1,234.56)'`
  /// - Currency annotations: `'1,234.56 SAR'`, `'1,234.56 ر.س'`
  ///
  /// Throws [FormatException] if input cannot be parsed.
  factory Money.parse(String input, {String currency = defaultCurrency}) {
    final parsed = tryParse(input, currency: currency);
    if (parsed == null) {
      throw FormatException('Invalid monetary string format: "$input"');
    }
    return parsed;
  }

  /// Attempts to parse a financial string into a [Money] object.
  /// Returns `null` if the input is null, empty, or invalid.
  static Money? tryParse(String? input, {String currency = defaultCurrency}) {
    if (input == null) return null;
    var text = input.trim();
    if (text.isEmpty) return null;

    // Normalize Arabic-Indic digits to ASCII standard digits
    text = _normalizeDigits(text);

    // Check for negative represented in accounting parenthesis: (123.45)
    bool isNegative = false;
    if (text.startsWith('(') && text.endsWith(')')) {
      isNegative = true;
      text = text.substring(1, text.length - 1).trim();
    } else if (text.startsWith('-')) {
      isNegative = true;
      text = text.substring(1).trim();
    } else if (text.startsWith('+')) {
      text = text.substring(1).trim();
    }

    // Strip known currency labels and symbols
    text = text
        .replaceAll('SAR', '')
        .replaceAll('sar', '')
        .replaceAll('ر.س', '')
        .replaceAll('ر.س.', '')
        .replaceAll('ريال', '')
        .trim();

    // Standardize decimal separators:
    // In Arabic typography, '٫' (U+066B) is the decimal separator,
    // and '،' (U+060C) is the thousands separator.
    text = text.replaceAll('،', ',').replaceAll('٬', ',');
    text = text.replaceAll('٫', '.');

    // If both comma and dot exist, determine role
    if (text.contains(',') && text.contains('.')) {
      final lastComma = text.lastIndexOf(',');
      final lastDot = text.lastIndexOf('.');
      if (lastDot > lastComma) {
        // e.g. 1,234.56 -> comma is thousands separator
        if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text)) return null;
        text = text.replaceAll(',', '');
      } else {
        // e.g. 1.234,56 (European style) -> dot is thousands separator
        if (!RegExp(r'^\d{1,3}(\.\d{3})+,\d+$').hasMatch(text)) return null;
        text = text.replaceAll('.', '').replaceAll(',', '.');
      }
    } else if (text.contains(',')) {
      // Check if comma is decimal (only one comma and 1-2 digits after it)
      final parts = text.split(',');
      if (parts.length == 2 && parts[1].isNotEmpty && parts[1].length <= 2) {
        text = '${parts[0]}.${parts[1]}';
      } else {
        // Otherwise treat as thousands separator
        if (!RegExp(r'^\d{1,3}(,\d{3})+$').hasMatch(text)) return null;
        text = text.replaceAll(',', '');
      }
    }

    // Remove remaining spaces or non-digit/non-dot characters
    final cleanBuffer = StringBuffer();
    int dotCount = 0;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '.') {
        dotCount++;
        if (dotCount > 1) return null; // Invalid multiple decimal points
        cleanBuffer.write(char);
      } else if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) {
        cleanBuffer.write(char);
      } else if (char == ' ') {
        // skip whitespace
        continue;
      } else {
        // Unexpected character
        return null;
      }
    }

    final sanitized = cleanBuffer.toString();
    if (sanitized.isEmpty || sanitized == '.') return null;

    final parts = sanitized.split('.');
    final majorStr = parts[0].isEmpty ? '0' : parts[0];
    final int? majorVal = int.tryParse(majorStr);
    if (majorVal == null) return null;

    int minorVal = 0;
    if (parts.length > 1) {
      final fracStr = parts[1];
      if (fracStr.length == 1) {
        minorVal = (int.tryParse(fracStr) ?? 0) * 10;
      } else if (fracStr.length == 2) {
        minorVal = int.tryParse(fracStr) ?? 0;
      } else if (fracStr.length > 2) {
        // Round to nearest 2 decimal places using pure integer logic (half-up)
        final twoDigits = int.tryParse(fracStr.substring(0, 2)) ?? 0;
        final thirdDigit = int.tryParse(fracStr.substring(2, 3)) ?? 0;
        minorVal = twoDigits + (thirdDigit >= 5 ? 1 : 0);
      }
    }

    int totalSubunits = (majorVal * scale) + minorVal;
    if (isNegative) {
      totalSubunits = -totalSubunits;
    }

    return Money(totalSubunits, currency: currency);
  }

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  /// Major currency component (e.g. For 1250 rawUnits -> 12).
  int get majorPart => rawUnits ~/ scale;

  /// Minor currency subunit component (e.g. For 1250 rawUnits -> 50).
  /// Always non-negative (0..99).
  int get minorPart => rawUnits.abs() % scale;

  /// Whether this amount is exactly zero.
  bool get isZero => rawUnits == 0;

  /// Whether this amount is strictly positive.
  bool get isPositive => rawUnits > 0;

  /// Whether this amount is strictly negative.
  bool get isNegative => rawUnits < 0;

  /// Returns the absolute value of this monetary amount.
  Money get abs => Money(rawUnits.abs(), currency: currency);

  /// Standard localized currency symbol.
  String get currencySymbol {
    if (currency.toUpperCase() == 'SAR') {
      return defaultArabicSymbol;
    }
    return currency;
  }

  // ---------------------------------------------------------------------------
  // Arithmetic Operations (Strict Integer Math)
  // ---------------------------------------------------------------------------

  /// Adds another [Money] instance.
  /// Throws [ArgumentError] if currencies do not match.
  Money operator +(Money other) {
    _assertSameCurrency(other);
    return Money(rawUnits + other.rawUnits, currency: currency);
  }

  /// Subtracts another [Money] instance.
  /// Throws [ArgumentError] if currencies do not match.
  Money operator -(Money other) {
    _assertSameCurrency(other);
    return Money(rawUnits - other.rawUnits, currency: currency);
  }

  /// Unary negation (e.g. -money).
  Money operator -() {
    return Money(-rawUnits, currency: currency);
  }

  /// Multiplies the amount by an integer factor (e.g., item quantity).
  Money operator *(int factor) {
    return Money(rawUnits * factor, currency: currency);
  }

  /// Divides the amount by an integer divisor using truncating division.
  Money operator ~/(int divisor) {
    if (divisor == 0) {
      throw UnsupportedError('Division by zero is not supported');
    }
    return Money(rawUnits ~/ divisor, currency: currency);
  }

  /// Multiplies by a rational ratio [numerator] / [denominator] using pure
  /// integer arithmetic with Half-Up rounding.
  ///
  /// Useful for financial rates, markups, margins, and taxes without floating-point errors.
  Money multiplyRatio(
    int numerator,
    int denominator, {
    bool roundHalfUp = true,
  }) {
    if (denominator == 0) {
      throw ArgumentError.value(
        denominator,
        'denominator',
        'Cannot divide by zero',
      );
    }
    final int product = rawUnits * numerator;
    int quotient = product ~/ denominator;
    if (roundHalfUp) {
      final int remainder = (product % denominator).abs();
      final int absDenom = denominator.abs();
      if (remainder * 2 >= absDenom) {
        quotient += (product >= 0 ? 1 : -1);
      }
    }
    return Money(quotient, currency: currency);
  }

  /// Calculates a percentage of the money amount (e.g. 10 for 10% discount).
  /// Uses pure integer arithmetic with half-up rounding.
  Money percentage(int percent, {int base = 100}) {
    return multiplyRatio(percent, base);
  }

  /// Calculates basis points (1 bp = 0.01%, 10,000 bps = 100%).
  Money basisPoints(int bps) {
    return multiplyRatio(bps, 10000);
  }

  /// Distributes/Splits this money amount evenly into [parts] without losing
  /// a single subunit due to truncation or rounding (Fowler Money pattern).
  ///
  /// The sum of the returned list is guaranteed to equal `this`.
  List<Money> split(int parts) {
    if (parts <= 0) {
      throw ArgumentError.value(parts, 'parts', 'Split parts must be positive');
    }
    final int baseShare = rawUnits ~/ parts;
    final int remainder = rawUnits % parts;

    final List<Money> result = List<Money>.generate(parts, (i) {
      // Allocate the remaining subunits one-by-one to early buckets
      final int extra = (i < remainder.abs()) ? (rawUnits >= 0 ? 1 : -1) : 0;
      return Money(baseShare + extra, currency: currency);
    });

    return result;
  }

  /// Allocates money according to a list of integer [ratios] without losing subunits.
  /// Uses the largest-remainder method (Hare-Niemeyer) for fairest penny distribution.
  ///
  /// The sum of the returned list is guaranteed to equal `this`.
  List<Money> allocate(List<int> ratios) {
    if (ratios.isEmpty) {
      throw ArgumentError('Ratios list cannot be empty');
    }
    int totalRatio = 0;
    for (final r in ratios) {
      if (r < 0) throw ArgumentError('Ratio values cannot be negative');
      totalRatio += r;
    }
    if (totalRatio == 0) {
      throw ArgumentError('Sum of ratios must be greater than zero');
    }

    int remainder = rawUnits;
    final List<int> portions = List<int>.filled(ratios.length, 0);
    final List<int> fractionRemainders = List<int>.filled(ratios.length, 0);

    for (int i = 0; i < ratios.length; i++) {
      final product = rawUnits * ratios[i];
      portions[i] = product ~/ totalRatio;
      fractionRemainders[i] = (product % totalRatio).abs();
      remainder -= portions[i];
    }

    // Sort indices by largest fractional remainder (Hare-Niemeyer method)
    final List<int> indices = List<int>.generate(ratios.length, (i) => i);
    indices.sort((a, b) {
      final cmp = fractionRemainders[b].compareTo(fractionRemainders[a]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });

    final int step = remainder > 0 ? 1 : -1;
    int orderIndex = 0;
    while (remainder != 0) {
      final targetIndex = indices[orderIndex % indices.length];
      portions[targetIndex] += step;
      remainder -= step;
      orderIndex++;
    }

    return portions.map((units) => Money(units, currency: currency)).toList();
  }

  // ---------------------------------------------------------------------------
  // Comparison & Equality
  // ---------------------------------------------------------------------------

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other);
    return rawUnits.compareTo(other.rawUnits);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Money &&
        other.rawUnits == rawUnits &&
        other.currency == currency;
  }

  @override
  int get hashCode => Object.hash(rawUnits, currency);

  // ---------------------------------------------------------------------------
  // Formatting & Presentation (Zero Float)
  // ---------------------------------------------------------------------------

  /// Formats the money into a clean, professional string without floating point conversions.
  ///
  /// - [includeSymbol]: If true, appends currency symbol. Defaults to false.
  /// - [customSymbol]: Overrides the default symbol.
  /// - [useArabicDigits]: Converts digits to Arabic-Indic (`١,٢٣٤٫٥٦`).
  /// - [includeCents]: If false, omits subunits (e.g. `'1,235'` or `'1,234'`).
  /// - [spaceBetween]: Inserts space between amount and currency symbol.
  String format({
    bool includeSymbol = false,
    String? customSymbol,
    bool useArabicDigits = false,
    bool includeCents = true,
    bool spaceBetween = true,
  }) {
    final bool neg = isNegative;
    final int absUnits = rawUnits.abs();

    int major = absUnits ~/ scale;
    int minor = absUnits % scale;

    if (!includeCents) {
      // Round to nearest integer if cents excluded
      if (minor >= 50) {
        major += 1;
      }
    }

    // Insert thousands separator into major unit string
    final majorString = _formatThousands(major);
    final String formattedNumber;

    if (includeCents) {
      final minorString = minor.toString().padLeft(2, '0');
      formattedNumber = '$majorString.$minorString';
    } else {
      formattedNumber = majorString;
    }

    var result = (neg ? '-' : '') + formattedNumber;

    if (useArabicDigits) {
      result = _toArabicDigits(result);
    }

    if (includeSymbol) {
      final symbol = customSymbol ?? currencySymbol;
      final separator = spaceBetween ? ' ' : '';
      // In Arabic typography, symbol appears on the appropriate side
      result = '$result$separator$symbol';
    }

    return result;
  }

  /// Returns a clean decimal representation (e.g. `'1234.56'` or `'-1234.56'`).
  String toDecimalString() {
    final bool neg = isNegative;
    final int absUnits = rawUnits.abs();
    final int major = absUnits ~/ scale;
    final int minor = absUnits % scale;
    final minorStr = minor.toString().padLeft(2, '0');
    return '${neg ? '-' : ''}$major.$minorStr';
  }

  @override
  String toString() {
    return 'Money(${toDecimalString()} $currency, rawUnits: $rawUnits)';
  }

  // ---------------------------------------------------------------------------
  // Internal Helpers
  // ---------------------------------------------------------------------------

  void _assertSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError(
        'Currency mismatch: cannot operate on $currency and ${other.currency}',
      );
    }
  }

  static String _formatThousands(int value) {
    final str = value.toString();
    if (str.length <= 3) return str;

    final buffer = StringBuffer();
    final int remainder = str.length % 3;

    if (remainder > 0) {
      buffer.write(str.substring(0, remainder));
      if (remainder < str.length) buffer.write(',');
    }

    for (int i = remainder; i < str.length; i += 3) {
      buffer.write(str.substring(i, i + 3));
      if (i + 3 < str.length) buffer.write(',');
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

  static String _toArabicDigits(String input) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    String output = input;
    for (int i = 0; i < 10; i++) {
      output = output.replaceAll(english[i], arabic[i]);
    }
    // Convert punctuation to Arabic typography
    output = output.replaceAll(',', '،');
    output = output.replaceAll('.', '٫');
    return output;
  }
}
