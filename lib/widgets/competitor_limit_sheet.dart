import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../screens/diamond_store_screen.dart';
import 'common.dart';

/// Opens the existing Diamond Store (the app's only plan/upgrade screen).
void openUpgradeScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
}

/// Shown when the user tries to add a competitor beyond their plan limit
/// (server code COMPETITOR_LIMIT_REACHED, or the app already knows the limit
/// is full). The backend enforces the limit — this is only the friendly prompt.
Future<void> showCompetitorLimitSheet(BuildContext context, {required int limit, required int current}) {
  final over = current > limit;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: sheetCtx.surfaces.border, borderRadius: BorderRadius.circular(999)),
              ),
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
                child: const Icon(Icons.radar_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              Text(
                sheetCtx.tr('rd_limit_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(color: sheetCtx.surfaces.card2, borderRadius: BorderRadius.circular(999)),
                child: Text('$current / $limit', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(height: 12),
              Text(
                over
                    ? sheetCtx.tr('rd_limit_over')
                    : sheetCtx.tr('rd_limit_body').replaceAll('%1', '$limit'),
                textAlign: TextAlign.center,
                style: TextStyle(color: sheetCtx.surfaces.textDim, fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: sheetCtx.tr('rd_limit_upgrade'),
                icon: Icons.workspace_premium_rounded,
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  openUpgradeScreen(context);
                },
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: Text(sheetCtx.tr('rd_limit_later'), style: TextStyle(color: sheetCtx.surfaces.textDim, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
    },
  );
}