import 'package:test/test.dart';
import 'package:unbound_mobile/domain/amount.dart';

void main() {
  group('Amount', () {
    test('parses and prints exactly, no float drift', () {
      expect(Amount.parse('80').toString(), '80.0000000');
      expect(Amount.parse('0.0000001').units, BigInt.one);
      expect(Amount.parse('0.1') + Amount.parse('0.2'), Amount.parse('0.3'));
    });

    for (final bad in ['', '-1', '1e3', '1.12345678', 'abc', '1.', '.5', ' 1']) {
      test('rejects "$bad"', () {
        expect(() => Amount.parse(bad), throwsFormatException);
      });
    }

    test('enforces int64 ceiling', () {
      expect(() => Amount.parse('922337203685.4775808'), throwsFormatException);
      expect(Amount.parse('922337203685.4775807').units, Amount.maxUnits);
    });

    test('subtraction below zero is an error, not a negative balance', () {
      expect(() => Amount.parse('1') - Amount.parse('2'), throwsRangeError);
    });

    test('slippage floor matches the core/stellar formula', () {
      expect(Amount.parse('72').applySlippageFloor(100).toString(), '71.2800000');
      expect(Amount.parse('72').applySlippageFloor(0), Amount.parse('72'));
      expect(() => Amount.parse('1').applySlippageFloor(10001), throwsRangeError);
    });

    test('display trims zeros but keeps two decimals', () {
      expect(Amount.parse('72').toDisplay(), '72.00');
      expect(Amount.parse('71.28').toDisplay(), '71.28');
      expect(Amount.parse('0.0000001').toDisplay(), '0.0000001');
    });

    test('comparison', () {
      expect(Amount.parse('2') > Amount.parse('1.9999999'), isTrue);
      expect(Amount.zero.isZero, isTrue);
    });
  });
}
