# Delta Exchange API Touchpoints

This document gathers every place in the codebase that talks directly to the Delta Exchange APIs so you can share the implementation details with someone else. Each snippet is pulled verbatim from the Flutter project and is preceded by a short remark on what it does.

---

## REST Utility (`lib/utils/delta_api.dart`)

> **Remark:** Central helper that signs every REST request (including bracket, order edit, etc.) with the HMAC strategy mandated by Delta.

```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class DeltaApi {
  static const String _baseUrl = 'https://api.india.delta.exchange';
  static String apiKey = '';
  static String apiSecret = '';

  static String getWebSocketAuthSignature() {
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      throw Exception('API key and secret are not set.');
    }

    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
    const method = 'GET';
    const path = '/live';

    final signatureData = method + timestamp + path;
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(signatureData);

    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }

  static Future<http.Response> get(String path) async {
    return _sendRequest('GET', path, null);
  }

  static Future<http.Response> post(String path, Map<String, dynamic> payload) async {
    return _sendRequest('POST', path, payload);
  }

  static Future<http.Response> put(String path, Map<String, dynamic> payload) async {
    return _sendRequest('PUT', path, payload);
  }

  static Future<http.Response> delete(String path, Map<String, dynamic> payload) async {
    return _sendRequest('DELETE', path, payload);
  }

  static Future<http.Response> _sendRequest(String method, String path, Map<String, dynamic>? payload) async {
    if (apiKey.isEmpty || apiSecret.isEmpty) {
      throw Exception('API key and secret are not set.');
    }

    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
    
    String requestBody = '';
    if (payload != null && method != 'GET') {
      requestBody = jsonEncode(payload);
    }

    final signatureData = method + timestamp + path + requestBody;
    final key = utf8.encode(apiSecret);
    final bytes = utf8.encode(signatureData);

    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    final signature = digest.toString();

    final headers = {
      'api-key': apiKey,
      'timestamp': timestamp,
      'signature': signature,
      'Content-Type': 'application/json',
    };

    final url = Uri.parse('$_baseUrl$path');
    
    switch (method) {
      case 'GET':
        return http.get(url, headers: headers);
      case 'POST':
        return http.post(url, headers: headers, body: requestBody);
      case 'PUT':
        return http.put(url, headers: headers, body: requestBody);
      case 'DELETE':
        return http.delete(url, headers: headers);
      default:
        throw Exception('Unsupported HTTP method: $method');
    }
  }
}
```

---

## WebSocket Authentication + Subscriptions (`lib/home_page.dart`)

> **Remark:** Opens the Delta WebSocket, authenticates it with the signature above, and subscribes to tickers, positions, and orders so UI stays live.

```dart
late final WebSocketChannel _channel;
bool _isWebSocketAuthenticated = false;

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
```

---

## Streaming Handlers (Still in `lib/home_page.dart`)

> **Remark:** These three functions consume the subscribed channels and keep the in-memory collections `_stocks`, `_positions`, and `_orders` aligned with exchange state.

```dart
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
```

---

## Placing Orders with Brackets (`lib/place_order_page.dart`)

> **Remark:** `_placeOrder` sends the primary order via `/v2/orders` and immediately attaches bracket stop-loss / take-profit legs via `/v2/orders/bracket`. Supporting helpers validate form input and construct the bracket payload.

```dart
Future<void> _placeOrder() async {
  final validationError = _validateForm();
  if (validationError != null) {
    ShowDialogs.showDialog(title: 'Invalid Input', msg: validationError);
    return;
  }

  ShowDialogs.showProgressDialog();

  try {
    final doc = DBUtils.userDoc.reference.collection("ORDERS").doc();

    final payload = <String, dynamic>{
      'product_id': widget.stock['code'],
      'product_symbol': widget.stock['name'],
      'side': _isBuy ? 'buy' : 'sell',
      'order_type': _isMarketOrder ? 'market_order' : 'limit_order',
      'size': int.tryParse(_quantityController.text) ?? 0,
      'client_order_id': doc.id,
    };

    if (!_isMarketOrder) {
      payload['limit_price'] = _limitPriceController.text;
    }

    final bracketPayload = _buildBracketPayload();

    final response = await DeltaApi.post('/v2/orders', payload);
    dynamic responseBody;
    try {
      responseBody = jsonDecode(response.body);
    } on FormatException {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Order Error', msg: 'Failed to parse order response.');
      return;
    }

    if (response.statusCode != 200) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Order Error', msg: responseBody['message'] ?? 'Failed to place order.');
      return;
    }

    await doc.set(responseBody);

    if (bracketPayload != null) {
      final bracketResponse = await DeltaApi.post('/v2/orders/bracket', bracketPayload);

      dynamic bracketBody;
      try {
        bracketBody = jsonDecode(bracketResponse.body);
      } on FormatException {
        ShowDialogs.dismissProgressDialog();
        ShowDialogs.showDialog(title: 'Bracket Error', msg: 'Failed to parse bracket order response.');
        return;
      }

      if (bracketResponse.statusCode != 200) {
        ShowDialogs.dismissProgressDialog();
        ShowDialogs.showDialog(
          title: 'Bracket Error',
          msg: bracketBody['message'] ?? 'Failed to attach bracket order.',
        );
        return;
      }
    }

    ShowDialogs.dismissProgressDialog();
    Navigator.of(context).pop();
    final successMsg = bracketPayload != null ? 'Order and bracket placed successfully.' : 'Order placed successfully.';
    ShowDialogs.showDialog(title: 'Success', msg: successMsg, type: DialogType.SUCCESS);
  } catch (e) {
    ShowDialogs.dismissProgressDialog();
    ShowDialogs.showDialog(title: 'Error', msg: 'An unexpected error occurred.');
  }
}

String? _validateForm() {
  final quantity = int.tryParse(_quantityController.text.trim());
  if (quantity == null || quantity <= 0) {
    return 'Enter a valid quantity.';
  }

  if (!_isMarketOrder && _limitPriceController.text.trim().isEmpty) {
    return 'Limit price is required for limit orders.';
  }

  if (_targetTriggerEnabled && _targetTriggerPriceController.text.trim().isEmpty) {
    return 'Target trigger price is required for take profit.';
  }

  if (_stopLossEnabled && _stopLossTriggerPriceController.text.trim().isEmpty) {
    return 'Stop-loss trigger price is required.';
  }

  return null;
}

Map<String, dynamic>? _buildBracketPayload() {
  final hasTarget = _targetTriggerEnabled && _targetTriggerPriceController.text.trim().isNotEmpty;
  final hasStop = _stopLossEnabled && _stopLossTriggerPriceController.text.trim().isNotEmpty;

  if (!hasTarget && !hasStop) {
    return null;
  }

  final payload = <String, dynamic>{
    'product_id': widget.stock['code'],
    'product_symbol': widget.stock['name'],
    'bracket_stop_trigger_method': 'last_traded_price',
  };

  if (hasTarget) {
    final targetOrder = <String, dynamic>{
      'order_type': _targetLimitPriceController.text.trim().isEmpty ? 'market_order' : 'limit_order',
      'stop_price': _targetTriggerPriceController.text.trim(),
    };

    if (_targetLimitPriceController.text.trim().isNotEmpty) {
      targetOrder['limit_price'] = _targetLimitPriceController.text.trim();
    }

    payload['take_profit_order'] = targetOrder;
  }

  if (hasStop) {
    final stopOrder = <String, dynamic>{
      'order_type': _stopLossLimitPriceController.text.trim().isEmpty ? 'market_order' : 'limit_order',
      'stop_price': _stopLossTriggerPriceController.text.trim(),
    };

    if (_stopLossLimitPriceController.text.trim().isNotEmpty) {
      stopOrder['limit_price'] = _stopLossLimitPriceController.text.trim();
    }

    payload['stop_loss_order'] = stopOrder;
  }

  return payload;
}
```

---

## Managing Existing Orders (`lib/home_page.dart`)

> **Remark:** `_updateOrder` handles standalone stop-loss / take-profit reduce-only orders, `_updateBracketLeg` edits the bracket legs attached to an entry, and `_updateTrailAmount` creates/updates/cancels trailing-stop orders via REST.

```dart
Future<void> _updateOrder(Map<String, dynamic> position, Map<String, dynamic> order, String triggerPrice, String limitPrice, String orderType) async {
  ShowDialogs.showProgressDialog();

  try {
    http.Response response;
    final doc = order.isNotEmpty ? DBUtils.userDoc.reference.collection("ORDERS").doc(order['client_order_id']) : DBUtils.userDoc.reference.collection("ORDERS").doc();

    if (order.isNotEmpty) {
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
```

---

That’s everything that actively touches the Delta Exchange APIs: REST helpers, WebSocket auth/subscriptions, real-time handlers, order placement (with bracket legs), and follow-up order management routines. Send this file along and your teammate will have all the exchange-integration code in one place.






