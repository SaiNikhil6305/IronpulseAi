import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/units.dart';

/// Line chart over dates; only plots real recorded points.
class DateLineChart extends StatelessWidget {
  const DateLineChart({super.key, required this.points, this.unit = '', this.height = 200, this.decimals = 1});
  final List<(DateTime, double)> points;
  final String unit;
  final double height;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(points.isEmpty ? 'No data in this range yet.' : 'Record at least two entries to see a trend.',
              style: const TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final sorted = [...points]..sort((a, b) => a.$1.compareTo(b.$1));
    final origin = sorted.first.$1;
    double x(DateTime d) => d.difference(origin).inHours / 24.0;
    final ys = sorted.map((p) => p.$2);
    final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
    final pad = (maxY - minY).abs() < 1e-6 ? (maxY.abs() * 0.05 + 1) : (maxY - minY) * 0.15;
    final spanX = x(sorted.last.$1);
    final fmt = spanX > 120 ? DateFormat('MMM') : DateFormat('d MMM');
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        minX: 0,
        maxX: spanX == 0 ? 1 : spanX,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(Units.trimNum(v, maxDecimals: 0), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: spanX <= 0 ? 1 : math.max(1, spanX / 4),
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(fmt.format(origin.add(Duration(hours: (v * 24).round()))),
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceHigh,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${Units.trimNum(s.y, maxDecimals: decimals)} $unit\n'
                  '${DateFormat('d MMM yyyy').format(origin.add(Duration(hours: (s.x * 24).round())))}',
                  const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12),
                )
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (final p in sorted) FlSpot(x(p.$1), p.$2)],
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.accent,
            barWidth: 3,
            dotData: FlDotData(show: sorted.length <= 30),
            belowBarData: BarAreaData(show: true, color: AppColors.accent.withValues(alpha: 0.12)),
          ),
        ],
      )),
    );
  }
}

/// Simple labelled bar chart (e.g. workouts per week).
class LabeledBarChart extends StatelessWidget {
  const LabeledBarChart({super.key, required this.bars, this.height = 180, this.target});
  final List<(String, double)> bars;
  final double height;
  final double? target;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty || bars.every((b) => b.$2 == 0)) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('No data in this range yet.', style: TextStyle(color: AppColors.textMuted))),
      );
    }
    final maxY = math.max(bars.map((b) => b.$2).reduce(math.max), target ?? 0) * 1.2;
    final every = (bars.length / 8).ceil();
    return SizedBox(
      height: height,
      child: BarChart(BarChartData(
        maxY: maxY == 0 ? 1 : maxY,
        gridData: FlGridData(
            drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        extraLinesData: target == null
            ? null
            : ExtraLinesData(horizontalLines: [
                HorizontalLine(y: target!, color: AppColors.success.withValues(alpha: 0.7), strokeWidth: 1.5, dashArray: [6, 4]),
              ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(Units.trimNum(v, maxDecimals: 0), style: const TextStyle(fontSize: 10, color: AppColors.textMuted))),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= bars.length || i % every != 0) return const SizedBox.shrink();
                return SideTitleWidget(
                    meta: meta, child: Text(bars[i].$1, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)));
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceHigh,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${bars[group.x].$1}: ${Units.trimNum(rod.toY, maxDecimals: 1)}',
              const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < bars.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: bars[i].$2,
                color: AppColors.accent,
                width: math.max(4, math.min(18, 220 / bars.length)),
                borderRadius: BorderRadius.circular(4),
              ),
            ]),
        ],
      )),
    );
  }
}
