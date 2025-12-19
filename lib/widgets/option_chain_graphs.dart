import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:finwiz/services/option_chain_service.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OptionChainGraphs extends StatefulWidget {
  final String symbol;
  const OptionChainGraphs({Key? key, required this.symbol}) : super(key: key);

  @override
  _OptionChainGraphsState createState() => _OptionChainGraphsState();
}

class _OptionChainGraphsState extends State<OptionChainGraphs> {
  // Graph 1 Data
  List<Map<String, dynamic>> _strikeData = [];
  double _spotPrice = 0.0;
  bool _isLoadingStrikes = true;

  String? _selectedExpiry;

  // Graph 2 Data
  List<FlSpot> _callHistory = [];
  List<FlSpot> _putHistory = [];
  bool _isLoadingHistory = false;
  DateTime _selectedHistoryDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    var current = DateTime.now();
    if (current.isAfter(DateTime(current.year, current.month, current.day, 17, 30))){
      var next = current.add(Duration(days: 1));
      _selectedExpiry = DateFormat('dd-MM-yyyy').format(next);
      _selectedHistoryDate = next;
    }else{
      _selectedExpiry = DateFormat('dd-MM-yyyy').format(current);
    }
    _initData();
  }

  void _initData() async {
    if (_selectedExpiry != null) {
      _fetchLiveStrikesAndSave();
      _fetchHistory();
    }
  }

  void _fetchLiveStrikesAndSave() async {
    if (_selectedExpiry == null) return;
    setState(() => _isLoadingStrikes = true);

    try {
      final response = await DeltaApi.get('/v2/tickers?contract_types=call_options,put_options&underlying_asset_symbols=${widget.symbol}&expiry_date=$_selectedExpiry');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tickers = data['result'] as List;

        if (tickers.isNotEmpty) {
          double currentSpot = double.tryParse(tickers.first['spot_price'].toString()) ?? 0.0;

          Map<double, Map<String, double>> strikes = {};
          double totalCall = 0;
          double totalPut = 0;

          for (var t in tickers) {
            double strike = double.parse(t['strike_price'].toString());
            double vol = double.tryParse(t['volume']?.toString() ?? t['volume_24h']?.toString() ?? '0') ?? 0.0;
            String type = t['contract_type'];

            if (type == 'call_options') totalCall += vol;
            else if (type == 'put_options') totalPut += vol;

            if (!strikes.containsKey(strike)) strikes[strike] = {'call': 0, 'put': 0};
            if (type == 'call_options') strikes[strike]!['call'] = vol;
            else if (type == 'put_options') strikes[strike]!['put'] = vol;
          }

          Map<String, Map<String, double>> expiryBreakdown = {};
          expiryBreakdown[_selectedExpiry!] = {
            'call': (Utils.round(2, num: totalCall, getAsDouble: true) as num).toDouble(),
            'put': (Utils.round(2, num: totalPut, getAsDouble: true) as num).toDouble()
          };

          await OptionChainService().saveSnapshot(widget.symbol, currentSpot, expiryBreakdown);

          _fetchHistory();

          List<double> sortedStrikes = strikes.keys.toList()..sort();
          int nearestIndex = 0;
          double minDiff = double.infinity;
          for (int i = 0; i < sortedStrikes.length; i++) {
            double diff = (sortedStrikes[i] - currentSpot).abs();
            if (diff < minDiff) {
              minDiff = diff;
              nearestIndex = i;
            }
          }

          int start = (nearestIndex - 10).clamp(0, sortedStrikes.length);
          int end = (nearestIndex + 11).clamp(0, sortedStrikes.length);

          List<Map<String, dynamic>> finalData = [];
          for (int i = start; i < end; i++) {
            double k = sortedStrikes[i];
            finalData.add({
              'strike': k,
              'call': Utils.round(2, num: strikes[k]!['call'] ?? 0, getAsDouble: true),
              'put': Utils.round(2, num: strikes[k]!['put'] ?? 0, getAsDouble: true),
            });
          }

          if (mounted) {
            setState(() {
              _spotPrice = currentSpot;
              _strikeData = finalData;
            });
          }
        } else {
          if (mounted) setState(() { _strikeData = []; });
        }
      }
    } catch (e) {
      print("Graph 1 Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingStrikes = false);
    }
  }

  void _fetchHistory() async {
    if (_selectedExpiry == null) return;
    setState(() => _isLoadingHistory = true);
    try {
      final rawDocs = await OptionChainService().fetchHistoryForDate(_selectedHistoryDate);
      _processHistoryData(rawDocs);
    } catch (e) {
      print("Graph 2 Error: $e");
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _processHistoryData(List<Map<String, dynamic>> docs) {
    if (docs.isEmpty) {
      setState(() { _callHistory = []; _putHistory = []; });
      return;
    }

    List<FlSpot> c = [];
    List<FlSpot> p = [];

    docs.sort((a, b) => (a['timestamp'] as Timestamp).compareTo(b['timestamp'] as Timestamp));

    int? lastTimestampMillis;

    for (var doc in docs) {
      Map<String, dynamic>? breakdown;
      try {
        breakdown = doc['expiry_breakdown'] != null
            ? Map<String, dynamic>.from(doc['expiry_breakdown'])
            : null;
      } catch(e) { breakdown = null; }

      double callVal = 0;
      double putVal = 0;

      if (breakdown != null && breakdown.containsKey(_selectedExpiry)) {
        final exData = breakdown[_selectedExpiry];
        callVal = (exData['call'] as num).toDouble();
        putVal = (exData['put'] as num).toDouble();
      } else if (breakdown == null && doc.containsKey('total_call_vol')) {
        callVal = (doc['total_call_vol'] as num).toDouble();
        putVal = (doc['total_put_vol'] as num).toDouble();
      } else {
        continue;
      }

      int currentTs = (doc['timestamp'] as Timestamp).millisecondsSinceEpoch;

      if (lastTimestampMillis == null || (currentTs - lastTimestampMillis) >= 900000) {
        double roundedCall = (Utils.round(2, num: callVal, getAsDouble: true) as num).toDouble();
        double roundedPut = (Utils.round(2, num: putVal, getAsDouble: true) as num).toDouble();

        c.add(FlSpot(currentTs.toDouble(), roundedCall));
        p.add(FlSpot(currentTs.toDouble(), roundedPut));
        lastTimestampMillis = currentTs;
      }
    }

    setState(() {
      _callHistory = c;
      _putHistory = p;
    });
  }

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedHistoryDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(3000),
    );
    if (picked != null && picked != _selectedHistoryDate) {
      setState(() {
        _selectedExpiry = DateFormat('dd-MM-yyyy').format(picked);
        _selectedHistoryDate = picked;
      });
      _fetchHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, color: Color(0xFF32F5A3), size: 20),
                label: Text(
                  DateFormat('dd MMM yyyy').format(_selectedHistoryDate),
                  style: const TextStyle(color: Color(0xFF32F5A3), fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Expanded(
            flex: 1,
            child: _isLoadingStrikes
                ? const Center(child: CircularProgressIndicator())
                : _buildBarChart(),
          ),

          const Divider(color: Colors.white24, height: 32),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Volume History (15m intervals)", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),

            ],
          ),

          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 16, height: 16, color: const Color(0xFF32F5A3)),
              const SizedBox(width: 8),
              const Text("Call Vol", style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 24),
              Container(width: 16, height: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              const Text("Put Vol", style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            flex: 1,
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _callHistory.isEmpty
                ? const Center(child: Text("No historical data available for selected date/expiry.", style: TextStyle(color: Colors.white38, fontSize: 16)))
                : _buildLineChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Strike Volume (Spot: $_spotPrice)", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54, size: 24),
              onPressed: _fetchLiveStrikesAndSave,
            )
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: BarChart(
            BarChartData(
              barGroups: _strikeData.asMap().entries.map((e) {
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    // Increased Width to 16
                    BarChartRodData(toY: (e.value['call'] as num).toDouble(), color: const Color(0xFF32F5A3), width: 16),
                    BarChartRodData(toY: (e.value['put'] as num).toDouble(), color: Colors.redAccent, width: 16),
                  ],
                );
              }).toList(),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      int idx = value.toInt();
                      if (idx >= 0 && idx < _strikeData.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _strikeData[idx]['strike'].toInt().toString(),
                            style: TextStyle(
                                color: _strikeData[idx]['strike'] == ((_spotPrice/100).round()*100) ? Colors.yellow : Colors.white54,
                                fontSize: 14 // Bigger Font
                            ),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 60)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return const FlLine(color: Colors.white10, strokeWidth: 1);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLineChart() {
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: _callHistory,
            color: const Color(0xFF32F5A3),
            isCurved: true,
            barWidth: 4, // Thicker Line
            dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 6, // Bigger Dot
                    color: const Color(0xFF32F5A3),
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                }
            ),
          ),
          LineChartBarData(
            spots: _putHistory,
            color: Colors.redAccent,
            isCurved: true,
            barWidth: 4, // Thicker Line
            dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 6, // Bigger Dot
                    color: Colors.redAccent,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                }
            ),
          ),
        ],
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 3600000,
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                      DateFormat('HH:mm').format(date),
                      style: const TextStyle(color: Colors.white54, fontSize: 14) // Bigger Font
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 60,
                // Since labels are auto-generated, increasing reservedSize helps fit larger text
              )
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (value) => const FlLine(color: Colors.white10, strokeWidth: 1),
          getDrawingVerticalLine: (value) => const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
      ),
    );
  }
}