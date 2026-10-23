import 'package:flutter/material.dart';

import '../theme/careai_theme.dart';

class CareAiBrand extends StatelessWidget {
  const CareAiBrand({super.key, this.subtitle = 'Chăm sóc gia đình'});
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: CareAiColors.muted,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CareAI',
              style: TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: CareAiColors.ink,
                letterSpacing: -0.6,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: CareAiColors.secondary,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class CareAiSectionHeading extends StatelessWidget {
  const CareAiSectionHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: CareAiColors.secondary),
              ),
            ],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

class CareAiStatusLabel extends StatelessWidget {
  const CareAiStatusLabel({
    super.key,
    required this.label,
    required this.icon,
    this.color = CareAiColors.brown,
    this.background,
  });
  final String label;
  final IconData icon;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: background ?? color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class CareAiEmptyState extends StatelessWidget {
  const CareAiEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                color: CareAiColors.greenSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 46, color: CareAiColors.greenInk),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: CareAiColors.secondary),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    ),
  );
}

/// The reference's curved white dock, with CareAI's existing destinations.
class CareAiFamilyDock extends StatelessWidget {
  const CareAiFamilyDock({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onAdd,
    required this.onHistory,
    required this.openIncidents,
  });
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onHistory;
  final int openIncidents;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = (constraints.maxWidth / 375).clamp(0.8, 1.25).toDouble();
      final bottom = MediaQuery.paddingOf(context).bottom;
      final width = constraints.maxWidth;
      final center = width / 2;
      final buttonSize = 64 * scale;
      final hitSize = (48 * scale).clamp(48.0, 60.0).toDouble();
      // The reference is a 375 x 128 SVG. Keep the same icon centres and notch.
      final positions = [
        width * 40 / 375,
        width * 108 / 375,
        width * 267 / 375,
        width * 335 / 375,
      ];
      return SizedBox(
        height: 128 * scale + bottom,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipPath(
                clipper: _FamilyDockClipper(scale),
                child: const ColoredBox(color: CareAiColors.surface),
              ),
            ),
            Positioned(
              left: positions[0] - hitSize / 2,
              top: 64 * scale,
              child: _destination(
                'Gia đình',
                Icons.home_rounded,
                index == 0,
                () => onSelect(0),
                hitSize,
              ),
            ),
            Positioned(
              left: positions[1] - hitSize / 2,
              top: 64 * scale,
              child: _destination(
                'Sự cố',
                Icons.notifications_none_rounded,
                index == 1,
                () => onSelect(1),
                hitSize,
                badge: openIncidents,
              ),
            ),
            Positioned(
              left: positions[2] - hitSize / 2,
              top: 64 * scale,
              child: _destination(
                'Lịch sử sự cố',
                Icons.history_rounded,
                false,
                onHistory,
                hitSize,
              ),
            ),
            Positioned(
              left: positions[3] - hitSize / 2,
              top: 64 * scale,
              child: _destination(
                'Tài khoản',
                Icons.person_outline_rounded,
                index == 2,
                () => onSelect(2),
                hitSize,
              ),
            ),
            Positioned(
              top: 16 * scale,
              left: center - buttonSize / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: CareAiColors.moss.withValues(alpha: 0.25),
                      blurRadius: 20 * scale,
                      offset: Offset(0, 8 * scale),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: buttonSize,
                  height: buttonSize,
                  child: IconButton.filled(
                    tooltip: 'Thêm người cao tuổi',
                    onPressed: onAdd,
                    style: IconButton.styleFrom(
                      backgroundColor: CareAiColors.moss,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                    icon: SizedBox.square(
                      dimension: 24 * scale,
                      child: CustomPaint(painter: _DockAddPainter()),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _destination(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
    double size, {
    int badge = 0,
  }) => Semantics(
    selected: selected,
    button: true,
    label: badge > 0 ? '$label, $badge chưa tiếp nhận' : label,
    child: Tooltip(
      message: label,
      child: Material(
        color: selected ? const Color(0xFFF7F4F2) : Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: ExcludeSemantics(
                child: Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: Icon(
                    icon,
                    size: 22 * size / 48,
                    color: selected
                        ? const Color(0xFF4B3425)
                        : CareAiColors.secondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FamilyDockClipper extends CustomClipper<Path> {
  const _FamilyDockClipper(this.scale);
  final double scale;

  @override
  Path getClip(Size size) {
    double x(double value) => value * size.width / 375;
    double y(double value) => value * scale;
    final bottom = size.height;
    return Path()
      ..moveTo(0, y(88))
      ..cubicTo(0, y(65.9), x(17.9), y(48), x(40), y(48))
      ..lineTo(x(116), y(48))
      ..cubicTo(x(133.7), y(48), x(147.5), y(64.4), x(160.1), y(76.7))
      ..cubicTo(x(167.3), y(83.7), x(177.2), y(88), x(188), y(88))
      ..cubicTo(x(198.8), y(88), x(208.7), y(83.7), x(215.9), y(76.7))
      ..cubicTo(x(228.5), y(64.4), x(242.3), y(48), x(260), y(48))
      ..lineTo(x(335), y(48))
      ..cubicTo(x(357.1), y(48), size.width, y(65.9), size.width, y(88))
      ..lineTo(size.width, bottom)
      ..lineTo(0, bottom)
      ..close();
  }

  @override
  bool shouldReclip(_FamilyDockClipper oldClipper) => scale != oldClipper.scale;
}

class _DockAddPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width / 2, 2),
      Offset(size.width / 2, size.height - 2),
      pen,
    );
    canvas.drawLine(
      Offset(2, size.height / 2),
      Offset(size.width - 2, size.height / 2),
      pen,
    );
  }

  @override
  bool shouldRepaint(_DockAddPainter oldDelegate) => false;
}
