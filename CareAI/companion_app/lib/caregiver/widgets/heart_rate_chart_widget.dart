import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/models.dart';
import '../../theme/careai_theme.dart';

/// Widget trực quan hóa chuỗi nhịp tim trong cửa sổ T - 15 phút ... T + 15 phút
/// quanh mốc xảy ra sự cố (UC-08 & 2.5 Lịch sử và dấu vết pháp y)
class HeartRateChartWidget extends StatelessWidget {
  final IncidentHeartRateWindow? window;
  final DateTime incidentTriggeredAt;
  final double? snapshotHeartRate;

  const HeartRateChartWidget({
    super.key,
    required this.window,
    required this.incidentTriggeredAt,
    this.snapshotHeartRate,
  });

  @override
  Widget build(BuildContext context) {
    final samples = window?.samples ?? [];

    if (samples.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: const Color(0xFFFAF7F2),
        elevation: 0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEFE8DF)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: Color(0xFFF2ECE4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined,
                  color: Color(0xFF8C7A6B),
                  size: 36,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Chưa Có Chuỗi Nhịp Tim ±15 Phút',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF5C493B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Không có mẫu đo nhịp tim nào được ghi nhận từ thiết bị đeo trong cửa sổ '
                '${DateFormat('HH:mm').format(incidentTriggeredAt.subtract(const Duration(minutes: 15)).toLocal())} — '
                '${DateFormat('HH:mm').format(incidentTriggeredAt.add(const Duration(minutes: 15)).toLocal())}.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7D7168),
                  height: 1.4,
                ),
              ),
              if (snapshotHeartRate != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4E4),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFD5E2BE)),
                  ),
                  child: Text(
                    'Nhịp tim tức thời tại mốc T: ${snapshotHeartRate!.toStringAsFixed(0)} bpm',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CareAiColors.greenInk,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Tính toán thống kê nhịp tim
    final bpms = samples.map((s) => s.bpm).toList();
    final minBpm = bpms.reduce(math.min);
    final maxBpm = bpms.reduce(math.max);
    final avgBpm = bpms.reduce((a, b) => a + b) / bpms.length;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
    final countBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CareAiColors.greenSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${samples.length} mẫu',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: CareAiColors.greenInk,
        ),
      ),
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.show_chart,
                  color: Color(0xFF4A3020),
                  size: 22,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Biểu Đồ Nhịp Tim (T - 15 đến T + 15 phút)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF231811),
                    ),
                  ),
                ),
                if (!largeText) countBadge,
              ],
            ),
            if (largeText) ...[const SizedBox(height: 8), countBadge],
            const SizedBox(height: 12),

            // Thẻ tóm tắt chỉ số nhanh
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF7F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEFE8DF)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _statItem(
                    'Thấp nhất',
                    '${minBpm.toStringAsFixed(0)} bpm',
                    minBpm <= 35 ? Colors.red : const Color(0xFF231811),
                  ),
                  _statItem(
                    'Trung bình',
                    '${avgBpm.toStringAsFixed(0)} bpm',
                    const Color(0xFF231811),
                  ),
                  _statItem(
                    'Cao nhất',
                    '${maxBpm.toStringAsFixed(0)} bpm',
                    maxBpm >= 180 ? Colors.red : const Color(0xFF231811),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Vùng vẽ biểu đồ nhịp tim tùy chỉnh CustomPainter
            SizedBox(
              height: 220,
              width: double.infinity,
              child: CustomPaint(
                painter: _HeartRatePainter(
                  samples: samples,
                  incidentTime: incidentTriggeredAt,
                  windowStart:
                      window?.windowStart ??
                      incidentTriggeredAt.subtract(const Duration(minutes: 15)),
                  windowEnd:
                      window?.windowEnd ??
                      incidentTriggeredAt.add(const Duration(minutes: 15)),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Chú giải biểu đồ
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _legendItem(
                  const Color(0xFFDC2626),
                  'Mốc sự cố (T)',
                  isDashed: false,
                  isVertical: true,
                ),
                _legendItem(
                  Colors.red.shade400,
                  'Ngưỡng nguy kịch (≥180 hoặc ≤35)',
                  isDashed: true,
                ),
                _legendItem(
                  Colors.green.shade600,
                  'Nhịp an toàn (60-100)',
                  isDashed: false,
                ),
                _legendItem(
                  const Color(0xFF4A3020),
                  'Nhịp tim đo được',
                  isDashed: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF7D7168)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _legendItem(
    Color color,
    String text, {
    bool isDashed = false,
    bool isVertical = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVertical)
          Container(width: 3, height: 12, color: color)
        else if (isDashed)
          Row(
            children: [
              Container(width: 4, height: 2, color: color),
              const SizedBox(width: 2),
              Container(width: 4, height: 2, color: color),
              const SizedBox(width: 2),
              Container(width: 4, height: 2, color: color),
            ],
          )
        else
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: CareAiColors.secondary),
          ),
        ),
      ],
    );
  }
}

class _HeartRatePainter extends CustomPainter {
  final List<HeartRateSample> samples;
  final DateTime incidentTime;
  final DateTime windowStart;
  final DateTime windowEnd;

  _HeartRatePainter({
    required this.samples,
    required this.incidentTime,
    required this.windowStart,
    required this.windowEnd,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftMargin = 38.0;
    const rightMargin = 12.0;
    const topMargin = 12.0;
    const bottomMargin = 26.0;

    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;

    if (plotWidth <= 0 || plotHeight <= 0) return;

    // Giới hạn trục Y (tối thiểu 30, tối đa 200, co giãn nếu dữ liệu vượt trần)
    double minY = 30;
    double maxY = 200;
    for (final s in samples) {
      if (s.bpm < minY) minY = (s.bpm / 10).floor() * 10;
      if (s.bpm > maxY) maxY = (s.bpm / 10).ceil() * 10;
    }

    final totalSeconds = windowEnd.difference(windowStart).inSeconds;
    final safeTotalSeconds = totalSeconds > 0 ? totalSeconds : 1800; // 30 phút

    double timeToX(DateTime t) {
      final elapsed = t.difference(windowStart).inSeconds;
      final ratio = (elapsed / safeTotalSeconds).clamp(0.0, 1.0);
      return leftMargin + ratio * plotWidth;
    }

    double bpmToY(double bpm) {
      final ratio = ((bpm - minY) / (maxY - minY)).clamp(0.0, 1.0);
      return topMargin + (1.0 - ratio) * plotHeight;
    }

    final gridPaint = Paint()
      ..color = const Color(0xFFF2ECE4)
      ..strokeWidth = 1.0;

    final textStyle = const TextStyle(
      fontFamily: 'BeVietnamPro',
      color: Color(0xFF8C7A6B),
      fontSize: 10,
    );
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // 1. Vẽ dải an toàn nhịp tim bình thường (60-100 bpm)
    final safeTop = bpmToY(100);
    final safeBottom = bpmToY(60);
    final safeZonePaint = Paint()..color = const Color(0xFFF0FDF4);
    canvas.drawRect(
      Rect.fromLTRB(leftMargin, safeTop, leftMargin + plotWidth, safeBottom),
      safeZonePaint,
    );

    // 2. Vẽ lưới Y (mỗi 30-40 bpm)
    final yTicks = [40.0, 60.0, 100.0, 140.0, 180.0];
    for (final tick in yTicks) {
      if (tick < minY || tick > maxY) continue;
      final y = bpmToY(tick);
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(leftMargin + plotWidth, y),
        gridPaint,
      );

      textPainter.text = TextSpan(text: '${tick.toInt()}', style: textStyle);
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(leftMargin - textPainter.width - 6, y - textPainter.height / 2),
      );
    }

    // 3. Vẽ đường ngưỡng nguy kịch 180 bpm và 35 bpm (Dashed red line)
    _drawDashedLine(
      canvas,
      Offset(leftMargin, bpmToY(180)),
      Offset(leftMargin + plotWidth, bpmToY(180)),
      Colors.red.shade300,
      1.5,
      [4, 4],
    );
    _drawDashedLine(
      canvas,
      Offset(leftMargin, bpmToY(35)),
      Offset(leftMargin + plotWidth, bpmToY(35)),
      Colors.red.shade300,
      1.5,
      [4, 4],
    );

    // 4. Vẽ mốc T (Thời điểm kích hoạt sự cố)
    final incidentX = timeToX(incidentTime);
    final incidentLinePaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.0;
    canvas.drawLine(
      Offset(incidentX, topMargin),
      Offset(incidentX, topMargin + plotHeight),
      incidentLinePaint,
    );

    // Nhãn chữ mốc T trên đỉnh
    textPainter.text = const TextSpan(
      text: '⚡ T',
      style: TextStyle(
        fontFamily: 'BeVietnamPro',
        color: Color(0xFFDC2626),
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        incidentX - textPainter.width / 2,
        topMargin - textPainter.height - 1,
      ),
    );

    // 5. Vẽ lưới trục X (Mốc T-15m, T-10m, T-5m, T, T+5m, T+10m, T+15m)
    final xMinuteOffsets = [-15, -10, -5, 0, 5, 10, 15];
    for (final m in xMinuteOffsets) {
      final markerTime = incidentTime.add(Duration(minutes: m));
      final x = timeToX(markerTime);
      if (x < leftMargin - 1 || x > leftMargin + plotWidth + 1) continue;

      if (m != 0) {
        canvas.drawLine(
          Offset(x, topMargin),
          Offset(x, topMargin + plotHeight),
          gridPaint,
        );
      }

      final label = m == 0 ? 'T' : (m > 0 ? '+$m\'' : '$m\'');
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'BeVietnamPro',
          color: m == 0 ? const Color(0xFFDC2626) : const Color(0xFF7D7168),
          fontSize: 10,
          fontWeight: m == 0 ? FontWeight.bold : FontWeight.normal,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, topMargin + plotHeight + 5),
      );
    }

    // 6. Sắp xếp mẫu đo theo thời gian
    final sorted = List<HeartRateSample>.from(samples)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    if (sorted.length == 1) {
      final x = timeToX(sorted.first.timestamp);
      final y = bpmToY(sorted.first.bpm);
      final pointPaint = Paint()
        ..color = const Color(0xFF4A3020)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
      return;
    }

    // 7. Vẽ đường nối các mẫu và vùng tô màu Gradient
    final path = Path();
    final fillPath = Path();

    final firstX = timeToX(sorted.first.timestamp);
    final firstY = bpmToY(sorted.first.bpm);

    path.moveTo(firstX, firstY);
    fillPath.moveTo(firstX, topMargin + plotHeight);
    fillPath.lineTo(firstX, firstY);

    for (int i = 1; i < sorted.length; i++) {
      final currX = timeToX(sorted[i].timestamp);
      final currY = bpmToY(sorted[i].bpm);
      path.lineTo(currX, currY);
      fillPath.lineTo(currX, currY);
    }

    final lastX = timeToX(sorted.last.timestamp);
    fillPath.lineTo(lastX, topMargin + plotHeight);
    fillPath.close();

    // Tô nền gradient
    final fillGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        const Color(0xFF4A3020).withValues(alpha: 0.25),
        const Color(0xFF4A3020).withValues(alpha: 0.0),
      ],
    );
    final fillPaint = Paint()
      ..shader = fillGradient.createShader(
        Rect.fromLTRB(
          leftMargin,
          topMargin,
          leftMargin + plotWidth,
          topMargin + plotHeight,
        ),
      );
    canvas.drawPath(fillPath, fillPaint);

    // Vẽ đường chính
    final linePaint = Paint()
      ..color = const Color(0xFF4A3020)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Vẽ các chấm điểm đo (Dot markers)
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final dotBorderPaint = Paint()
      ..color = const Color(0xFF4A3020)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final alertDotBorderPaint = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final s in sorted) {
      final x = timeToX(s.timestamp);
      final y = bpmToY(s.bpm);
      final isCritical = s.bpm >= 180 || s.bpm <= 35;

      canvas.drawCircle(Offset(x, y), isCritical ? 5.0 : 3.5, dotPaint);
      canvas.drawCircle(
        Offset(x, y),
        isCritical ? 5.0 : 3.5,
        isCritical ? alertDotBorderPaint : dotBorderPaint,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Color color,
    double width,
    List<double> dashPattern,
  ) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double currentDist = 0.0;
    int patternIndex = 0;

    while (currentDist < distance) {
      final dashLength = dashPattern[patternIndex % dashPattern.length];
      final nextDist = math.min(currentDist + dashLength, distance);

      if (patternIndex % 2 == 0) {
        canvas.drawLine(
          Offset(p1.dx + unitX * currentDist, p1.dy + unitY * currentDist),
          Offset(p1.dx + unitX * nextDist, p1.dy + unitY * nextDist),
          paint,
        );
      }

      currentDist = nextDist;
      patternIndex++;
    }
  }

  @override
  bool shouldRepaint(covariant _HeartRatePainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.incidentTime != incidentTime ||
        oldDelegate.windowStart != windowStart ||
        oldDelegate.windowEnd != windowEnd;
  }
}
