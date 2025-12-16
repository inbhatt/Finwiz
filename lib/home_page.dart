import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finwiz/login_page.dart';
import 'package:finwiz/place_order_page.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:finwiz/widgets/edit_order_dialog.dart';
import 'package:finwiz/widgets/oi_chart.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:finwiz/widgets/volume_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

enum _BracketLeg { takeProfit, stopLoss }

class _HomePageState extends State<HomePage> {
  bool _isBitcoinCardHovered = false;
  int _hoveredPositionIndex = -1;
  List<Map<String, dynamic>> _stocks = [];
  List<Map<String, dynamic>> _positions = [];
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  late final WebSocketChannel _channel;
  bool _isWebSocketAuthenticated = false;

  Map<String, dynamic>? _selectedStock;
  List<Map<String, dynamic>> _optionChainData = [];
  bool _isOptionChainLoading = false;
  String? _selectedExpiryDate;
  double _spotPrice = 0.0;
  Timer? _optionChainRefreshTimer;

  @override
  void initState() {
    super.initState();
    _channel = WebSocketChannel.connect(
      Uri.parse('wss://socket.india.delta.exchange'),
    );

    _authenticateAndSubscribe();
    _fetchStocks();
  }

  void _authenticateAndSubscribe() {
    try {
      final signature = DeltaApi.getWebSocketAuthSignature();
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();

      _channel.sink.add(jsonEncode({
        'type': 'key-auth',
        'payload': {
          'api-key': DeltaApi.apiKey,
          'signature': signature,
          'timestamp': timestamp,
        }
      }));

      _channel.stream.listen(
        (message) {
          if (!mounted) return;
          try {
            final decodedMessage = jsonDecode(message);

            if (decodedMessage['type'] == 'key-auth') {
              if (decodedMessage['success'] == true) {
                setState(() {
                  _isWebSocketAuthenticated = true;
                });
                _subscribeToChannels();
              } else {
                ShowDialogs.showDialog(
                    title: 'WebSocket Auth Error',
                    msg: 'Authentication failed: ${decodedMessage['message'] ?? 'Unknown authentication error'}');
              }
            }

            if (_isWebSocketAuthenticated) {
              if (decodedMessage['type'] == 'v2/ticker') {
                _handleTickerUpdate(decodedMessage);
              } else if (decodedMessage['type'] == 'positions') {
                _handlePositionUpdate(decodedMessage);
              } else if (decodedMessage['type'] == 'orders') {
                _handleOrderUpdate(decodedMessage);
              }
            }
          } on FormatException catch (e) {
            ShowDialogs.showDialog(title: 'WebSocket Data Error', msg: 'Failed to parse WebSocket message (invalid JSON): $e');
          } catch (e) {
            ShowDialogs.showDialog(title: 'WebSocket Processing Error', msg: 'An error occurred while processing WebSocket message: $e');
          }
        },
        onError: (error) {
          if (!mounted) return;
          ShowDialogs.showDialog(title: 'WebSocket Connection Error', msg: 'WebSocket connection error: $error');
        },
        onDone: () {
          if (!mounted) return;
        },
      );
    } catch (e) {
      if (!mounted) return;
      ShowDialogs.showDialog(title: 'WebSocket Initialization Error', msg: 'Failed to initialize WebSocket: $e');
    }
  }

  void _handleTickerUpdate(Map<String, dynamic> data) {
    final productId = data['product_id'];
    final stockIndex = _stocks.indexWhere((s) => s['code'].toString() == productId.toString());

    if (stockIndex != -1) {
      setState(() {
        _stocks[stockIndex]['ltp'] = data['close'];
        _stocks[stockIndex]['open'] = data['open'];
        _stocks[stockIndex]['high'] = data['high'];
        _stocks[stockIndex]['low'] = data['low'];
        _stocks[stockIndex]['close'] = data['close'];
      });
    }
  }

  void _handlePositionUpdate(Map<String, dynamic> data) {
    setState(() {
      if (data['action'] == 'snapshot') {
        _positions = List<Map<String, dynamic>>.from(data['result']);
      } else {
        final symbol = data['symbol'];
        final index = _positions.indexWhere((p) => p['symbol'] == symbol);

        if (data['action'] == 'create') {
          _positions.add(data);
        } else if (data['action'] == 'update' && index != -1) {
          _positions[index] = data;
        } else if (data['action'] == 'delete' && index != -1) {
          _positions.removeAt(index);
        }
      }
    });
  }

  void _handleOrderUpdate(Map<String, dynamic> data) {
    setState(() {
      if (data['action'] == 'snapshot') {
        _orders = List<Map<String, dynamic>>.from(data['result']);
      } else {
        final clientOrderId = data['client_order_id'];
        final index = _orders.indexWhere((o) => o['client_order_id'] == clientOrderId);

        if (data['action'] == 'create') {
          _orders.add(data);
        } else if (data['action'] == 'update' && index != -1) {
          _orders[index] = data;
        } else if (data['action'] == 'delete' && index != -1) {
          _orders.removeAt(index);
        }
      }
    });
  }

  Future<void> _fetchStocks() async {
    try {
      final snapshot = await DBUtils.getData(
        collection: "STOCKS",
        condition: "PLATFORM=DELTA",
        showProgress: false,
      );

      if (mounted) {
        if (snapshot.querySnapshot != null && snapshot.querySnapshot!.docs.isNotEmpty) {
          final fetchedStocks = snapshot.querySnapshot!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'name': doc.id,
              'short_name': data['NAME'],
              'code': data['CODE'],
              'ltp': 'N/A',
              'open': 'N/A',
              'high': 'N/A',
              'low': 'N/A',
              'close': 'N/A',
            };
          });

          setState(() {
            _stocks = fetchedStocks.toList();
            _isLoading = false;
          });

          if (_isWebSocketAuthenticated) {
            _subscribeToChannels();
          }
        } else {
          setState(() {
            _isLoading = false;
          });
          ShowDialogs.showDialog(title: 'Info', msg: 'No stocks found in Firestore.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ShowDialogs.showDialog(title: 'Error', msg: 'Failed to fetch stocks from Firestore: $e');
      }
    }
  }

  void _subscribeToChannels() {
    final symbols = _stocks.map((s) => s['name']).toList();
    _channel.sink.add(jsonEncode({
      'type': 'subscribe',
      'payload': {
        'channels': [
          {
            'name': 'v2/ticker',
            'symbols': symbols,
          },
          {
            'name': 'positions',
            'symbols': ['all'],
          },
          {
            'name': 'orders',
            'symbols': ['all'],
          }
        ]
      }
    }));
  }

  @override
  void dispose() {
    _channel.sink.close();
    _optionChainRefreshTimer?.cancel();
    super.dispose();
  }

  void _showOrderDialog(Map<String, dynamic> stock, bool isBuy) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return PlaceOrderPage(stock: stock, isBuy: isBuy);
      },
    );
  }

  Future<void> _updateOrder(Map<String, dynamic> position, Map<String, dynamic> order, String triggerPrice, String limitPrice, String orderType) async {
    ShowDialogs.showProgressDialog();

    try {
      http.Response response;
      final doc = order.isNotEmpty ? DBUtils.userDoc.reference.collection("ORDERS").doc(order['client_order_id']) : DBUtils.userDoc.reference.collection("ORDERS").doc();

      if (order.isNotEmpty) {
        // Update existing stop loss order
        final payload = {
          'id': order['id'],
          'product_id': order['product_id'],
          'product_symbol': order['product_symbol'],
          'size': order['size'],
          'stop_price': triggerPrice,
          'limit_price': limitPrice,
        };
        response = await DeltaApi.put('/v2/orders', payload);
      } else {
        // Create new stop loss/take profit order
        final isLong = position['size'] > 0;
        final payload = {
          'product_id': position['product_id'],
          'product_symbol': position['product_symbol'],
          'side': isLong ? 'sell' : 'buy',
          'order_type': 'limit_order',
          'size': position['size'].abs(),
          'stop_order_type': orderType,
          'stop_price': triggerPrice,
          'limit_price': limitPrice,
          'reduce_only': true,
          'client_order_id': doc.id,
        };
        response = await DeltaApi.post('/v2/orders', payload);
      }

      ShowDialogs.dismissProgressDialog();
      // Attempt to decode JSON, handle potential errors
      dynamic responseBody;
      try {
        responseBody = jsonDecode(response.body);
      } on FormatException {
        ShowDialogs.showDialog(title: 'Order Error', msg: 'Failed to parse order response (invalid JSON).');
        return;
      }

      if (response.statusCode == 200) {
        await doc.set(responseBody, SetOptions(merge: true));
        ShowDialogs.showDialog(title: 'Success', msg: 'Order updated successfully.', type: DialogType.SUCCESS);
      } else {
        ShowDialogs.showDialog(title: 'Order Error', msg: responseBody['message'] ?? 'Failed to update order: HTTP ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Network Error', msg: 'Failed to connect to Delta Exchange: ${e.message}');
    } catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Order Error', msg: 'An unexpected error occurred while updating order: $e');
    }
  }

  Future<void> _updateBracketLeg(Map<String, dynamic> bracketOrder, _BracketLeg leg, String triggerPrice, String limitPrice) async {
    if (triggerPrice.trim().isEmpty) {
      ShowDialogs.showDialog(title: 'Invalid Input', msg: 'Trigger price is required for bracket orders.');
      return;
    }

    final orderId = bracketOrder['id'] ?? bracketOrder['order_id'];
    if (orderId == null) {
      ShowDialogs.showDialog(title: 'Bracket Error', msg: 'Unable to identify bracket order.');
      return;
    }

    ShowDialogs.showProgressDialog();

    try {
      final payload = <String, dynamic>{
        'id': orderId,
        'product_id': bracketOrder['product_id'],
        'product_symbol': bracketOrder['product_symbol'],
        'bracket_stop_trigger_method': bracketOrder['bracket_stop_trigger_method'] ?? 'last_traded_price',
      };

      if (leg == _BracketLeg.takeProfit) {
        payload['bracket_take_profit_price'] = triggerPrice.trim();
        final effectiveLimit = limitPrice.trim().isNotEmpty
            ? limitPrice.trim()
            : (bracketOrder['bracket_take_profit_limit_price']?.toString() ?? '');
        if (effectiveLimit.isNotEmpty) {
          payload['bracket_take_profit_limit_price'] = effectiveLimit;
        }
      } else {
        payload['bracket_stop_loss_price'] = triggerPrice.trim();
        final effectiveLimit = limitPrice.trim().isNotEmpty
            ? limitPrice.trim()
            : (bracketOrder['bracket_stop_loss_limit_price']?.toString() ?? '');
        if (effectiveLimit.isNotEmpty) {
          payload['bracket_stop_loss_limit_price'] = effectiveLimit;
        }
      }

      final response = await DeltaApi.put('/v2/orders/bracket', payload);
      dynamic responseBody;
      try {
        responseBody = jsonDecode(response.body);
      } on FormatException {
        ShowDialogs.dismissProgressDialog();
        ShowDialogs.showDialog(title: 'Bracket Error', msg: 'Failed to parse bracket update response.');
        return;
      }

      ShowDialogs.dismissProgressDialog();

      if (response.statusCode == 200) {
        ShowDialogs.showDialog(title: 'Success', msg: 'Bracket order updated successfully.', type: DialogType.SUCCESS);
      } else {
        ShowDialogs.showDialog(title: 'Bracket Error', msg: responseBody['message'] ?? 'Failed to update bracket order.');
      }
    } catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Bracket Error', msg: 'An unexpected error occurred while updating bracket order.');
    }
  }

  Future<void> _updateTrailAmount(Map<String, dynamic> position, Map<String, dynamic> order, String newTrailAmount) async {
    ShowDialogs.showProgressDialog();

    try {
      http.Response? response;
      final doc = order.isNotEmpty ? DBUtils.userDoc.reference.collection("ORDERS").doc(order['client_order_id']) : DBUtils.userDoc.reference.collection("ORDERS").doc();

      bool place = true;
      if (order.isNotEmpty) {
        Map<String, dynamic> payload = {};
        if (num.parse(order['trail_amount']?.toString() ?? '0') > 0){
          payload = {
            'id': order['id'],
            'product_id': order['product_id'],
            'product_symbol': order['product_symbol'],
            'size': order['size'],
            'trail_amount': newTrailAmount,
          };
          response = await DeltaApi.put('/v2/orders', payload);
          place = false;
        }else{
          payload = {
            'id': order['id'],
            'client_order_id': order['client_order_id'],
            'product_id': order['product_id'],
          };
          response = await DeltaApi.delete('/v2/orders', payload);
        }
      }
      if (place){
        final isLong = position['size'] > 0;
        final payload = {
          'product_id': position['product_id'],
          'product_symbol': position['product_symbol'],
          'side': isLong ? 'sell' : 'buy',
          'order_type': 'market_order',
          'stop_order_type': 'stop_loss_order',
          'size': position['size'].abs(),
          'trail_amount': newTrailAmount,
          'client_order_id': doc.id,
          'reduce_only': true,
        };
        response = await DeltaApi.post('/v2/orders', payload);
      }

      ShowDialogs.dismissProgressDialog();
      // Attempt to decode JSON, handle potential errors
      dynamic responseBody;
      try {
        responseBody = jsonDecode(response!.body);
      } on FormatException {
        ShowDialogs.showDialog(title: 'Trail Order Error', msg: 'Failed to parse trail order response (invalid JSON).');
        return;
      }

      if (response.statusCode == 200) {
        await doc.set(responseBody, SetOptions(merge: true));
        ShowDialogs.showDialog(title: 'Success', msg: 'Trail amount updated successfully.', type: DialogType.SUCCESS);
      } else {
        ShowDialogs.showDialog(title: 'Trail Order Error', msg: responseBody['message'] ?? 'Failed to update trail amount: HTTP ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Network Error', msg: 'Failed to connect to Delta Exchange: ${e.message}');
    } catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Trail Order Error', msg: 'An unexpected error occurred while updating trail amount: $e');
    }
  }

  void _onStockSelected(Map<String, dynamic> stock) {
    _optionChainRefreshTimer?.cancel();
    setState(() {
      _selectedStock = stock;
      _optionChainData = [];
      _selectedExpiryDate = DateFormat('dd-MM-yyyy').format(DateTime.now());
    });
    _fetchOptionChainData();
    _startOptionChainTimer();
  }

  void _startOptionChainTimer() {
    _optionChainRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_selectedStock != null && _selectedExpiryDate != null) {
        _fetchOptionChainData();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _fetchOptionChainData() async {
    if (_selectedStock == null || _selectedExpiryDate == null) return;

    setState(() {
      _isOptionChainLoading = true;
    });

    try {
      final response = await DeltaApi.get('/v2/tickers?contract_types=call_options,put_options&underlying_asset_symbols=${_selectedStock!['short_name']}&expiry_date=$_selectedExpiryDate');

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        final tickers = data['result'] as List;
        if (tickers.isEmpty) {
          setState(() {
            _optionChainData = [];
            _isOptionChainLoading = false;
          });
          ShowDialogs.showDialog(title: 'Info', msg: 'No option chain data found for the selected expiry date.');
          return;
        }

        // Group by strike price
        Map<String, Map<String, dynamic>> chain = {};
        for (var ticker in tickers) {
          final strike = ticker['strike_price'].toString();
          if (!chain.containsKey(strike)) {
            chain[strike] = {'strike_price': double.parse(strike)};
          }
          if (ticker['contract_type'] == 'call_options') {
            chain[strike]!['call'] = ticker;
          } else if (ticker['contract_type'] == 'put_options') {
            chain[strike]!['put'] = ticker;
          }
        }

        final sortedChain = chain.values.toList();
        sortedChain.sort((a, b) => a['strike_price'].compareTo(b['strike_price']));

        setState(() {
          _optionChainData = List<Map<String, dynamic>>.from(sortedChain);
          _spotPrice = double.parse(tickers.first['spot_price']?.toString() ?? '0.0');
        });

        _saveOiToFirestore(tickers);
      } else {
        ShowDialogs.showDialog(title: 'Error', msg: 'Failed to fetch option chain data: HTTP ${response.statusCode}');
      }
    } on http.ClientException catch (e) {
      ShowDialogs.showDialog(title: 'Network Error', msg: 'Failed to connect to Delta Exchange: ${e.message}');
    } on FormatException catch (e) {
      ShowDialogs.showDialog(title: 'Data Error', msg: 'Failed to parse option chain data (invalid JSON): $e');
    } catch (e) {
      ShowDialogs.showDialog(title: 'Error', msg: 'An unexpected error occurred while fetching option chain data: $e');
    }
    finally {
      if (mounted) {
        setState(() {
          _isOptionChainLoading = false;
        });
      }
    }
  }

  Future<void> _saveOiToFirestore(List<dynamic> tickers) async {
    final docId = '${_selectedStock!['name']}_$_selectedExpiryDate';
    final now = DateTime.now().toUtc();
    final timestamp = now.toIso8601String();

    final Map<String, dynamic> historyData = {};
    for (var ticker in tickers) {
      final strike = ticker['strike_price'].toString();
      final type = ticker['contract_type'] == 'call_options' ? 'call' : 'put';
      historyData['$strike-${type}_oi'] = ticker['oi'];
      historyData['$strike-${type}_volume'] = ticker['volume_24h'];
    }

    try {
      final docRef = FirebaseFirestore.instance.collection('option_chain_history').doc(docId);
      await docRef.set({
        'history': {
          timestamp: historyData,
        }
      }, SetOptions(merge: true));
    } catch (e) {
      // This error will not be shown in a dialog as it is a background process.
      // For production, consider using a proper logging solution.
      // For now, I'll log it to the console for debugging.
      print("Error saving option chain data to Firestore: $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131A19),
      body: Row(
        children: [
          _buildLeftPane(),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Dashboard',
                        style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 24),
                      if (!_isLoading) _buildBitcoinCard(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPositionsTable(),
                        const SizedBox(height: 24),
                        if (_selectedStock != null) _buildOptionChain(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBitcoinCard() {
    final btcStock = _stocks.firstWhere((s) => s['name'] == 'BTCUSD', orElse: () => {});
    if (btcStock.isEmpty) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isBitcoinCardHovered = true),
      onExit: (_) => setState(() => _isBitcoinCardHovered = false),
      child: InkWell(
        onTap: () => _onStockSelected(btcStock),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2827),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white.withAlpha((255 * 0.1).round())),
          ),
          child: Row(
            children: [
              Text(
                '${btcStock['name']}: ',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '${btcStock['ltp']}',
                style: const TextStyle(color: Color(0xFF32F5A3), fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 16),
              if (_isBitcoinCardHovered)
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: () => _showOrderDialog(btcStock, true),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF32F5A3)),
                          minimumSize: const Size(40, 32),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                      child: const Text('B', style: TextStyle(color: Color(0xFF32F5A3), fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _showOrderDialog(btcStock, false),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.redAccent),
                          minimumSize: const Size(40, 32),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                      child: const Text('S', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeftPane() {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E2827).withAlpha((255 * 0.9).round()),
            const Color(0xFF131A19).withAlpha((255 * 0.9).round()),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(right: BorderSide(color: Colors.white.withAlpha((255 * 0.1).round()))),
      ),
      child: Column(
        children: [
          const SizedBox(
            height: 80,
            child: Center(
              child: Text(
                'Stonks',
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard, color: Color(0xFF32F5A3)),
            title: const Text('Dashboard', style: TextStyle(color: Color(0xFF32F5A3), fontWeight: FontWeight.bold)),
            tileColor: const Color(0xFF2B403F).withAlpha((255 * 0.5).round()),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.pie_chart, color: Colors.white70),
            title: const Text('Portfolio', style: TextStyle(color: Colors.white70)),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.show_chart, color: Colors.white70),
            title: const Text('Markets', style: TextStyle(color: Colors.white70)),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.article, color: Colors.white70),
            title: const Text('News', style: TextStyle(color: Colors.white70)),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.filter_alt, color: Colors.white70),
            title: const Text('Screener', style: TextStyle(color: Colors.white70)),
            onTap: () {},
          ),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.settings_outlined, color: Colors.white70),
            title: const Text('Settings', style: TextStyle(color: Colors.white70)),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.white70),
            title: const Text('Logout', style: TextStyle(color: Colors.white70)),
            onTap: () {
              Utils.prefs.setBool("REM_LOGIN", false);
              Utils.prefs.remove("MOBILE");
              Utils.prefs.remove("PASS");
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.orangeAccent,
                  child: Text('AD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Alex Doe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('alex.doe@example.com', style: TextStyle(color: Colors.white.withAlpha((255 * 0.7).round()), fontSize: 12)),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(List<String> headers, List<int> flexValues) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: List.generate(headers.length, (index) {
          return Expanded(
            flex: flexValues[index],
            child: Text(headers[index], style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          );
        }),
      ),
    );
  }

  String _formatBracketPrice(dynamic trigger, dynamic limit) {
    final triggerStr = trigger?.toString() ?? '';
    final limitStr = limit?.toString() ?? '';

    if (triggerStr.isEmpty && limitStr.isEmpty) {
      return 'N/A';
    }

    if (limitStr.isEmpty) {
      return triggerStr;
    }

    return '$triggerStr/$limitStr';
  }

  Widget _buildPositionsTable() {
    final headers = ['NAME', 'QTY', 'AVG PRICE', 'TARGET', 'STOP LOSS', 'TRAILING SL', ''];
    final flexValues = [1, 1, 1, 2, 2, 2, 1];

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E2827).withAlpha((255 * 0.9).round()),
            const Color(0xFF131A19).withAlpha((255 * 0.9).round()),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withAlpha((255 * 0.1).round())),
      ),
      child: Column(
        children: [
          _buildTableHeader(headers, flexValues),
          const Divider(color: Colors.white12, height: 1),
          if (_positions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No open positions.', style: TextStyle(color: Colors.white70)),
            )
          else
            ..._positions.asMap().entries.map((entry) {
              int index = entry.key;
              final position = entry.value;
              final relevantOrders = _orders.where((o) => o['product_id'].toString() == position['product_id'].toString() && (o['state'] == 'open' || o['state'] == 'pending')).toList();

              var targetPrice = 'N/A';
              var stopLossPrice = 'N/A';
              Map<String, dynamic> takeProfitOrder = {};
              Map<String, dynamic> stopLossOrder = {};

              final bracketOrder = relevantOrders.firstWhere((o) => o['bracket_order'] == true, orElse: () => {});
              final hasBracket = bracketOrder.isNotEmpty;

              if (hasBracket) {
                targetPrice = _formatBracketPrice(bracketOrder['bracket_take_profit_price'], bracketOrder['bracket_take_profit_limit_price']);
                stopLossPrice = _formatBracketPrice(bracketOrder['bracket_stop_loss_price'], bracketOrder['bracket_stop_loss_limit_price']);
              } else {
                takeProfitOrder = relevantOrders.firstWhere((o) => o['stop_order_type'] == 'take_profit_order', orElse: () => {});
                if (takeProfitOrder.isNotEmpty) {
                  targetPrice = "${takeProfitOrder['stop_price'] ?? ''}/${takeProfitOrder['limit_price'] ?? ''}";
                }

                stopLossOrder = relevantOrders.firstWhere((o) => o['stop_order_type'] == 'stop_loss_order', orElse: () => {});
                if (stopLossOrder.isNotEmpty) {
                  stopLossPrice = "${stopLossOrder['stop_price'] ?? ''}/${stopLossOrder['limit_price'] ?? ''}";
                }
              }

              final trailOrder = relevantOrders.firstWhere((o) => o['trail_amount'] != null, orElse: () => {});
              final trailAmount = trailOrder['trail_amount']?.toString() ?? '0.0';

              final entryPrice = double.tryParse(position['entry_price'].toString()) ?? 0.0;

              return MouseRegion(
                onEnter: (_) => setState(() => _hoveredPositionIndex = index),
                onExit: (_) => setState(() => _hoveredPositionIndex = -1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  color: _hoveredPositionIndex == index ? const Color(0xFF2B403F).withAlpha((255 * 0.5).round()) : Colors.transparent,
                  child: Row(
                    children: [
                      Expanded(flex: flexValues[0], child: Text(position['product_symbol'].toString(), style: const TextStyle(color: Colors.white))),
                      Expanded(flex: flexValues[1], child: Text(position['size'].toString(), style: const TextStyle(color: Colors.white))),
                      Expanded(flex: flexValues[2], child: Text(entryPrice.toStringAsFixed(2), style: const TextStyle(color: Colors.white))),
                      Expanded(
                        flex: flexValues[3],
                        child: Row(
                          children: [
                            Text(targetPrice, style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => EditOrderDialog(
                                    initialTriggerPrice: hasBracket
                                        ? bracketOrder['bracket_take_profit_price']?.toString()
                                        : takeProfitOrder['stop_price']?.toString(),
                                    initialLimitPrice: hasBracket
                                        ? bracketOrder['bracket_take_profit_limit_price']?.toString()
                                        : takeProfitOrder['limit_price']?.toString(),
                                    onSave: (trigger, limit) {
                                      if (hasBracket) {
                                        _updateBracketLeg(bracketOrder, _BracketLeg.takeProfit, trigger, limit);
                                      } else {
                                        _updateOrder(position, takeProfitOrder, trigger, limit, 'take_profit_order');
                                      }
                                    },
                                  ),
                                );
                              },
                              child: const Icon(Icons.edit, color: Colors.white54, size: 16),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: flexValues[4],
                        child: Row(
                          children: [
                            Text(stopLossPrice, style: const TextStyle(color: Colors.white)),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => EditOrderDialog(
                                    initialTriggerPrice: hasBracket
                                        ? bracketOrder['bracket_stop_loss_price']?.toString()
                                        : stopLossOrder['stop_price']?.toString(),
                                    initialLimitPrice: hasBracket
                                        ? bracketOrder['bracket_stop_loss_limit_price']?.toString()
                                        : stopLossOrder['limit_price']?.toString(),
                                    onSave: (trigger, limit) {
                                      if (hasBracket) {
                                        _updateBracketLeg(bracketOrder, _BracketLeg.stopLoss, trigger, limit);
                                      } else {
                                        _updateOrder(position, stopLossOrder, trigger, limit, 'stop_loss_order');
                                      }
                                    },
                                  ),
                                );
                              },
                              child: const Icon(Icons.edit, color: Colors.white54, size: 16),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                          flex: flexValues[5],
                          child: EditableCell(
                            initialValue: trailAmount,
                            onSubmitted: (newTrailAmount) => _updateTrailAmount(position, trailOrder, newTrailAmount),
                          )),
                      Expanded(
                        flex: flexValues[6],
                        child: Row(
                          children: [
                            const SizedBox(width: 8),
                            Visibility(
                              visible: _hoveredPositionIndex == index,
                              maintainState: true,
                              maintainAnimation: true,
                              maintainSize: true,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.redAccent),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                  child: const Text('Close', style: TextStyle(color: Colors.redAccent)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildOptionChain() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF1E2827).withAlpha((255 * 0.9).round()),
            const Color(0xFF131A19).withAlpha((255 * 0.9).round()),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withAlpha((255 * 0.1).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedStock != null ? 'Option Chain for ${_selectedStock!['name']}' : 'Select a stock to view its Option Chain',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          if (_selectedStock != null) ..._buildOptionChainContent(),
        ],
      ),
    );
  }

  List<Widget> _buildOptionChainContent() {
    if (_isOptionChainLoading) {
      return [const Center(child: CircularProgressIndicator())];
    } else if (_selectedExpiryDate == null) {
      return [_buildDatePickerButton()];
    } else if (_optionChainData.isEmpty && !_isOptionChainLoading) {
      return [
        _buildDatePickerButton(),
        const SizedBox(height: 16),
        const Center(child: Text('No option chain data for this expiry date.', style: TextStyle(color: Colors.white70)))
      ];
    } else {
      return [
        _buildDatePickerButton(),
        const SizedBox(height: 16),
        Column(
          children: [
            const Text('Call & Put Volumes', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            VolumeChart(underlyingAsset: _selectedStock!['name'], expiryDate: _selectedExpiryDate!),
            const SizedBox(height: 24),
            const Text('Change in OI over Time', style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            OiChart(underlyingAsset: _selectedStock!['name'], expiryDate: _selectedExpiryDate!),
          ],
        ),
      ];
    }
  }

  Widget _buildDatePickerButton() {
    return Center(
      child: OutlinedButton(
        onPressed: () async {
          final DateTime? picked = await showDatePicker(
            context: context,
            initialDate: DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2101),
          );
          if (picked != null) {
            final formattedDate = DateFormat('dd-MM-yyyy').format(picked);
            setState(() {
              _selectedExpiryDate = formattedDate;
            });
            _optionChainRefreshTimer?.cancel();
            _fetchOptionChainData();
            _startOptionChainTimer();
          }
        },
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            _selectedExpiryDate ?? 'Select Expiry Date',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

class EditableCell extends StatefulWidget {
  const EditableCell({super.key, required this.initialValue, required this.onSubmitted});

  final String initialValue;
  final Function(String) onSubmitted;

  @override
  State<EditableCell> createState() => _EditableCellState();
}

class _EditableCellState extends State<EditableCell> {
  late TextEditingController _controller;
  bool _isEditing = false;
  String _value = '';

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _controller = TextEditingController(text: _value);
  }

  @override
  void didUpdateWidget(EditableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      setState(() {
        _value = widget.initialValue;
        _controller.text = _value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isEditing
        ? SizedBox(
            width: 80,
            height: 32,
            child: TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                isCollapsed: true,
                filled: true,
                fillColor: const Color(0xFF131A19),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4.0),
                  borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.2).round())),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4.0),
                  borderSide: BorderSide(color: Colors.white.withAlpha((255 * 0.2).round())),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4.0),
                  borderSide: const BorderSide(color: Color(0xFF32F5A3)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              ),
              onSubmitted: (newValue) {
                setState(() {
                  _value = newValue;
                  _isEditing = false;
                });
                widget.onSubmitted(newValue);
              },
            ),
          )
        : Row(
            children: [
              Text(_value, style: const TextStyle(color: Colors.white)),
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  setState(() {
                    _isEditing = true;
                  });
                },
                child: const Icon(Icons.edit, color: Colors.white54, size: 16),
              ),
            ],
          );
  }
}
