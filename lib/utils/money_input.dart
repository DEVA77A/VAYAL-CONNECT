/// Parse rupee input exactly into paise, without floating point rounding.
int? parseSellingPricePaise(String value) {
  final cleaned = value.trim();
  if (!RegExp(r'^[0-9]+(\.[0-9]{1,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 1000000) return null;
  final fraction = parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0;
  final paise = whole * 100 + fraction;
  return paise > 0 && paise <= 100000000 ? paise : null;
}
