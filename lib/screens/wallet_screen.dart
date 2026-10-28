import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/app_brand_background.dart';
import '../providers/language_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? wallet;
  bool loading = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final res = await ApiService.instance.getWallet();
      setState(() => wallet = res['wallet']);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  (Color, String) _statusBadge(BuildContext context, String status) {
    switch (status) {
      case 'pending': return (AppColors.diamond, context.tr('status_pending'));
      case 'approved': return (AppColors.green, context.tr('status_approved'));
      case 'rejected': return (AppColors.red, context.tr('status_rejected'));
      case 'completed': return (AppColors.green, context.tr('status_completed'));
      default: return (AppColors.diamond, status);
    }
  }

  // Real transaction-type icons, replacing any emoji previously used —
  // gives each row a proper Material icon matched to what happened.
  (IconData, Color) _txnIcon(Map t, bool isSpend) {
    if (t['type'] == 'diamond_purchase') return (Icons.diamond_rounded, AppColors.diamond);
    if (isSpend) return (Icons.upload_rounded, AppColors.red);
    return (Icons.replay_rounded, AppColors.green);
  }

  @override
  Widget build(BuildContext context) {
    // Festival background wrapper — shows the shared festival image when
    // festival mode is on, and draws nothing extra when it is off.
    return AppBrandBackground(
      watermarkWhenNormal: false,
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    final all = (wallet?['transactions'] as List?) ?? [];
    final purchasesOnly = all.where((t) => t['type'] == 'diamond_purchase').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('wallet_title')),
        bottom: TabBar(controller: _tabController, labelColor: AppColors.purple, indicatorColor: AppColors.purple, tabs: [
          Tab(text: context.tr('transactions_tab')), Tab(text: context.tr('purchases_tab')),
        ]),
      ),
      body: loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(18)),
                    child: Column(children: [
                      Text(context.tr('total_diamonds'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.diamond_rounded, color: AppColors.diamond, size: 24),
                        const SizedBox(width: 8),
                        Text('${wallet?['diamondBalance'] ?? 0}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                      ]),
                      const SizedBox(height: 6),
                      Text(context.tr('free_uploads_remaining').replaceAll('%d', '${wallet?['freeUploadsRemaining'] ?? 0}'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 400,
                    child: TabBarView(controller: _tabController, children: [
                      _buildList(context, all),
                      _buildList(context, purchasesOnly),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildList(BuildContext context, List list) {
    if (list.isEmpty) return EmptyView(message: context.tr('no_transactions_yet'), icon: Icons.receipt_long_outlined);
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: list.length,
      itemBuilder: (_, i) {
        final t = list[i];
        final isSpend = t['type'] == 'diamond_spend';
        final isRefund = t['type'] == 'diamond_refund';
        final label = t['type'] == 'diamond_purchase'
            ? context.tr('diamond_pack_label').replaceAll('%s', '${t['diamondPackage']}')
            : (isSpend ? context.tr('video_scheduled_label') : context.tr('diamond_refund_label'));
        final amount = t['type'] == 'diamond_purchase' ? '+${t['diamondPackage']}' : (isSpend ? '-${t['diamondsForSpend']}' : '+${t['diamondsForSpend']}');
        final (color, statusLabel) = _statusBadge(context, t['status'] ?? '');
        final (icon, iconColor) = _txnIcon(t, isSpend);
        // Auto-refund entries (post failed after retries, upload cancelled,
        // etc.) get their own green badge + reason line instead of the
        // generic pending/approved/rejected status badge.
        final refundNote = (t['adminNote'] ?? '').toString();
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: isRefund ? AppColors.green.withValues(alpha: 0.5) : context.surfaces.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 38, height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(formatDateTime(t['createdAt']), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                  if (isRefund && refundNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(refundNote, style: const TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(amount, style: TextStyle(fontWeight: FontWeight.w700, color: isSpend ? AppColors.red : AppColors.green)),
                const SizedBox(height: 4),
                isRefund
                    ? AppBadge(label: context.tr('auto_refunded_badge'), color: AppColors.green)
                    : AppBadge(label: statusLabel, color: color),
              ]),
            ],
          ),
        );
      },
    );
  }
}