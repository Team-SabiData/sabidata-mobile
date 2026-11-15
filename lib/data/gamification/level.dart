import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// Progression du contributeur calculée à partir des points cumulés.
/// Les seuils par défaut sont un contrat front temporaire et peuvent être
/// remplacés par `levelThresholds` renvoyé par l'API.
class LevelInfo {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final int currentAt;
  final int? nextAt;
  final double progress;

  const LevelInfo({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.currentAt,
    required this.nextAt,
    required this.progress,
  });

  static const int argentAt = 500;
  static const int orAt = 2000;

  static Map<String, int> normalizeThresholds(Map<String, dynamic>? raw) {
    int read(String key, int fallback) {
      final value = raw?[key];
      return value is num && value.toInt() > 0 ? value.toInt() : fallback;
    }

    final argent = read('argent', argentAt);
    final or = read('or', orAt);
    return {'bronze': 0, 'argent': argent, 'or': or > argent ? or : argent + 1};
  }

  factory LevelInfo.of(String serverLevel, int points, {Map<String, dynamic>? thresholds}) {
    final limits = normalizeThresholds(thresholds);
    // Le serveur reste la source d'autorité sur le badge. Les points donnent
    // la barre de progression et servent de repli si le niveau est absent.
    final normalized = serverLevel.toLowerCase();
    final key = const {'bronze', 'argent', 'or'}.contains(normalized)
        ? normalized
        : points >= limits['or']! ? 'or'
        : points >= limits['argent']! ? 'argent' : 'bronze';
    final int start = limits[key]!;
    final int? next = key == 'bronze' ? limits['argent'] : key == 'argent' ? limits['or'] : null;
    final double progress = next == null
        ? 1.0
        : ((points - start) / (next - start)).clamp(0.0, 1.0);
    switch (key) {
      case 'or':
        return LevelInfo(key: key, label: 'Gardien Or', icon: Icons.verified_rounded,
            color: AppColors.gold, currentAt: start, nextAt: null, progress: progress);
      case 'argent':
        return LevelInfo(key: key, label: 'Gardien Argent', icon: Icons.shield_rounded,
            color: const Color(0xFF9BA3B5), currentAt: start, nextAt: next, progress: progress);
      default:
        return LevelInfo(key: 'bronze', label: 'Gardien Bronze', icon: Icons.shield_outlined,
            color: AppColors.bronzeBadge, currentAt: 0, nextAt: limits['argent'],
            progress: (points / limits['argent']!).clamp(0.0, 1.0));
    }
  }

  int pointsRemaining(int points) => nextAt == null ? 0 : (nextAt! - points).clamp(0, nextAt!);
}
