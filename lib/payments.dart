import 'api.dart';
import 'pok_pay.dart';

/// A coin package with its prices: lek (card / POK app) and PayPal (euro by default).
class PayPackage {
  PayPackage(Map<String, dynamic> j)
    : id = j['id'] as int,
      coins = j['coins'] as int,
      bonus = j['bonus'] as int,
      priceAll = j['price_all'] as int,
      priceEur = (j['price_eur'] as num?)?.toDouble(),
      pricePaypal = (j['price_paypal'] as num?)?.toDouble();
  final int id, coins, bonus, priceAll;

  /// Card price in euro (for people abroad), if set.
  final double? priceEur;

  /// Price on PayPal, when PayPal is on.
  final double? pricePaypal;

  int get total => coins + bonus;
}

/// How people can buy coins: POK (card / POK app, lek) and PayPal.
class PayOptions {
  PayOptions(Map<String, dynamic> j)
    : packages = (j['packages'] as List)
          .map((e) => PayPackage(e as Map<String, dynamic>))
          .toList(),
      pok = (j['pok'] as bool?) ?? false,
      paypal = (j['paypal'] as bool?) ?? false,
      paypalCurrency = (j['paypal_currency'] as String?) ?? 'EUR',
      payments = ((j['pok_payments'] as List?) ?? const [])
          .map((e) => PokPayment(e as Map<String, dynamic>))
          .toList(),
      firstPurchaseBonus = (j['first_purchase_bonus'] as int?) ?? 0;
  final List<PayPackage> packages;
  final bool pok, paypal;
  final String paypalCurrency;

  /// Recent payments (pending ones can be continued).
  final List<PokPayment> payments;

  /// Extra coins (%) on this person's first purchase; 0 when used or off.
  final int firstPurchaseBonus;

  bool get available => (pok || paypal) && packages.isNotEmpty;

  static Future<PayOptions> load(Api api) async =>
      PayOptions(await api.get('/pay/options') as Map<String, dynamic>);
}

String formatLek(int n) =>
    '${n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')} L';

String formatMoney(double amount, String currency) => switch (currency) {
  'ALL' => formatLek(amount.round()),
  'EUR' => '€${amount.toStringAsFixed(2)}',
  'USD' => '\$${amount.toStringAsFixed(2)}',
  'GBP' => '£${amount.toStringAsFixed(2)}',
  _ => '${amount.toStringAsFixed(2)} $currency',
};
