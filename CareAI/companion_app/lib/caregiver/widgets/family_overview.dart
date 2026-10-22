import 'package:flutter/material.dart';

import '../../theme/careai_theme.dart';

/// The family overview presentation; counts and actions are supplied by HomeScreen.
class CareAiFamilyOverview extends StatelessWidget {
  const CareAiFamilyOverview({
    super.key,
    required this.caregiverName,
    required this.elderCount,
    required this.openIncidents,
    required this.isLoadingIncidents,
    required this.onIncidents,
  });

  final String caregiverName;
  final int elderCount;
  final int openIncidents;
  final bool isLoadingIncidents;
  final VoidCallback onIncidents;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chào bạn,',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: CareAiColors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      caregiverName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.7,
                        color: CareAiColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Hôm nay của gia đình',
                      style: TextStyle(
                        fontSize: 13,
                        color: CareAiColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!largeText)
              Image.asset(
                'assets/images/facare/girl-greeting-clean.png',
                width: 118,
                height: 132,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
          ],
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFFEBF1E0),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              if (!largeText)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: ExcludeSemantics(
                    child: Image.asset(
                      'assets/images/facare/card1-green-b.png',
                      width: 142,
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: FractionallySizedBox(
                  widthFactor: largeText ? 1 : 0.64,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoadingIncidents
                            ? 'Đang cập nhật\nsự cố gia đình'
                            : openIncidents > 0
                            ? '$openIncidents sự cố\ncần tiếp nhận'
                            : 'Cùng quan tâm\nngười thương.',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          letterSpacing: -0.4,
                          color: CareAiColors.ink,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 42),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: onIncidents,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                'Xem sự cố',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final tiles = [
              _overviewTile(
                icon: Icons.people_outline_rounded,
                value: '$elderCount',
                label: 'hồ sơ gia đình',
                color: const Color(0xFFEDF2E6),
                iconColor: CareAiColors.greenInk,
              ),
              _overviewTile(
                icon: Icons.notifications_none_rounded,
                value: isLoadingIncidents ? '—' : '$openIncidents',
                label: 'sự cố cần tiếp nhận',
                color: CareAiColors.lavender,
                iconColor: CareAiColors.lavenderInk,
              ),
            ];
            if (largeText) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [tiles[0], const SizedBox(height: 12), tiles[1]],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: tiles[0]),
                  const SizedBox(width: 12),
                  Expanded(child: tiles[1]),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _overviewTile({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
    required Color iconColor,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.09),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 25,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: CareAiColors.ink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            height: 1.4,
            color: CareAiColors.brown,
          ),
        ),
      ],
    ),
  );
}
