import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../utils/db_utils.dart';

class OiChart extends StatelessWidget {
  final String underlyingAsset;
  final String expiryDate;

  const OiChart({
    Key? key,
    required this.underlyingAsset,
    required this.expiryDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final docId = '${underlyingAsset}_$expiryDate';

    return StreamBuilder<DocumentSnapshot>(
      stream: DBUtils.db.collection('option_chain_history').doc(docId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('No historical OI data available.', style: TextStyle(color: Colors.white70)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final historyData = snapshot.data!.get('history') as Map<String, dynamic>;
        final (chartData, sortedKeys) = _prepareChartData(historyData);
        final callSpots = chartData['call']!;
        final putSpots = chartData['put']!;
        final allSpots = [...callSpots, ...putSpots];

        if (callSpots.isEmpty) {
          return const Center(child: Text('No historical OI data available.', style: TextStyle(color: Colors.white70)));
        }

        return AspectRatio(
          aspectRatio: 1.7,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: _getInterval(_getMaxY(allSpots)),
                getDrawingHorizontalLine: (value) => const FlLine(color: Colors.white12, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: callSpots.length > 5 ? (callSpots.length / 5).ceilToDouble() : 1,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < sortedKeys.length) {
                        final key = sortedKeys[index];
                        // Assuming key is 'YYYY-MM-DD-HH-mm'
                        final parts = key.split('-');
                        if (parts.length >= 5) {
                          final time = '${parts[3]}:${parts[4]}';
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(time, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                          );
                        }
                      }
                      return const SizedBox();
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40, interval: _getInterval(_getMaxY(allSpots))),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (callSpots.length - 1).toDouble(),
              minY: 0,
              maxY: _getMaxY(allSpots),
              lineBarsData: [
                _buildLineChartBarData(callSpots, const Color(0xFF32F5A3)),
                _buildLineChartBarData(putSpots, Colors.redAccent),
              ],
            ),
          ),
        );
      },
    );
  }

  (Map<String, List<FlSpot>>, List<String>) _prepareChartData(Map<String, dynamic> historyData) {
    final sortedKeys = historyData.keys.toList()..sort();
    final List<FlSpot> callSpots = [];
    final List<FlSpot> putSpots = [];
    for (int i = 0; i < sortedKeys.length; i++) {
      final key = sortedKeys[i];
      final data = historyData[key] as Map<String, dynamic>;

      double totalCallOi = 0;
      double totalPutOi = 0;

      data.forEach((strikeKey, oi) {
        double oiDouble = 0.0;
        if (oi is String) {
          oiDouble = double.tryParse(oi) ?? 0.0;
        } else if (oi is num) {
          oiDouble = oi.toDouble();
        }

        if (strikeKey.endsWith('call_oi')) {
          totalCallOi += oiDouble;
        } else if (strikeKey.endsWith('put_oi')) {
          totalPutOi += oiDouble;
        }
      });

      callSpots.add(FlSpot(i.toDouble(), totalCallOi));
      putSpots.add(FlSpot(i.toDouble(), totalPutOi));
    }
    return ({'call': callSpots, 'put': putSpots}, sortedKeys);
  }

  LineChartBarData _buildLineChartBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: true, color: color.withOpacity(0.3)),
    );
  }

  double _getMaxY(List<FlSpot> spots) {
    double maxY = 0.0;
    if (spots.isEmpty) return 100.0;
    for (var spot in spots) {
      if (spot.y > maxY) maxY = spot.y;
    }
    return maxY * 1.2;
  }

  double _getInterval(double maxY) {
    if (maxY <= 0) return 10.0;
    return (maxY / 5).ceilToDouble();
  }
}
