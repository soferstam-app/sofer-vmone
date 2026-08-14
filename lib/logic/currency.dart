/// What a number of money is a number of.
///
/// Every amount in the app used to be a bare number with the shekel sign typed
/// in beside it on screen. That was true and unambiguous while the shekel was
/// the only possibility — and the moment it was not, every amount already
/// stored would have been a figure with no unit, unrecoverable, because nothing
/// anywhere said what it had meant.
///
/// So the currency is stored on the amount, not read from a setting. Which
/// currency a price was agreed in is a fact about that price. The setting says
/// what the *next* amount is entered in; it never restates an old one. This is
/// the same shape as the day-boundary rule and the lines-per-page snapshot, and
/// for the same reason: a setting that reaches backwards rewrites history.
class Currency {
  /// The ISO 4217 code, and the only thing stored.
  ///
  /// A bare code rather than one of a fixed list, so that a currency added by a
  /// later version survives a round trip through this one. An unknown code
  /// still sorts, still groups, and still prints — as the code itself, which is
  /// how money is written wherever a symbol would be ambiguous anyway.
  final String code;

  const Currency(this.code);

  /// The shekel, and what every amount stored before this existed was in.
  ///
  /// There was no other option, so reading an unmarked amount as shekels loses
  /// nothing: it is not a guess, it is the only thing it could have been.
  static const Currency ils = Currency('ILS');

  /// The ones offered in settings. Not a limit on what can be stored.
  static const List<Currency> offered = [
    ils,
    Currency('USD'),
    Currency('EUR'),
    Currency('GBP'),
  ];

  static const Map<String, String> _symbols = {
    'ILS': '₪',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
  };

  static const Map<String, String> _names = {
    'ILS': 'שקל',
    'USD': 'דולר',
    'EUR': 'אירו',
    'GBP': 'לירה שטרלינג',
  };

  /// What to print before the number. Falls back to the code, which is a
  /// perfectly ordinary way to write money and never a wrong one.
  String get symbol => _symbols[code] ?? code;

  /// Whether the symbol sits against the number (`₪120`) or needs a space
  /// after it (`USD 120`). A code run into a numeral is unreadable.
  String get _gap => _symbols.containsKey(code) ? '' : ' ';

  String get name => _names[code] ?? code;

  String format(num amount, {int decimals = 0}) =>
      '$symbol$_gap${amount.toStringAsFixed(decimals)}';

  /// Reads a stored code. Anything unusable — absent, empty, not a string —
  /// is the shekel, which is what every amount written before this was.
  factory Currency.fromJson(Object? value) => switch (value) {
        final String s when s.trim().isNotEmpty => Currency(s.trim()),
        _ => ils,
      };

  String toJson() => code;

  @override
  bool operator ==(Object other) => other is Currency && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// An amount and what it is an amount of.
///
/// The two travel together or they do not travel: a total handed around as a
/// bare double is a number that has already forgotten whether it can be added
/// to the next one.
class Money {
  final double amount;
  final Currency currency;

  const Money(this.amount, this.currency);

  Money.zero(this.currency) : amount = 0;

  bool get isZero => amount == 0;

  /// Adds, and refuses to add across currencies.
  ///
  /// Shekels and dollars do not make a number. Converting would need a rate,
  /// and the rate that matters is the one on the day of each amount — which the
  /// app does not have and should not invent. [MoneyTotal] is what to reach for
  /// where a mixture is genuinely possible.
  Money operator +(Money other) {
    assert(currency == other.currency,
        'refusing to add $currency to ${other.currency}');
    return Money(amount + other.amount, currency);
  }

  Money operator -(Money other) {
    assert(currency == other.currency,
        'refusing to subtract ${other.currency} from $currency');
    return Money(amount - other.amount, currency);
  }

  Money operator *(num by) => Money(amount * by, currency);

  String format({int decimals = 0}) =>
      currency.format(amount, decimals: decimals);

  @override
  String toString() => format(decimals: 2);
}

/// A sum of amounts that may not all be in one currency.
///
/// Rather than adding them anyway and producing a number that means nothing,
/// this keeps a running total per currency. Almost always there is exactly one
/// and it reads as an ordinary figure; where there is more than one, the app
/// can say so instead of quietly lying by a factor of four.
class MoneyTotal {
  final Map<Currency, double> _byCurrency = {};

  MoneyTotal();

  factory MoneyTotal.of(Iterable<Money> amounts) {
    final total = MoneyTotal();
    for (final money in amounts) {
      total.add(money);
    }
    return total;
  }

  void add(Money money) {
    _byCurrency.update(money.currency, (v) => v + money.amount,
        ifAbsent: () => money.amount);
  }

  void addAmount(double amount, Currency currency) =>
      add(Money(amount, currency));

  bool get isEmpty => _byCurrency.isEmpty;

  /// More than one currency went in, so no single number is the answer.
  bool get isMixed => _byCurrency.length > 1;

  /// Every currency present, largest total first.
  List<Money> get parts {
    final parts = [
      for (final e in _byCurrency.entries) Money(e.value, e.key),
    ];
    parts.sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
    return parts;
  }

  /// Every currency actually recorded in this total.
  ///
  /// Empty means no records, which is not the same as records in the default
  /// currency — the distinction [single] cannot make, and the reason it needs
  /// a fallback handed to it.
  Set<Currency> get currencies => _byCurrency.keys.toSet();

  /// The total, when there is one currency to state it in.
  ///
  /// An empty total is zero in [fallback], because nothing spent is a figure
  /// and not an absence. A mixed one is null: there is no single number, and
  /// returning the largest part would be the lie this class exists to prevent.
  Money? single(Currency fallback) => switch (_byCurrency.length) {
        0 => Money.zero(fallback),
        1 => parts.first,
        _ => null,
      };

  /// How it reads on one line, however many currencies are in it.
  String format(Currency fallback, {int decimals = 0}) {
    final one = single(fallback);
    if (one != null) return one.format(decimals: decimals);
    return parts.map((m) => m.format(decimals: decimals)).join(' + ');
  }
}
