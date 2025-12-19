import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:intl/intl.dart';

class OptionChainService {
  static final OptionChainService _instance = OptionChainService._internal();
  factory OptionChainService() => _instance;
  OptionChainService._internal();

  Timer? _syncTimer;
  final String _collectionName = 'OPTION_CHAIN';

  void startBackgroundSync(String symbol) {
    _syncTimer?.cancel();
    print("Starting background sync for $symbol...");
    _fetchAndSaveData(symbol);
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _fetchAndSaveData(symbol);
    });
  }

  void stopBackgroundSync() {
    _syncTimer?.cancel();
  }

  /// Saves detailed snapshot with correct rounding
  Future<void> saveSnapshot(String symbol, double spot, Map<String, Map<String, double>> expiryVolumes) async {
    String expiry;
    var current = DateTime.now();
    if (current.isAfter(DateTime(current.year, current.month, current.day, 17, 30))){
      var next = current.add(Duration(days: 1));
      expiry = DateFormat('dd-MM-yy').format(next);
    }else{
      expiry = DateFormat('dd-MM-yy').format(current);
    }

    double globalCall = 0;
    double globalPut = 0;

    // Round breakdown values individually before saving
    Map<String, Map<String, double>> roundedBreakdown = {};

    expiryVolumes.forEach((expiry, vols) {
      // FIX: Use correct Utils.round signature
      double c = (Utils.round(2, num: vols['call'] ?? 0, getAsDouble: true) as num).toDouble();
      double p = (Utils.round(2, num: vols['put'] ?? 0, getAsDouble: true) as num).toDouble();

      roundedBreakdown[expiry] = {'call': c, 'put': p};

      globalCall += c;
      globalPut += p;
    });

    try {
      await FirebaseFirestore.instance.collection(_collectionName).doc().set({
        'symbol': symbol,
        'timestamp': DBUtils.getTimestamp(expiry),
        'spot_price': spot,
        // FIX: Use correct Utils.round signature for totals
        'total_call_vol': Utils.round(2, num: globalCall, getAsDouble: true),
        'total_put_vol': Utils.round(2, num: globalPut, getAsDouble: true),
        'expiry_breakdown': roundedBreakdown,
      });
      print("Saved snapshot: ${expiry}");
    } catch (e) {
      print("Error saving snapshot: $e");
    }
  }

  Future<void> _fetchAndSaveData(String symbol) async {
    try {
      final response = await DeltaApi.get('/v2/tickers?contract_types=call_options,put_options&underlying_asset_symbols=$symbol');
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final tickers = data['result'] as List;
      if (tickers.isEmpty) return;

      double spotPrice = double.tryParse(tickers.first['spot_price'].toString()) ?? 0.0;

      Map<String, Map<String, double>> expiryVolumes = {};

      for (var t in tickers) {
        final vol = double.tryParse(t['volume']?.toString() ?? t['volume_24h']?.toString() ?? '0') ?? 0.0;
        final expiry = t['expiry_date'] ?? 'unknown';

        if (!expiryVolumes.containsKey(expiry)) {
          expiryVolumes[expiry] = {'call': 0.0, 'put': 0.0};
        }

        if (t['contract_type'] == 'call_options') {
          expiryVolumes[expiry]!['call'] = expiryVolumes[expiry]!['call']! + vol;
        } else {
          expiryVolumes[expiry]!['put'] = expiryVolumes[expiry]!['put']! + vol;
        }
      }

      await saveSnapshot(symbol, spotPrice, expiryVolumes);

    } catch (e) {
      print("Error in background sync: $e");
    }
  }

  Future<List<Map<String, dynamic>>> fetchHistoryForDate(DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day, 0, 0, 0);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionName)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
        .orderBy('timestamp')
        .get();

    return snapshot.docs.map((d) => d.data()).toList();
  }
}