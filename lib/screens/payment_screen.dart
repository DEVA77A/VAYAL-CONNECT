import '../widgets/brand_widgets.dart';
import '../utils/language_rebuild.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../utils/commerce_strings.dart';
import '../widgets/vayal_app_bar.dart';

class PaymentScreen extends StatefulWidget {
  final String orderId;
  final ApiClient? api;
  const PaymentScreen({super.key, required this.orderId, this.api});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with LanguageRebuild<PaymentScreen> {
  late final _api = widget.api ?? ApiClient();
  final _razorpay = Razorpay();
  Map<String, dynamic>? _checkout;
  bool _busy = false;
  bool _verified = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _success);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _failed);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _wallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = Map<String, dynamic>.from(await _api.request(
          '/api/v1/payments/${widget.orderId}/checkout',
          method: 'POST'));
      if (data['test_mode'] != true ||
          !(data['key_id'] as String).startsWith('rzp_test_')) {
        throw Exception(S.t('Unable to complete this request. Please retry.'));
      }
      if (!mounted) return;
      _checkout = data;
      _razorpay.open({
        'key': data['key_id'],
        'amount': data['amount_paise'],
        'currency': data['currency'],
        'order_id': data['razorpay_order_id'],
        'name': 'VayalConnect',
        'description': S.t('Razorpay TEST MODE — no real money'),
        'prefill': {'email': SessionManager().currentUser?.email ?? ''},
        'timeout': 180
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _message = e.toString();
          _busy = false;
        });
      }
    }
  }

  Future<void> _success(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => _message =
        S.t('Payment awaiting server verification. Refresh order status.'));
    try {
      if (_checkout == null ||
          response.paymentId == null ||
          response.signature == null) {
        throw Exception(S.t('Invalid server response. Please retry.'));
      }
      final data =
          await _api.request('/api/v1/payments/verify', method: 'POST', body: {
        'order_id': widget.orderId,
        'razorpay_order_id': _checkout!['razorpay_order_id'],
        'razorpay_payment_id': response.paymentId,
        'razorpay_signature': response.signature
      });
      if (mounted) {
        setState(() {
          _verified = data['payment_verified'] == true;
          _message = S.t(data['order_status'] == 'CANCELLED'
              ? 'Payment captured after cancellation. Refund review required.'
              : _verified
                  ? 'Verified test payment.'
                  : 'Payment awaiting server verification. Refresh order status.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _message =
            '${S.t('Payment awaiting server verification. Refresh order status.')}\n$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _failed(PaymentFailureResponse response) {
    if (mounted) {
      setState(() {
        _busy = false;
        _message =
            S.t('Payment cancelled or failed. Your order remains pending.');
      });
    }
  }

  void _wallet(ExternalWalletResponse response) {
    if (mounted) {
      setState(() {
        _busy = false;
        _message =
            S.t('Payment awaiting server verification. Refresh order status.');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: VayalAppBar(title: S.t('Payment'), showBack: true),
      body: PageBody(
          child: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BrandHeading(
                            title: S.t('Payment'), icon: Icons.lock_outline),
                        SectionCard(
                            title: 'Payment',
                            icon: Icons.lock_outline,
                            children: [
                              Text(S.t('Razorpay TEST MODE — no real money'),
                                  textAlign: TextAlign.center),
                            ]),
                        if (_message != null)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Text(_message!,
                                          textAlign: TextAlign.center)))),
                        if (_busy) const LinearProgressIndicator(),
                        if (!_verified)
                          ElevatedButton(
                              onPressed: _busy ? null : _pay,
                              child: Text(S.t('Pay in test mode'))),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(S.t('View orders'))),
                      ])))));
}
