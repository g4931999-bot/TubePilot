import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:payu_checkoutpro_flutter/payu_checkoutpro_flutter.dart';
import 'package:payu_checkoutpro_flutter/PayUConstantKeys.dart';
import '../services/api_service.dart';

/// status: 'approved' | 'failed' | 'pending' | 'cancelled' | 'error'
class PayuResult {
  final String status;
  final String message;
  const PayuResult(this.status, [this.message = '']);
  bool get approved => status == 'approved';
}

class PayuCheckout implements PayUCheckoutProProtocol {
  late final PayUCheckoutProFlutter _pro;
  Completer<PayuResult>? _done;
  String _txnid = '';

  PayuCheckout() {
    _pro = PayUCheckoutProFlutter(this);
  }

  Future<PayuResult> pay(int diamonds) async {
    Map<String, dynamic> p;
    try {
      final res = await ApiService.instance.createPayuOrder(diamonds);
      p = Map<String, dynamic>.from(res['payu'] as Map);
      _txnid = p['txnid'].toString();
    } catch (e) {
      debugPrint('[PayU] create-order failed: $e');
      return PayuResult('error', e.toString());
    }

    _done = Completer<PayuResult>();

    final params = {
      PayUPaymentParamKey.key: p['key'],
      PayUPaymentParamKey.amount: p['amount'],
      PayUPaymentParamKey.productInfo: p['productinfo'],
      PayUPaymentParamKey.firstName: p['firstname'],
      PayUPaymentParamKey.email: p['email'],
      PayUPaymentParamKey.phone: p['phone'],
      PayUPaymentParamKey.environment: p['environment'], // "0" = production
      PayUPaymentParamKey.transactionId: p['txnid'],
      PayUPaymentParamKey.userCredential: '${p['key']}:${p['userId']}',
      PayUPaymentParamKey.android_surl: p['surl'],
      PayUPaymentParamKey.android_furl: p['furl'],
      PayUPaymentParamKey.ios_surl: p['surl'],
      PayUPaymentParamKey.ios_furl: p['furl'],
    };
    final config = {
      PayUCheckoutProConfigKeys.merchantName: 'TubePilot',
      PayUCheckoutProConfigKeys.showExitConfirmationOnCheckoutScreen: true,
    };

    try {
      debugPrint('[PayU] Opening checkout txn=$_txnid');
      _pro.openCheckoutScreen(payUPaymentParams: params, payUCheckoutProConfig: config);
    } catch (e) {
      debugPrint('[PayU] open failed: $e');
      return PayuResult('error', 'Could not open checkout: $e');
    }

    return _done!.future.timeout(const Duration(minutes: 10), onTimeout: () => _confirm(_txnid, attempts: 2));
  }

  Future<PayuResult> _confirm(String txnid, {int attempts = 6, String? sdkMsg}) async {
    try {
      for (var i = 1; i <= attempts; i++) {
        debugPrint('[PayU] Verifying $txnid attempt $i/$attempts');
        final res = await ApiService.instance.verifyPayuPayment(txnid);
        final status = (res['status'] ?? '').toString();
        if (status == 'approved') return const PayuResult('approved');
        if (status == 'failed') return PayuResult('failed', sdkMsg ?? 'Payment was not completed.');
        if (i < attempts) await Future.delayed(const Duration(seconds: 3));
      }
      return const PayuResult('pending', 'Payment is still being confirmed. Diamonds will be added automatically once it succeeds.');
    } catch (e) {
      return PayuResult('error', sdkMsg ?? e.toString());
    }
  }

  void _finish(PayuResult r) {
    if (_done != null && !_done!.isCompleted) _done!.complete(r);
  }

  // ---------------- PayUCheckoutProProtocol ----------------
  @override
  generateHash(Map response) async {
    final name = response['hashName']?.toString() ?? '';
    try {
      final r = await ApiService.instance.payuHash(
        hashName: name,
        hashString: response['hashString']?.toString() ?? '',
        hashType: response['hashType']?.toString(),
        postSalt: response['postSalt']?.toString(),
      );
      _pro.hashGenerated(hash: {name: r['hash']});
    } catch (e) {
      debugPrint('[PayU] hash failed for $name: $e');
    }
  }

  @override
  onPaymentSuccess(dynamic response) async {
    debugPrint('[PayU] onPaymentSuccess');
    _finish(await _confirm(_txnid)); // never trust the SDK alone
  }

  @override
  onPaymentFailure(dynamic response) async {
    debugPrint('[PayU] onPaymentFailure: $response');
    _finish(await _confirm(_txnid, attempts: 2, sdkMsg: 'Payment failed. Please try again.'));
  }

  @override
  onPaymentCancel(Map? response) async {
    debugPrint('[PayU] onPaymentCancel');
    final r = await _confirm(_txnid, attempts: 1);
    _finish(r.status == 'pending' ? const PayuResult('cancelled', 'Payment cancelled.') : r);
  }

  @override
  onError(Map? response) async {
    debugPrint('[PayU] onError: $response');
    final r = await _confirm(_txnid, attempts: 1, sdkMsg: 'Checkout error: ${response ?? ''}');
    _finish(r.status == 'pending' ? PayuResult('error', 'Checkout error: ${response ?? ''}') : r);
  }
}