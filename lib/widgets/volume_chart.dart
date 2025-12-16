import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:finwiz/utils/db_utils.dart';

class VolumeChart extends StatelessWidget {
  final String underlyingAsset;
  final String expiryDate;

  const VolumeChart({
    Key? key,
    required this.underlyingAsset,
    required this.expiryDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final docId = '${underlyingAsset}_$expiryDate';

    return StreamBuilder<DocumentSnapshot>(
      stream: DBUtils.db.collection('option_chain').doc(docId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('No volume data available.', style: TextStyle(color: Colors.white70)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final (totalCallVolume, totalPutVolume) = _calculateVolumes(data);

        return AspectRatio(
          aspectRatio: 1.7,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (totalCallVolume > totalPutVolume ? totalCallVolume : totalPutVolume) * 1.2,
              barTouchData: BarTouchData(enabled: false),
              titlesData: const FlTitlesData(
                show: true,
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: _getTitles,
                    reservedSize: 38,
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                _makeGroupData(0, totalCallVolume, barColor: const Color(0xFF32F5A3)),
                _makeGroupData(1, totalPutVolume, barColor: Colors.redAccent),
              ],
              gridData: const FlGridData(show: false),
            ),
          ),
        );
      },
    );
  }

  (double, double) _calculateVolumes(Map<String, dynamic> data) {
    double totalCallVolume = 0;
    double totalPutVolume = 0;

    data.forEach((key, value) {
      if (key.endsWith('_call_volume')) {
        totalCallVolume += (value as num).toDouble();
      } else if (key.endsWith('_put_volume')) {
        totalPutVolume += (value as num).toDouble();
      }
    });

    return (totalCallVolume, totalPutVolume);
  }

  BarChartGroupData _makeGroupData(int x, double y, {Color barColor = Colors.white}) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: barColor,
          width: 22,
          borderRadius: BorderRadius.zero,
        ),
      ],
    );
  }

  static Widget _getTitles(double value, TitleMeta meta) {
    const style = TextStyle(
      color: Colors.white70,
      fontWeight: FontWeight.bold,
      fontSize: 14,
    );
    String text;
    switch (value.toInt()) {
      case 0:
        text = 'Call';
        break;
      case 1:
        text = 'Put';
        break;
      default:
        text = '';
        break;
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 16,
      child: Text(text, style: style),
    );
  }
}
