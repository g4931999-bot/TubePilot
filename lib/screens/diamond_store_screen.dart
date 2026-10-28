import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/payu_checkout.dart';
import '../providers/language_provider.dart';
import 'live_plans_screen.dart';

class DiamondStoreScreen extends StatefulWidget {
  const DiamondStoreScreen({super.key});
  @override
  State<DiamondStoreScreen> createState() => _DiamondStoreScreenState();
}

class _DiamondStoreScreenState extends State<DiamondStoreScreen> {
  static const String supportEmail = 'support@tubepilot.com';

  List<dynamic> packages = [];
  int balance = 0;
  bool loading = true;
  int? _payingDiamonds;

  final PayuCheckout _payu = PayuCheckout();

  Future<void> _openSupportEmail() async {
    final uri = Uri(scheme: 'mailto', path: supportEmail);
    final opened = await launchUrl(uri);
    if (!opened && mounted) {
      showToast(context, context.tr('diamond_support_error'), isError: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final pkgRes = await ApiService.instance.getDiamondPackages();
      debugPrint('[Diamond] packages loaded: ${pkgRes['packages']?.length}');
      setState(() {
        packages = pkgRes['packages'];
        balance = pkgRes['currentBalance'] ?? 0;
      });
    } catch (e) {
      debugPrint('[Diamond] load failed: $e');
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _buy(int diamonds) async {
    if (_payingDiamonds != null) return;
    setState(() => _payingDiamonds = diamonds);
    try {
      final r = await _payu.pay(diamonds);
      if (!mounted) return;
      if (r.approved) {
        showToast(context, context.tr('payment_submitted_msg'), isSuccess: true);
        _load();
      } else if (r.status == 'pending') {
        showToast(context, r.message, isError: false);
      } else if (r.status != 'cancelled') {
        showToast(context, r.message, isError: true);
      }
    } catch (e) {
      debugPrint('[PayU] Buy failed: $e');
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _payingDiamonds = null);
    }
  }

  Widget _topSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.surfaces.card2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(999)),
              child: const Center(
                child: Text('💎 Diamonds', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LivePlansScreen())),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    '📡 Live Stream',
                    style: TextStyle(color: context.surfaces.textDim, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _payingDiamonds == null,
      onPopInvoked: (didPop) {
        if (!didPop && _payingDiamonds != null) {
          showToast(context, 'Please wait — confirming your payment...', isError: false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('diamond_store_title')),
        ),
        body: loading
            ? const LoadingView()
            : SafeArea(
                bottom: true,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom + 24),
                  children: [
                    _topSwitcher(),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(context.tr('your_balance'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                        Text('💎 $balance', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    Text(context.tr('choose_package'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('diamond_store_description'),
                      style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(
                      packages.length,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _packageCard(context, index),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _enterpriseCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _packageCard(BuildContext context, int index) {
    final p = packages[index];
    final diamonds = p['diamonds'] as int;
    final price = (p['priceINR'] as num).toDouble();
    final isPaying = _payingDiamonds == diamonds;
    final perRupee = price > 0 ? (diamonds / price) : 0;

    final List<dynamic> features = (p['features'] as List<dynamic>?) ?? [];

    String? badgeText;
    Color? badgeColor;
    if (packages.length >= 3) {
      if (index == packages.length - 1) {
        badgeText = context.tr('diamond_badge_best_value');
        badgeColor = AppColors.green;
      } else if (index == 1) {
        badgeText = context.tr('diamond_badge_popular');
        badgeColor = Theme.of(context).colorScheme.primary;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 16),
      decoration: BoxDecoration(
        border: Border.all(color: badgeText != null ? (badgeColor ?? context.surfaces.border) : context.surfaces.border, width: badgeText != null ? 1.4 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (badgeText != null)
            Positioned(
              top: -22,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(999)),
                  child: Text(
                    badgeText.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('💎', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('diamonds_suffix').replaceAll('%d', '$diamonds'),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                        ),
                        const SizedBox(height: 2),
                        Text('₹${p['priceINR']}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (perRupee > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(999)),
                      child: Text(
                        context.tr('diamond_value_rate').replaceAll('%d', perRupee.toStringAsFixed(1)),
                        style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: context.surfaces.border),
              const SizedBox(height: 12),
              Text(
                context.tr('diamond_whats_included'),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
              const SizedBox(height: 8),
              ...features.map((f) {
                final bool included = f['included'] == true;
                final String label = f['label'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        included ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 15,
                        color: included ? AppColors.green : context.surfaces.textDim,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.25,
                            color: included ? null : context.surfaces.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 14, color: AppColors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.tr('diamond_feature_instant'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _payingDiamonds != null ? null : () => _buy(diamonds),
                  child: isPaying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(context.tr('buy_btn')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _enterpriseCard() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _openSupportEmail,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppColors.gradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.workspaces_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('diamond_enterprise_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(context.tr('diamond_enterprise_subtitle'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mail_outline_rounded, color: Colors.white, size: 14),
                      const SizedBox(width: 5),
                      Text(context.tr('diamond_enterprise_cta'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _enterpriseFeatureRow(context.tr('diamond_enterprise_feature_1')),
                const SizedBox(height: 6),
                _enterpriseFeatureRow(context.tr('diamond_enterprise_feature_2')),
                const SizedBox(height: 6),
                _enterpriseFeatureRow(context.tr('diamond_enterprise_feature_3')),
              ],
            ),
            const SizedBox(height: 12),
            Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
            const SizedBox(height: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app_rounded, color: Colors.white70, size: 13),
                const SizedBox(width: 6),
                Text(
                  context.tr('diamond_support_title'),
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _enterpriseFeatureRow(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5))),
      ],
    );
  }
}