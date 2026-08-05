/// Reading a sum of money the way a person types one.
///
/// The project form had two different answers for the same text. The validator
/// read it as `text.replaceAll(',', '.')`; the save read it as a bare
/// `double.tryParse(...) ?? 0`. So a sofer entering the price of a sefer torah
/// the natural way — `40,000` — was told the form was fine and got a commission
/// priced at **zero**, because the validator saw 40.0 and the save saw nothing
/// at all. Every earning, hourly rate and quote for that job was zero from then
/// on, with nothing on any screen explaining why.
///
/// Both were wrong even where they agreed: a comma in `40,000` separates
/// thousands, and turning it into a decimal point gives forty.
///
/// One function now, used by the validator and by the save, so the two cannot
/// drift apart again.
class MoneyInput {
  const MoneyInput._();

  /// The characters people put between thousands and expect to be ignored.
  static final RegExp _grouping = RegExp(r'[,  \s]');

  /// Reads [text] as an amount, or null when it is not one.
  ///
  /// Grouping separators are dropped; a full stop is the decimal point. A comma
  /// is never a decimal point here — Hebrew and English both write 40.5, and
  /// reading `40,000` as forty is the failure this exists to prevent.
  static double? parse(String? text) {
    final trimmed = (text ?? '').trim();
    if (trimmed.isEmpty) return null;

    final stripped = trimmed.replaceAll(_grouping, '');
    if (stripped.isEmpty) return null;

    // A second full stop is a typo, not a number. `40.0.5` must be refused
    // rather than quietly becoming something.
    if ('.'.allMatches(stripped).length > 1) return null;

    final value = double.tryParse(stripped);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return value;
  }
}
