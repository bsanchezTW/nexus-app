import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Barra de progreso + porcentaje para la descarga OTA.
class UpdateProgressView extends StatelessWidget {
  const UpdateProgressView({super.key, required this.progress, this.label});

  final double progress;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 8,
            backgroundColor: AppColors.tintNavy,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label ?? 'Descargando… $pct%',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
