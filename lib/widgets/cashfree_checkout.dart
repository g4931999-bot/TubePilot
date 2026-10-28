import 'dart:async';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart'; // ✅ FIXED: Web not Drop
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import '../services/api_service.dart';

/// Result of one diamond purchase attempt.
/// status: 'approved' | 'rejected' | 'pending' | 'error' | 'no_callback'
class CashfreeResult {
  final String status;
  final String message; // real reason (Cashfree SDK / backend text), safe to show
  const CashfreeResult(this.status, [this.message = '']);
  bool get approved => status == 'approved';
}

/// Same checkout flow as Live Plans (which works), packaged for the Diamond Store (UPDATE18).
///
///  * Opens checkout in the SAME environment the backend created the order in
///    (create-order now returns `cashfreeEnvironment`) - a sandbox/production
///    mismatch is what makes the checkout open and close instantly.
///  * Registers the SDK callbacks BEFORE doPayment, and always reports the SDK's
///    own error text, so a failure is never silent.
///  * After checkout it asks the backend (which asks Cashfree) for the final
///    status - never trusts the app alone.
///
/// Usage in diamond_store_screen.dart (inside the Buy button handler):
///   final r = await CashfreeCheckout().pay(pkg['diamonds'] as int);
///   if (r.approved) { showToast(context, 'Diamonds added', isSuccess: true); _load(); }
///   else if (r.status != 'pending') { showToast(context, r.message, isError: true); }
class CashfreeCheckout {
  final CFPaymentGatewayService _service = CFPaymentGatewayService();
  static const _callbackTimeout = Duration(seconds: 120);

  Future<CashfreeResult> pay(int diamonds) async {
    String orderId;
    String sessionId;
    CFEnvironment env;
    try {
      final res = await ApiService.instance.createCashfreeOrder(diamonds);
      orderId = (res['orderId'] ?? '').toString();
      sessionId = (res['paymentSessionId'] ?? '').toString().trim();
      env = (res['cashfreeEnvironment'] ?? '').toString().toUpperCase() == 'SANDBOX' ? CFEnvironment.SANDBOX : CFEnvironment.PRODUCTION;
      if (orderId.isEmpty || sessionId.isEmpty) {
        return const CashfreeResult('error', 'Server did not return a payment session. Backend response: $res');
      }
      print('[Cashfree] Order created: orderId=$orderId env=$env sessionLen=${sessionId.length}');
    } catch (e) {
      print('[Cashfree] create-order failed: $e');
      return CashfreeResult('error', e.toString());
    }

    final done = Completer<CashfreeResult>();

    // 1) callbacks FIRST - before doPayment
    _service.setCallback(
      (String verifiedOrderId) async {
        print('[Cashfree] onVerify success: $verifiedOrderId');
        if (!done.isCompleted) done.complete(await _confirm(verifiedOrderId));
      },
      (CFErrorResponse err, String failedOrderId) async {
        final reason = [err.getMessage(), err.getCode(), err.getType(), err.getStatus()]
            .where((e) => (e ?? '').toString().isNotEmpty)
            .join(' | ');
        print('[Cashfree] onError for $failedOrderId: $reason');
        // The payment may still have gone through - ask the backend before reporting failure.
        final r = await _confirm(failedOrderId, sdkError: reason);
        if (!done.isCompleted) done.complete(r);
      },
    );

    // 2) then open checkout - ✅ FIXED: CFWebCheckoutPaymentBuilder
    try {
      final session = CFSessionBuilder()
          .setEnvironment(env)
          .setOrderId(orderId)
          .setPaymentSessionId(sessionId)
          .build();
      
      // ✅ MAIN FIX: CFWebCheckoutPaymentBuilder instead of CFDropCheckoutPaymentBuilder
      // Drop causes INVALID_WEB_DATA and instant close (0.0 sec)
      final payment = CFWebCheckoutPaymentBuilder()
          .setSession(session)
          .build();
      
      print('[Cashfree] Opening CFWebCheckoutPayment for $orderId');
      _service.doPayment(payment);
    } on CFException catch (e) {
      print('[Cashfree] CFException opening checkout: ${e.message}');
      return CashfreeResult('error', e.message ?? 'Could not open checkout.');
    } catch (e) {
      print('[Cashfree] Exception opening checkout: $e');
      return CashfreeResult('error', e.toString());
    }

    return done.future.timeout(_callbackTimeout, onTimeout: () async {
      print('[Cashfree] Timeout - no callback in ${_callbackTimeout.inSeconds}s');
      // No callback at all: still check the real status once.
      final r = await _confirm(orderId);
      return r.status == 'pending' 
          ? const CashfreeResult('no_callback', 'Checkout closed without a response. If money was deducted, diamonds will be added automatically.') 
          : r;
    });
  }

  Future<CashfreeResult> _confirm(String orderId, {String? sdkError}) async {
    try {
      for (var i = 0; i < 6; i++) {
        print('[Cashfree] Verifying $orderId attempt ${i+1}/6');
        final res = await ApiService.instance.verifyCashfreePayment(orderId);
        final status = (res['status'] ?? '').toString();
        print('[Cashfree] Verify response: status=$status');
        if (status == 'approved') return const CashfreeResult('approved');
        if (status == 'rejected') return CashfreeResult('rejected', sdkError ?? 'Payment was not completed.');
        await Future.delayed(const Duration(seconds: 3));
      }
      return CashfreeResult('pending', sdkError ?? 'Payment is still being confirmed. Diamonds will be added automatically once it succeeds.');
    } catch (e) {
      print('[Cashfree] Confirm error: $e');
      return CashfreeResult('error', sdkError ?? e.toString());
    }
  }
}
