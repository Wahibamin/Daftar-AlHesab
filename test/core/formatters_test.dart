import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3/core/utils/formatters.dart';

void main() {
  group('ThousandsSeparatorInputFormatter', () {
    final formatter = ThousandsSeparatorInputFormatter();

    test('Formats integers with thousands separators', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1234567',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(result.text, equals('1,234,567'));
    });

    test('Formats decimal amounts correctly', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1250.50',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(result.text, equals('1,250.50'));
    });

    test('Limits decimal digits to maximum specified (default 2)', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '100.999',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(result.text, equals('100.99'));
    });

    test('Automatically converts Arabic-Indic digits to ASCII and formats', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '١٢٥٠٫٧٥',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(result.text, equals('1,250.75'));
    });

    test('integerOnly mode blocks decimal points', () {
      final intFormatter = ThousandsSeparatorInputFormatter.integerOnly();
      final result = intFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1250.50',
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      expect(result.text, equals('1,250'));
    });

    test(
      'Static extractRawUnits converts formatted string to integer subunits',
      () {
        expect(
          ThousandsSeparatorInputFormatter.extractRawUnits('1,250.50'),
          equals(125050),
        );
        expect(
          ThousandsSeparatorInputFormatter.extractRawUnits('1,250'),
          equals(125000),
        );
        expect(
          ThousandsSeparatorInputFormatter.extractRawUnits('1,250.5'),
          equals(125050),
        );
        expect(ThousandsSeparatorInputFormatter.extractRawUnits(''), equals(0));
        expect(
          ThousandsSeparatorInputFormatter.extractRawUnits(null),
          equals(0),
        );
      },
    );

    test('Static extractInteger extracts clean whole integer quantity', () {
      expect(
        ThousandsSeparatorInputFormatter.extractInteger('1,250.50'),
        equals(1250),
      );
      expect(
        ThousandsSeparatorInputFormatter.extractInteger('1,250'),
        equals(1250),
      );
      expect(ThousandsSeparatorInputFormatter.extractInteger(''), equals(0));
      expect(ThousandsSeparatorInputFormatter.extractInteger(null), equals(0));
    });

    test('Static extractMoney returns accurate Money value', () {
      final money = ThousandsSeparatorInputFormatter.extractMoney('1,250.50');
      expect(money.rawUnits, equals(125050));
      expect(money.toDecimalString(), equals('1250.50'));
    });
  });

  group('PhoneNumberFormatter', () {
    final phoneFormatter = PhoneNumberFormatter();

    test('Strips non-digit characters and applies spacing mask', () {
      final result = phoneFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '0501234567',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      expect(result.text, equals('050 123 4567'));
    });

    test('Blocks letters and symbols completely', () {
      final result = phoneFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '050-ABC#123!',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      expect(result.text, equals('050 123'));
    });

    test('Enforces maxLength constraint', () {
      final result = phoneFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '050123456789999',
          selection: TextSelection.collapsed(offset: 15),
        ),
      );
      // Only first 10 digits are kept
      expect(result.text, equals('050 123 4567'));
    });

    test('Converts Arabic-Indic digits automatically', () {
      final result = phoneFormatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '٠٥٠١٢٣٤٥٦٧',
          selection: TextSelection.collapsed(offset: 10),
        ),
      );
      expect(result.text, equals('050 123 4567'));
    });

    test('cleanDigits extracts raw digits string', () {
      expect(
        PhoneNumberFormatter.cleanDigits('050 123 4567'),
        equals('0501234567'),
      );
      expect(
        PhoneNumberFormatter.cleanDigits('٠٥٠-١٢٣-٤٥٦٧'),
        equals('0501234567'),
      );
    });

    test('isValidSaudiMobile correctly checks mobile numbers', () {
      expect(PhoneNumberFormatter.isValidSaudiMobile('0501234567'), isTrue);
      expect(PhoneNumberFormatter.isValidSaudiMobile('050 123 4567'), isTrue);
      expect(
        PhoneNumberFormatter.isValidSaudiMobile('0111234567'),
        isFalse,
      ); // Landline
      expect(
        PhoneNumberFormatter.isValidSaudiMobile('050123'),
        isFalse,
      ); // Too short
      expect(PhoneNumberFormatter.isValidSaudiMobile(null), isFalse);
    });
  });
}
