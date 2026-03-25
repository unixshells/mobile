import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import '../util/constants.dart';

/// Product IDs — must match App Store Connect / Google Play Console.
const kShellMonthly = 'com.unixshells.shell.monthly';
const kShellYearly = 'com.unixshells.shell.yearly';
const kShellPlusMonthly = 'com.unixshells.shell_plus.monthly';
const kShellPlusYearly = 'com.unixshells.shell_plus.yearly';

const _allProductIds = {
  kShellMonthly,
  kShellYearly,
  kShellPlusMonthly,
  kShellPlusYearly,
};

/// Manages in-app purchase flow for shell subscriptions.
class IAPService extends ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  List<ProductDetails> products = [];
  bool available = false;
  bool purchasing = false;
  String? error;
  String? successMessage;

  /// Server auth token for receipt validation.
  String authToken = '';
  String username = '';

  Future<void> init() async {
    available = await _iap.isAvailable();
    if (!available) return;

    _sub = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _sub?.cancel(),
      onError: (e) => debugPrint('iap stream error: $e'),
    );

    await loadProducts();
  }

  Future<void> loadProducts() async {
    final response = await _iap.queryProductDetails(_allProductIds);
    if (response.error != null) {
      error = response.error!.message;
      notifyListeners();
      return;
    }
    products = response.productDetails;
    notifyListeners();
  }

  /// Start a purchase flow.
  Future<void> purchase(ProductDetails product) async {
    purchasing = true;
    error = null;
    successMessage = null;
    notifyListeners();

    final param = PurchaseParam(productDetails: product);
    try {
      await _iap.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      error = e.toString();
      purchasing = false;
      notifyListeners();
    }
  }

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _verifyAndDeliver(p);
          break;
        case PurchaseStatus.error:
          error = p.error?.message ?? 'Purchase failed';
          purchasing = false;
          notifyListeners();
          break;
        case PurchaseStatus.canceled:
          purchasing = false;
          notifyListeners();
          break;
        case PurchaseStatus.pending:
          break;
      }

      if (p.pendingCompletePurchase) {
        _iap.completePurchase(p);
      }
    }
  }

  /// Send receipt to our server for validation + shell provisioning.
  Future<void> _verifyAndDeliver(PurchaseDetails purchase) async {
    try {
      final receiptData = <String, dynamic>{
        'username': username,
        'product_id': purchase.productID,
        'platform': Platform.isIOS ? 'apple' : 'google',
      };

      if (Platform.isIOS) {
        receiptData['receipt_data'] = purchase.verificationData.serverVerificationData;
      } else {
        receiptData['purchase_token'] = purchase.verificationData.serverVerificationData;
        receiptData['package_name'] = 'com.unixshells.unixshells';
      }

      final resp = await http.post(
        Uri.parse('$apiBaseURL/api/iap/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(receiptData),
      );

      if (resp.statusCode == 200) {
        successMessage = 'Shell provisioning started. It will appear in your devices shortly.';
      } else {
        final body = jsonDecode(resp.body);
        error = body['error'] ?? 'Verification failed';
      }
    } catch (e) {
      error = 'Failed to verify purchase: $e';
    }

    purchasing = false;
    notifyListeners();
  }

  /// Restore previous purchases (required by App Store guidelines).
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
