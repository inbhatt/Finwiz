import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:flutter/material.dart';

class PlaceOrderPage extends StatefulWidget {
  final Map<String, dynamic> stock;
  final bool isBuy;

  const PlaceOrderPage({Key? key, required this.stock, required this.isBuy}) : super(key: key);

  @override
  _PlaceOrderPageState createState() => _PlaceOrderPageState();
}

class _PlaceOrderPageState extends State<PlaceOrderPage> {
  late bool _isBuy;
  bool _isMarketOrder = true;
  bool _stopLossEnabled = false;
  bool _targetTriggerEnabled = false;

  final _quantityController = TextEditingController();
  final _limitPriceController = TextEditingController();
  final _targetTriggerPriceController = TextEditingController();
  final _targetLimitPriceController = TextEditingController();
  final _stopLossTriggerPriceController = TextEditingController();
  final _stopLossLimitPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isBuy = widget.isBuy;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _limitPriceController.dispose();
    _targetTriggerPriceController.dispose();
    _targetLimitPriceController.dispose();
    _stopLossTriggerPriceController.dispose();
    _stopLossLimitPriceController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
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

      if (_targetTriggerEnabled) {
        payload['bracket_take_profit_price'] = _targetTriggerPriceController.text;
        if (_targetLimitPriceController.text.isNotEmpty) {
          payload['bracket_take_profit_limit_price'] = _targetLimitPriceController.text;
        }
      }

      if (_stopLossEnabled) {
        payload['bracket_stop_loss_price'] = _stopLossTriggerPriceController.text;
        if (_stopLossLimitPriceController.text.isNotEmpty) {
          payload['bracket_stop_loss_limit_price'] = _stopLossLimitPriceController.text;
        }
      }

      final response = await DeltaApi.post('/v2/orders', payload);

      ShowDialogs.dismissProgressDialog();
      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await doc.set(responseBody);

        Navigator.of(context).pop();
        ShowDialogs.showDialog(title: 'Success', msg: 'Order placed successfully.', type: DialogType.SUCCESS);
      } else {
        ShowDialogs.showDialog(title: 'Error', msg: responseBody['message'] ?? 'Failed to place order.');
      }
    } catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Error', msg: 'An unexpected error occurred.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2827).withOpacity(0.95),
              const Color(0xFF131A19).withOpacity(0.95),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Place Order for ${widget.stock['name']}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              _buildBuySellToggle(),
              const SizedBox(height: 24),
              _buildOrderTypeToggle(),
              const SizedBox(height: 24),
              _buildTextField('Quantity', '0', _quantityController),
              const SizedBox(height: 16),
              if (!_isMarketOrder) ...[
                _buildTextField('Limit Price', '\$ 0.00', _limitPriceController),
                const SizedBox(height: 16),
              ],
              _buildTargetSection(),
              const SizedBox(height: 16),
              _buildStopLossSection(),
              const SizedBox(height: 24),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBuySellToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isBuy = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _isBuy ? const Color(0xFF32F5A3) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _isBuy ? Colors.transparent : Colors.white24),
              ),
              child: Center(child: Text('Buy', style: TextStyle(color: _isBuy ? Colors.black : Colors.white, fontWeight: FontWeight.bold))),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isBuy = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: !_isBuy ? Colors.redAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: !_isBuy ? Colors.transparent : Colors.white24),
              ),
              child: Center(child: Text('Sell', style: TextStyle(color: !_isBuy ? Colors.white : Colors.white, fontWeight: FontWeight.bold))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderTypeToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isMarketOrder = true),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _isMarketOrder ? const Color(0xFF2B403F) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: Text('Market Order', style: TextStyle(color: _isMarketOrder ? Colors.white : Colors.white70, fontWeight: FontWeight.bold))),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _isMarketOrder = false),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: !_isMarketOrder ? const Color(0xFF2B403F) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(child: Text('Limit Order', style: TextStyle(color: !_isMarketOrder ? Colors.white : Colors.white70, fontWeight: FontWeight.bold))),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF131A19),
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF32F5A3))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Target Trigger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Switch(
              value: _targetTriggerEnabled,
              onChanged: (value) => setState(() => _targetTriggerEnabled = value),
              activeTrackColor: const Color(0xFF32F5A3),
              activeColor: Colors.white,
            ),
          ],
        ),
        if (_targetTriggerEnabled) ...[
          const SizedBox(height: 16),
          _buildTextField('Target Trigger Price', '\$ 0.00', _targetTriggerPriceController),
          const SizedBox(height: 16),
          _buildTextField('Target Limit Price', '\$ 0.00', _targetLimitPriceController),
        ],
      ],
    );
  }

  Widget _buildStopLossSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Stop Loss', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            Switch(
              value: _stopLossEnabled,
              onChanged: (value) => setState(() => _stopLossEnabled = value),
              activeTrackColor: const Color(0xFF32F5A3),
              activeColor: Colors.white,
            ),
          ],
        ),
        if (_stopLossEnabled) ...[
          const SizedBox(height: 16),
          _buildTextField('Stop Loss Trigger Price', '\$ 0.00', _stopLossTriggerPriceController),
          const SizedBox(height: 16),
          _buildTextField('Stop Loss Limit Price', '\$ 0.00', _stopLossLimitPriceController),
        ],
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Colors.white24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _placeOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF32F5A3),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Place Order', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}
