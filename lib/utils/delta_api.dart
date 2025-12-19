import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../widgets/show_dialogs.dart';

class DeltaApi {
  static const String baseUrl = 'https://api.india.delta.exchange';
  static String apiKey = '';
  static String apiSecret = '';

  static Map<String, String> _getHeaders(String method, String path, String payload) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).round().toString();
    final signatureData = method + timestamp + path + payload;
    final hmac = Hmac(sha256, utf8.encode(apiSecret));
    final signature = hmac.convert(utf8.encode(signatureData)).toString();

    return {
      'Content-Type': 'application/json',
      'api-key': apiKey,
      'signature': signature,
      'timestamp': timestamp,
    };
  }

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

  static Future<http.Response> get(String endpoint) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final headers = _getHeaders('GET', endpoint, '');
    return await http.get(uri, headers: headers);
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final payload = jsonEncode(data);
    final headers = _getHeaders('POST', endpoint, payload);
    return await http.post(uri, headers: headers, body: payload);
  }

  static Future<http.Response> put(String endpoint, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final payload = jsonEncode(data);
    final headers = _getHeaders('PUT', endpoint, payload);
    return await http.put(uri, headers: headers, body: payload);
  }

  // FIX: Use http.Request to ensure Body and Headers are sent correctly for DELETE
  static Future<http.Response> delete(String endpoint, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl$endpoint');
    final payload = jsonEncode(data);
    final headers = _getHeaders('DELETE', endpoint, payload);

    final request = http.Request('DELETE', uri);
    request.headers.addAll(headers);
    request.body = payload;

    final streamedResponse = await request.send();
    return await http.Response.fromStream(streamedResponse);
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

    final url = Uri.parse('$baseUrl$path');
    
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

  static Future<double> getUSDBalance() async {
    try {
      final response = await get('/v2/wallet/balances');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'] as List;
        // Usually, the trading balance is in USDT or DETO.
        // We'll look for USDT (Asset ID 2 usually, or symbol USDT)
        // Adjust logic if your primary collateral is BTC or DETO
        final usdtWallet = result.firstWhere(
                (w) => w['asset_symbol'] == 'USD',
            orElse: () => null
        );

        if (usdtWallet != null) {
          return double.parse(usdtWallet['balance'].toString());
        }
        ShowDialogs.showDialog(title: 'Error', msg: response.body);
        return 0.0;
      }
    } catch (e) {
      print("Error fetching balance: $e");
    }
    return 0.0;
  }

  static Future<void> cancelOrder(String orderId, String productId, [bool showDialogs = true]) async {
    if (showDialogs){
      ShowDialogs.showProgressDialog();
    }
    try {
      // FIX: Ensure ID is string and product_id is int/string correctly formatted
      final payload = {
        'id': orderId,
        'product_id': int.parse(productId),
      };

      final response = await DeltaApi.delete('/v2/orders', payload);
      if (showDialogs){
        ShowDialogs.dismissProgressDialog();
      }

      if (response.statusCode == 200) {
        if (showDialogs){
          ShowDialogs.showDialog(title: 'Success', msg: 'Order cancelled successfully.', type: DialogType.SUCCESS);
        }
      } else {
        final body = jsonDecode(response.body);
        if (showDialogs){
          ShowDialogs.showDialog(title: 'Error', msg: body['message'] ?? 'Failed to cancel order.');
        }
      }
    } catch (e) {
      if (showDialogs){
        ShowDialogs.dismissProgressDialog();
        ShowDialogs.showDialog(title: 'Error', msg: 'Error cancelling order: $e');
      }
    }
  }
}
