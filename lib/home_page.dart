import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finwiz/login_page.dart';
import 'package:finwiz/place_order_page.dart';
import 'package:finwiz/services/option_chain_service.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:finwiz/widgets/edit_order_dialog.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
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

  WebSocketChannel? _channel;
  bool _isWebSocketAuthenticated = false;
  bool _isConnected = false;
  Timer? _reconnectTimer;

  final ValueNotifier<double> _btcPriceNotifier = ValueNotifier<double>(0.0);
  double _userBalanceUsd = 0.0;
  final double _usdToInr = 85.0;

  @override
  void initState() {
    super.initState();
    _fetchStocks();
    _fetchBalance();
    _connectWebSocket();
    //OptionChainService().startBackgroundSync('BTC');
  }

  Future<void> _fetchBalance() async {
    final balance = await DeltaApi.getUSDBalance();
    if (mounted) {
      setState(() {
        _userBalanceUsd = balance;
      });
    }
  }

  void _connectWebSocket() {
    if (_isConnected || _channel != null) return;
    print("Attempting to connect to WebSocket...");
    try {
      _channel = WebSocketChannel.connect(Uri.parse('wss://socket.india.delta.exchange'));
      _channel!.stream.listen(
            (message) {
          if (!_isConnected) setState(() => _isConnected = true);
          _handleWebSocketMessage(message);
        },
        onError: (error) { print("WebSocket Error: $error"); _handleDisconnect(); },
        onDone: () { print("WebSocket Connection Closed"); _handleDisconnect(); },
      );
      _authenticateWebSocket();
    } catch (e) {
      print("WebSocket Connection Failed: $e");
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _isWebSocketAuthenticated = false;
      _channel = null;
    });
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) { print("Reconnecting..."); _connectWebSocket(); }
    });
  }

  void _authenticateWebSocket() {
    try {
      final signature = DeltaApi.getWebSocketAuthSignature();
      final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
      _channel?.sink.add(jsonEncode({
        'type': 'key-auth',
        'payload': {'api-key': DeltaApi.apiKey, 'signature': signature, 'timestamp': timestamp}
      }));
    } catch (e) { print("Auth Error: $e"); }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (!mounted) return;
    try {
      final decodedMessage = jsonDecode(message);
      if (decodedMessage['type'] == 'key-auth') {
        if (decodedMessage['success'] == true){
          setState(() => _isWebSocketAuthenticated = true);
          _subscribeToChannels();
        }else{
          ShowDialogs.showDialog(title: 'Error', msg: decodedMessage.toString());
        }
      }
      if (_isWebSocketAuthenticated) {
        if (decodedMessage['type'] == 'v2/ticker') _handleTickerUpdate(decodedMessage);
        else if (decodedMessage['type'] == 'positions') _handlePositionUpdate(decodedMessage);
        else if (decodedMessage['type'] == 'orders') _handleOrderUpdate(decodedMessage);
      }
    } catch (e) { print("Message parsing error: $e"); }
  }

  void _handleTickerUpdate(Map<String, dynamic> data) {
    final productId = data['product_id'];
    final stockIndex = _stocks.indexWhere((s) => s['code'].toString() == productId.toString());
    if (stockIndex != -1) {
      final close = double.tryParse(data['close'].toString()) ?? 0.0;
      setState(() {
        _stocks[stockIndex]['ltp'] = data['close'];
        _stocks[stockIndex]['open'] = data['open'];
        _stocks[stockIndex]['high'] = data['high'];
        _stocks[stockIndex]['low'] = data['low'];
        _stocks[stockIndex]['close'] = data['close'];
      });
      if (_stocks[stockIndex]['name'] == 'BTCUSD') {
        _btcPriceNotifier.value = close;
      }
    }
  }

  void _handlePositionUpdate(Map<String, dynamic> data) {
    setState(() {
      if (data['action'] == 'snapshot') {
        _positions = List<Map<String, dynamic>>.from(data['result']);
      } else {
        final symbol = data['symbol'];
        final index = _positions.indexWhere((p) => p['symbol'] == symbol);
        if (data['action'] == 'create') _positions.add(data);
        else if (data['action'] == 'update' && index != -1) _positions[index] = data;
        else if (data['action'] == 'delete' && index != -1) _positions.removeAt(index);
      }
    });
  }

  void _handleOrderUpdate(Map<String, dynamic> data) {
    setState(() {
      if (data['action'] == 'snapshot') {
        _orders = List<Map<String, dynamic>>.from(data['result']);
      } else {
        final id = data['id'];
        final index = _orders.indexWhere((o) => o['id'].toString() == id.toString());

        if (data['action'] == 'create') _orders.add(data);
        else if (data['action'] == 'update' && index != -1) _orders[index] = data;
        else if (data['action'] == 'delete' && index != -1) _orders.removeAt(index);
      }
    });
  }

  Future<void> _fetchStocks() async {
    try {
      final snapshot = await DBUtils.getData(collection: "STOCKS", condition: "PLATFORM=DELTA", showProgress: false);
      if (mounted) {
        if (snapshot.querySnapshot != null && snapshot.querySnapshot!.docs.isNotEmpty) {
          final fetchedStocks = snapshot.querySnapshot!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'name': doc.id,
              'short_name': data['NAME'],
              'code': data['CODE'],
              'ltp': 'N/A', 'open': 'N/A', 'high': 'N/A', 'low': 'N/A', 'close': 'N/A',
            };
          }).toList();
          setState(() { _stocks = fetchedStocks; _isLoading = false; });
          if (_isWebSocketAuthenticated) _subscribeToChannels();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) { if (mounted) setState(() => _isLoading = false); }
  }

  void _subscribeToChannels() {
    if (_channel == null || !_isWebSocketAuthenticated) return;
    final symbols = _stocks.map((s) => s['name']).toList();
    _channel!.sink.add(jsonEncode({
      'type': 'subscribe',
      'payload': {
        'channels': [
          {'name': 'v2/ticker', 'symbols': symbols},
          {'name': 'positions', 'symbols': ['all']},
          {'name': 'orders', 'symbols': ['all']}
        ]
      }
    }));
  }

  Future<void> _openOptionChainWindow(String symbol) async {
    try {
      final window = await DesktopMultiWindow.createWindow(jsonEncode({
        'symbol': symbol,
        'apiKey': DeltaApi.apiKey,
        'apiSecret': DeltaApi.apiSecret,
      }));
      window..setFrame(const Offset(0, 0) & const Size(1000, 800))..center()..setTitle('$symbol Option Chain Graphs')..show();
    } catch (e) { print("Error opening window: $e"); }
  }

  Map<String, String> _getBracketsForDisplay(Map<String, dynamic> item, bool isPosition) {
    String tp = '-';
    String sl = '-';
    if (isPosition) {
      final relevantOrders = _orders.where((o) =>
      o['product_id'].toString() == item['product_id'].toString() &&
          (o['state'] == 'open' || o['state'] == 'pending')
      ).toList();
      final tpOrder = relevantOrders.firstWhere((o) => o['stop_order_type'] == 'take_profit_order', orElse: () => {});
      if (tpOrder.isNotEmpty) tp = tpOrder['stop_price'].toString();
      final slOrder = relevantOrders.firstWhere((o) => o['stop_order_type'] == 'stop_loss_order', orElse: () => {});
      if (slOrder.isNotEmpty) sl = slOrder['stop_price'].toString();
    } else {
      if (item['bracket_take_profit_price'] != null) tp = item['bracket_take_profit_price'].toString();
      if (item['bracket_stop_loss_price'] != null) sl = item['bracket_stop_loss_price'].toString();
    }
    return {'tp': tp, 'sl': sl};
  }

  void _showOrderDialog(Map<String, dynamic> stock, bool isBuy, {Map<String, dynamic>? existingOrder, bool isPositionMode = false, Map<String, dynamic>? tpOrder, Map<String, dynamic>? slOrder}) {
    String? existingTpPrice;
    String? existingSlPrice;

    if (isPositionMode) {
      if (tpOrder != null) existingTpPrice = tpOrder['stop_price'].toString();
      if (slOrder != null) existingSlPrice = slOrder['stop_price'].toString();
    } else if (existingOrder != null) {
      final brackets = _getBracketsForDisplay(existingOrder, false);
      if (brackets['tp'] != '-') existingTpPrice = brackets['tp'];
      if (brackets['sl'] != '-') existingSlPrice = brackets['sl'];
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return PlaceOrderPage(
          stock: stock,
          isBuy: isBuy,
          priceNotifier: _btcPriceNotifier,
          accountBalance: _userBalanceUsd,
          existingOrder: existingOrder,
          existingTpOrder: tpOrder,
          existingSlOrder: slOrder,
          initialTargetPrice: existingTpPrice,
          initialStopLossPrice: existingSlPrice,
          isPositionMode: isPositionMode,
        );
      },
    );
  }

  // --- UPDATED: Edit Position Brackets ---
  Future<void> _editPositionBrackets(Map<String, dynamic> position) async {
    final productId = position['product_id'].toString();
    final stock = _stocks.firstWhere((s) => s['code'].toString() == productId,
        orElse: () => {'name': position['product_symbol'], 'code': position['product_id']});

    // 1. Try to find Active Independent TP/SL orders
    Map<String, dynamic>? findOrder(String type) {
      try {
        return _orders.firstWhere((o) =>
        o['product_id'].toString() == productId &&
            (o['state'] == 'open' || o['state'] == 'pending') &&
            o['stop_order_type'] == type
        );
      } catch (e) { return null; }
    }

    final tpOrder = findOrder('take_profit_order');
    final slOrder = findOrder('stop_loss_order');

    _showOrderDialog(
      stock,
      double.parse(position['size'].toString()) > 0,
      existingOrder: position,
      isPositionMode: true,
      tpOrder: tpOrder,
      slOrder: slOrder,
    );
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
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Open Positions', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _buildPositionsTable(),
                        const SizedBox(height: 32),
                        const Text('Open Orders', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _buildOpenOrdersTable(),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          const Text('Dashboard', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _isConnected ? Colors.greenAccent : Colors.redAccent)),
          const SizedBox(width: 24),
          if (!_isLoading) _buildBitcoinCard(),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("Available Balance", style: TextStyle(color: Colors.white54, fontSize: 12)),
              Row(
                children: [
                  Text("\$${Utils.round(2, num: _userBalanceUsd)}", style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text("(₹${Utils.round(2, num: _userBalanceUsd * _usdToInr)})", style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildBitcoinCard() {
    final btcStock = _stocks.firstWhere((s) => s['name'] == 'BTCUSD', orElse: () => {});
    if (btcStock.isEmpty) return const SizedBox.shrink();
    return GestureDetector(
      onSecondaryTapUp: (details) {
        showMenu(
          context: context,
          position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx + 1, details.globalPosition.dy + 1),
          color: const Color(0xFF1E2827),
          items: [const PopupMenuItem(value: 'graphs', child: Text("View Option Chain Graphs", style: TextStyle(color: Colors.white)))],
        ).then((v) { if (v == 'graphs') _openOptionChainWindow(btcStock['short_name'] ?? 'BTC'); });
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isBitcoinCardHovered = true),
        onExit: (_) => setState(() => _isBitcoinCardHovered = false),
        child: InkWell(
          onTap: () {},
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            decoration: BoxDecoration(color: const Color(0xFF1E2827), borderRadius: BorderRadius.circular(8.0), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(
              children: [
                Text('${btcStock['name']}: ', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('${btcStock['ltp']}', style: const TextStyle(color: Color(0xFF32F5A3), fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                if (_isBitcoinCardHovered) Row(children: [
                  OutlinedButton(onPressed: () => _showOrderDialog(btcStock, true), style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF32F5A3))), child: const Text('B', style: TextStyle(color: Color(0xFF32F5A3)))),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => _showOrderDialog(btcStock, false), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)), child: const Text('S', style: TextStyle(color: Colors.redAccent))),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _closePosition(Map<String, dynamic> position) async {
    ShowDialogs.showProgressDialog();
    try {
      final size = double.tryParse(position['size'].toString()) ?? 0;
      if (size == 0) return;

      // Close means creating a Market Order in the opposite direction
      // reduce_only = true ensures it closes existing position and doesn't flip
      final payload = {
        'product_id': position['product_id'],
        'size': size.abs().toInt(),
        'side': size > 0 ? 'sell' : 'buy', // Opposite side
        'order_type': 'market_order',
        'reduce_only': true,
      };

      final response = await DeltaApi.post('/v2/orders', payload);
      ShowDialogs.dismissProgressDialog();

      if (response.statusCode == 200) {
        ShowDialogs.showDialog(title: 'Success', msg: 'Position closed successfully.', type: DialogType.SUCCESS);
      } else {
        final body = jsonDecode(response.body);
        ShowDialogs.showDialog(title: 'Error', msg: body['message'] ?? 'Failed to close position.');
      }
    } catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Error', msg: 'Error closing position: $e');
    }
  }

  Widget _buildPositionsTable() {
    final headers = ['NAME', 'QTY', 'AVG PRICE', 'TARGET', 'STOP LOSS', 'PnL', ''];
    final flexValues = [1, 1, 1, 2, 2, 2, 1];

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: const Color(0xFF1E2827).withOpacity(0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
      child: Column(
        children: [
          _buildTableHeader(headers, flexValues),
          const Divider(color: Colors.white12, height: 1),
          if (_positions.isEmpty) const Padding(padding: EdgeInsets.all(16.0), child: Text('No open positions.', style: TextStyle(color: Colors.white70)))
          else ..._positions.asMap().entries.map((entry) {
            int index = entry.key;
            final position = entry.value;
            final brackets = _getBracketsForDisplay(position, true);

            final stock = _stocks.firstWhere((s) => s['code'].toString() == position['product_id'].toString(), orElse: () => {});
            double currentPrice = (stock.isNotEmpty && stock['ltp'] != 'N/A') ? double.tryParse(stock['ltp'].toString()) ?? 0.0 : 0.0;
            double entryPrice = double.tryParse(position['entry_price'].toString()) ?? 0.0;
            double size = double.tryParse(position['size'].toString()) ?? 0.0;

            double rawPnl = 0.0;
            if (currentPrice > 0 && entryPrice > 0) {
              if (size > 0) rawPnl = (currentPrice - entryPrice) * size.abs() * 0.001;
              else rawPnl = (entryPrice - currentPrice) * size.abs() * 0.001;
            }
            Color pnlColor = rawPnl >= 0 ? Colors.greenAccent : Colors.redAccent;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: index % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02),
              child: Row(
                children: [
                  Expanded(flex: flexValues[0], child: Text(position['product_symbol'].toString(), style: const TextStyle(color: Colors.white))),
                  Expanded(flex: flexValues[1], child: Text(position['size'].toString(), style: const TextStyle(color: Colors.white))),
                  Expanded(flex: flexValues[2], child: Text(Utils.round(2, s: position['entry_price']), style: const TextStyle(color: Colors.white))),
                  Expanded(flex: flexValues[3], child: Row(children: [Text(brackets['tp']!, style: const TextStyle(color: Colors.white)), const SizedBox(width: 4), InkWell(onTap: () => _editPositionBrackets(position), child: const Icon(Icons.edit, color: Colors.white54, size: 14))])),
                  Expanded(flex: flexValues[4], child: Row(children: [Text(brackets['sl']!, style: const TextStyle(color: Colors.white)), const SizedBox(width: 4), InkWell(onTap: () => _editPositionBrackets(position), child: const Icon(Icons.edit, color: Colors.white54, size: 14))])),
                  Expanded(flex: flexValues[5], child: Text("${rawPnl >= 0 ? '+' : ''}\$${Utils.round(2, num: rawPnl)}", style: TextStyle(color: pnlColor, fontWeight: FontWeight.bold))),

                  // CLOSE BUTTON
                  Expanded(flex: flexValues[6], child: OutlinedButton(
                      onPressed: () => _closePosition(position),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent), padding: EdgeInsets.zero, minimumSize: const Size(60, 30)),
                      child: const Text('Close', style: TextStyle(color: Colors.redAccent, fontSize: 12))
                  )),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildOpenOrdersTable() {
    final headers = ['TIME', 'SYMBOL', 'TYPE', 'SIDE', 'PRICE', 'QTY', 'TARGET', 'STOP LOSS', 'STATUS', 'ACTIONS'];
    final flexValues = [2, 1, 1, 1, 1, 1, 1, 1, 1, 2];
    final openOrders = _orders.where((o) => (o['state'] == 'open' || o['state'] == 'pending') && (o['stop_order_type'] == null)).toList();
    openOrders.sort((a, b) => (b['created_at'] is int ? b['created_at'] : 0).compareTo(a['created_at'] is int ? a['created_at'] : 0));

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(color: const Color(0xFF1E2827).withOpacity(0.5), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
      child: Column(
        children: [
          _buildTableHeader(headers, flexValues),
          const Divider(color: Colors.white12, height: 1),
          if (openOrders.isEmpty) const Padding(padding: EdgeInsets.all(16.0), child: Text('No open orders.', style: TextStyle(color: Colors.white70)))
          else ...openOrders.asMap().entries.map((entry) {
            int index = entry.key;
            final order = entry.value;
            DateTime date;
            if (order['created_at'] is int) date = DateTime.fromMillisecondsSinceEpoch(order['created_at'] ~/ 1000);
            else if (order['created_at'] is String) date = DateTime.tryParse(order['created_at']) ?? DateTime.now();
            else date = DateTime.now();
            final timeStr = DateFormat('MM-dd HH:mm').format(date);
            final isBuy = order['side'] == 'buy';
            final brackets = _getBracketsForDisplay(order, false);

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: index % 2 == 0 ? Colors.transparent : Colors.white.withOpacity(0.02),
              child: Row(
                children: [
                  Expanded(flex: flexValues[0], child: Text(timeStr, style: const TextStyle(color: Colors.white70, fontSize: 12))),
                  Expanded(flex: flexValues[1], child: Text(order['product_symbol'], style: const TextStyle(color: Colors.white))),
                  Expanded(flex: flexValues[2], child: Text(order['order_type'].toString().replaceAll('_order', '').toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12))),
                  Expanded(flex: flexValues[3], child: Text(order['side'].toString().toUpperCase(), style: TextStyle(color: isBuy ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.bold))),
                  Expanded(flex: flexValues[4], child: Text(order['limit_price'] ?? 'MKT', style: const TextStyle(color: Colors.white))),
                  Expanded(flex: flexValues[5], child: Text(order['size'].toString(), style: const TextStyle(color: Colors.white))),
                  Expanded(flex: flexValues[6], child: Text(brackets['tp']!, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  Expanded(flex: flexValues[7], child: Text(brackets['sl']!, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  Expanded(flex: flexValues[8], child: Text(order['state'], style: const TextStyle(color: Colors.orangeAccent, fontSize: 12))),
                  Expanded(flex: flexValues[9], child: Row(children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blueAccent, size: 18), onPressed: () { final stock = _stocks.firstWhere((s) => s['name'] == order['product_symbol'], orElse: () => {'name': order['product_symbol'], 'code': order['product_id']}); _showOrderDialog(stock, isBuy, existingOrder: order); }),
                    IconButton(icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 18), onPressed: () => DeltaApi.cancelOrder(order['id'].toString(), order['product_id'].toString())),
                  ])),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTableHeader(List<String> h, List<int> f) { return Row(children: List.generate(h.length, (i) => Expanded(flex: f[i], child: Text(h[i], style: const TextStyle(color: Colors.white54, fontSize: 12))))); }
  @override void dispose() { _reconnectTimer?.cancel(); _channel?.sink.close(); super.dispose(); OptionChainService().stopBackgroundSync();}
}