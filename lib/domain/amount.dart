/// Exact 7-decimal amounts held as integer base units. Never `double`.
class Amount implements Comparable<Amount> {
  Amount._(this.units);

  static const int scale = 7;
  static final BigInt _unit = BigInt.from(10).pow(scale);
  static final BigInt maxUnits = BigInt.parse('9223372036854775807');
  static final RegExp _pattern = RegExp(r'^\d+(\.\d{1,7})?$');

  /// Integer base units (1 unit = 1e-7).
  final BigInt units;

  /// Parses a decimal string; throws [FormatException] on anything else
  /// (negatives, exponents, >7 decimals, overflow).
  factory Amount.parse(String text) {
    if (!_pattern.hasMatch(text)) {
      throw FormatException('invalid amount', text);
    }
    final parts = text.split('.');
    final frac = (parts.length > 1 ? parts[1] : '').padRight(scale, '0');
    final v = BigInt.parse(parts[0]) * _unit + BigInt.parse(frac);
    if (v > maxUnits) throw FormatException('amount exceeds ledger maximum', text);
    return Amount._(v);
  }

  factory Amount.fromUnits(BigInt units) {
    if (units < BigInt.zero || units > maxUnits) {
      throw RangeError('units out of range');
    }
    return Amount._(units);
  }

  static final Amount zero = Amount._(BigInt.zero);

  bool get isZero => units == BigInt.zero;

  Amount operator +(Amount o) => Amount.fromUnits(units + o.units);
  Amount operator -(Amount o) => Amount.fromUnits(units - o.units);
  bool operator <(Amount o) => units < o.units;
  bool operator <=(Amount o) => units <= o.units;
  bool operator >(Amount o) => units > o.units;
  bool operator >=(Amount o) => units >= o.units;

  /// floor(this * (10000 - bps) / 10000)
  Amount applySlippageFloor(int bps) {
    if (bps < 0 || bps > 10000) throw RangeError('bps');
    return Amount._(units * BigInt.from(10000 - bps) ~/ BigInt.from(10000));
  }

  @override
  int compareTo(Amount other) => units.compareTo(other.units);

  @override
  bool operator ==(Object other) => other is Amount && other.units == units;

  @override
  int get hashCode => units.hashCode;

  /// Canonical 7-decimal form, as the core API uses.
  @override
  String toString() {
    final whole = units ~/ _unit;
    final frac = (units % _unit).toString().padLeft(scale, '0');
    return '$whole.$frac';
  }

  /// Display form: trailing zeros trimmed but at least 2 decimals.
  String toDisplay() {
    var s = toString();
    s = s.replaceFirst(RegExp(r'0+$'), '');
    final dot = s.indexOf('.');
    final decimals = s.length - dot - 1;
    if (decimals < 2) s = s.padRight(dot + 3, '0');
    return s;
  }
}
