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
