import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import 'diamond_store_screen.dart';

/// Wallet & Refund Logs (UPDATE15 UI upgrade).
/// Balance = GET /wallet. Refunds = GET /wallet/refunds?days=N, built from the
/// user's REAL uploads that failed after retries and were refunded.
class WalletRefundLogsScreen extends StatefulWidget {
  const WalletRefundLogsScreen({super.key});
  @override
  State<WalletRefundLogsScreen> createState() => _WalletRefundLogsScreenState();
}

class _WalletRefundLogsScreenState extends State<WalletRefundLogsScreen> {
  int _days = 30;
  int _balance = 0;
  List<Map<String, dynamic>> _refunds = [];
  int _totalRefunded = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([ApiService.instance.getWallet(), ApiService.instance.getRefundLogs(days: _days)]);
      if (!mounted) return;
      setState(() {
        _balance = (res[0]['wallet']?['diamondBalance'] as num?)?.toInt() ?? 0;
        _refunds = ((res[1]['refunds'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _totalRefunded = (res[1]['totalDiamondsRefunded'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatDate(dynamic raw) {
    final d = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _pickRange() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          for (final d in const [7, 30, 90])
            ListTile(
              title: Text(context.tr('wr_last_days').replaceAll('%1', '$d'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: _days == d ? const Icon(Icons.check_rounded, color: AppColors.purple) : null,
              onTap: () {
                Navigator.pop(c);
                if (_days != d) {
                  _days = d;
                  _load();
                }
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _balanceCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(18), border: Border.all(color: context.surfaces.border)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('diamond_balance_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.diamond_rounded, color: AppColors.diamond, size: 26),
              const SizedBox(width: 8),
              Text('$_balance', style: const TextStyle(color: AppColors.purple, fontSize: 30, fontWeight: FontWeight.w900)),
            ]),
          ]),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen())).then((_) => _load()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.purple,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(context.tr('upgrade_btn')),
          ),
        ]),
      );

  Widget _refundTile(Map<String, dynamic> r) {
    final diamonds = (r['diamondsRefunded'] as num?)?.toInt() ?? 0;
    final title = (r['title'] ?? '').toString();
    final reason = (r['reason'] ?? '').toString();
    final platform = (r['platform'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: AppColors.green.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.replay_rounded, color: AppColors.green, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              diamonds > 0 ? context.tr('diamonds_auto_refunded').replaceAll('%d', '$diamonds') : context.tr('wr_free_upload_refunded'),
              style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.green, fontSize: 13.5),
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(context.tr('wr_reason').replaceAll('%1', reason), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
            ],
            const SizedBox(height: 4),
            Text([_formatDate(r['refundedAt']), if (platform.isNotEmpty) platform].join('  ·  '), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('wallet_refund_logs_title'))),
      body: _loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.purple,
              child: ListView(padding: const EdgeInsets.all(20), children: [
                _balanceCard(),
                const SizedBox(height: 24),
                Row(children: [
                  Expanded(child: Text(context.tr('auto_refund_history'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(context.tr('wr_last_days').replaceAll('%1', '$_days')),
                  ),
                ]),
                if (_refunds.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    context.tr('wr_summary').replaceAll('%1', '${_refunds.length}').replaceAll('%2', '$_totalRefunded'),
                    style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                if (_refunds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(children: [
                      Icon(Icons.replay_rounded, size: 44, color: context.surfaces.textDim),
                      const SizedBox(height: 12),
                      Text(context.tr('wr_empty_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 6),
                      Text(context.tr('wr_empty_sub'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4)),
                    ]),
                  )
                else
                  ..._refunds.map(_refundTile),
              ]),
            ),
    );
  }
}