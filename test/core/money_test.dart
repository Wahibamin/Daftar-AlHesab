import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/utils/money.dart';

void main() {
  group('Money - Architectural Core & Integer Arithmetic', () {
    test('Stores values purely as integers (rawUnits)', () {
      const money = Money(12345);
      expect(money.rawUnits, equals(12345));
      expect(money.majorPart, equals(123));
      expect(money.minorPart, equals(45));
      expect(money.currency, equals('SAR'));
      expect(money.isPositive, isTrue);
      expect(money.isNegative, isFalse);
      expect(money.isZero, isFalse);
    });

    test('Eliminates IEEE-754 floating-point drift (0.10 + 0.20 == 0.30)', () {
      // In floating-point (double): 0.1 + 0.2 = 0.30000000000000004 != 0.3
      // With Money raw subunits (10 + 20 = 30):
      final tenCents = Money.parse('0.10');
      final twentyCents = Money.parse('0.20');
      final sum = tenCents + twentyCents;

      expect(sum.rawUnits, equals(30));
      expect(sum, equals(Money.parse('0.30')));
      expect(sum.format(includeSymbol: false), equals('0.30'));
    });

    test('Constructors initialize accurately', () {
      final fromMajor = Money.fromMajor(150);
      expect(fromMajor.rawUnits, equals(15000));
      expect(fromMajor.majorPart, equals(150));
      expect(fromMajor.minorPart, equals(0));

      final fromParts = Money.fromParts(45, 75);
      expect(fromParts.rawUnits, equals(4575));

      final negativeParts = Money.fromParts(45, 75, isNegative: true);
      expect(negativeParts.rawUnits, equals(-4575));
      expect(negativeParts.isNegative, isTrue);
      expect(negativeParts.majorPart, equals(-45));
      expect(negativeParts.minorPart, equals(75));

      expect(() => Money.fromParts(10, 100), throwsA(isA<ArgumentError>()));
      expect(() => Money.fromParts(10, -1), throwsA(isA<ArgumentError>()));
    });

    test('Addition and Subtraction with matching currencies', () {
      const a = Money(15050); // 150.50
      const b = Money(4950); // 49.50

      final sum = a + b;
      expect(sum.rawUnits, equals(20000));
      expect(sum.toDecimalString(), equals('200.00'));

      final diff = a - b;
      expect(diff.rawUnits, equals(10100));
      expect(diff.toDecimalString(), equals('101.00'));

      final negativeResult = b - a;
      expect(negativeResult.rawUnits, equals(-10100));
      expect(negativeResult.isNegative, isTrue);
    });

    test('Unary negation and absolute value', () {
      const positive = Money(5000);
      final negative = -positive;
      expect(negative.rawUnits, equals(-5000));
      expect(negative.isNegative, isTrue);
      expect(negative.abs.rawUnits, equals(5000));
      expect(positive.abs.rawUnits, equals(5000));
    });

    test('Multiplication by integer quantities', () {
      const unitPrice = Money(2550); // 25.50
      final total = unitPrice * 4;
      expect(total.rawUnits, equals(10200)); // 102.00

      final zeroTotal = unitPrice * 0;
      expect(zeroTotal.rawUnits, equals(0));
      expect(zeroTotal.isZero, isTrue);

      final negativeTotal = unitPrice * -2;
      expect(negativeTotal.rawUnits, equals(-5100));
    });

    test('Integer division and division-by-zero prevention', () {
      const amount = Money(10000); // 100.00
      final divided = amount ~/ 4;
      expect(divided.rawUnits, equals(2500));

      final truncated = amount ~/ 3;
      expect(truncated.rawUnits, equals(3333)); // 33.33

      expect(() => amount ~/ 0, throwsA(isA<UnsupportedError>()));
    });

    test('Ratio calculation and percentage calculation (Half-Up rounding)', () {
      // 15% percentage on 100.00 SAR
      const hundred = Money(10000);
      final pct100 = hundred.percentage(15);
      expect(pct100.rawUnits, equals(1500)); // 15.00 SAR

      // 15% percentage on 12.33 SAR (1233 * 15 / 100 = 184.95 -> rounds to 185)
      const base1233 = Money(1233);
      final pct1233 = base1233.percentage(15);
      expect(pct1233.rawUnits, equals(185)); // 1.85 SAR

      // Basis points: 250 bps = 2.5% of 1,000.00 SAR = 25.00 SAR
      final thousand = Money.fromMajor(1000);
      expect(thousand.basisPoints(250).rawUnits, equals(2500));
    });

    test('Fowler Split: Prevents lost subunits in equal divisions', () {
      // 100.00 SAR divided among 3 entities
      const hundred = Money(10000);
      final splits = hundred.split(3);

      expect(splits.length, equals(3));
      // First bucket gets the remaining penny: 33.34 + 33.33 + 33.33 = 100.00
      expect(splits[0].rawUnits, equals(3334));
      expect(splits[1].rawUnits, equals(3333));
      expect(splits[2].rawUnits, equals(3333));

      // Invariant: sum of parts MUST strictly equal original amount
      final sum = splits.fold<Money>(Money.zero, (prev, cur) => prev + cur);
      expect(sum, equals(hundred));
    });

    test('Fowler Allocation: Distributes by ratios without remainder loss', () {
      // Allocate 10.00 SAR by ratio 1:2
      const ten = Money(1000);
      final allocated = ten.allocate([1, 2]);

      expect(allocated.length, equals(2));
      // 3.33 + 6.67 = 10.00
      expect(allocated[0].rawUnits, equals(333));
      expect(allocated[1].rawUnits, equals(667));

      final sum = allocated.fold<Money>(Money.zero, (prev, cur) => prev + cur);
      expect(sum, equals(ten));
    });

    test('Currency mismatch guard', () {
      const sar = Money(100, currency: 'SAR');
      const usd = Money(100, currency: 'USD');

      expect(() => sar + usd, throwsA(isA<ArgumentError>()));
      expect(() => sar - usd, throwsA(isA<ArgumentError>()));
      expect(() => sar.compareTo(usd), throwsA(isA<ArgumentError>()));
    });

    test('Comparison and sorting', () {
      const m1 = Money(1000);
      const m2 = Money(2000);
      const m3 = Money(1000);

      expect(m1 < m2, isTrue);
      expect(m2 > m1, isTrue);
      expect(m1 <= m3, isTrue);
      expect(m1 >= m3, isTrue);
      expect(m1 == m3, isTrue);
      expect(m1 == m2, isFalse);

      final list = [m2, m1];
      list.sort();
      expect(list, equals([m1, m2]));
    });

    test('Strict string parsing without float conversions', () {
      expect(Money.parse('1234.56').rawUnits, equals(123456));
      expect(Money.parse('1234').rawUnits, equals(123400));
      expect(Money.parse('1234.5').rawUnits, equals(123450));
      expect(Money.parse('1,234.56').rawUnits, equals(123456));
      expect(Money.parse('1,234,567.89').rawUnits, equals(123456789));
      expect(Money.parse('-500.25').rawUnits, equals(-50025));
      expect(
        Money.parse('(500.25)').rawUnits,
        equals(-50025),
      ); // Accounting parens
      expect(Money.parse('1,234.56 SAR').rawUnits, equals(123456));
      expect(Money.parse('1,234.56 ر.س').rawUnits, equals(123456));

      // Arabic-Indic numerals
      expect(Money.parse('١٢٣٤٫٥٦').rawUnits, equals(123456));
      expect(Money.parse('١،٢٣٤٫٥٦').rawUnits, equals(123456));

      // Rounding excess fractions strictly using integer half-up logic
      expect(Money.parse('10.555').rawUnits, equals(1056));
      expect(Money.parse('10.554').rawUnits, equals(1055));

      // Safe tryParse
      expect(Money.tryParse('invalid_text'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse(null), isNull);
    });

    test('Formatting output', () {
      const money = Money(123456); // 1,234.56 SAR
      expect(money.format(), equals('1,234.56'));
      expect(money.format(includeSymbol: true), equals('1,234.56 ر.س'));
      expect(money.format(includeCents: false), equals('1,235'));
      expect(
        money.format(includeCents: false, includeSymbol: true),
        equals('1,235 ر.س'),
      );

      const negative = Money(-123456);
      expect(negative.format(), equals('-1,234.56'));
      expect(negative.format(includeSymbol: true), equals('-1,234.56 ر.س'));

      const zero = Money(0);
      expect(zero.format(), equals('0.00'));

      // Arabic typography formatting
      final arabicFormatted = money.format(
        useArabicDigits: true,
        includeSymbol: false,
      );
      expect(arabicFormatted, equals('١،٢٣٤٫٥٦'));
    });
  });
}
