import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:flutter/material.dart';

class PlaceOrderPage extends StatefulWidget {
  final Map<String, dynamic> stock;
  final bool isBuy;
  final ValueNotifier<double> priceNotifier;
  final double accountBalance;

  final Map<String, dynamic>? existingOrder;
  final Map<String, dynamic>? existingTpOrder;
  final Map<String, dynamic>? existingSlOrder;

  final String? initialTargetPrice;
  final String? initialStopLossPrice;
  final bool isPositionMode;

  const PlaceOrderPage({
    Key? key,
    required this.stock,
    required this.isBuy,
    required this.priceNotifier,
    required this.accountBalance,
    this.existingOrder,
    this.existingTpOrder,
    this.existingSlOrder,
    this.initialTargetPrice,
    this.initialStopLossPrice,
    this.isPositionMode = false,
  }) : super(key: key);

  @override
  _PlaceOrderPageState createState() => _PlaceOrderPageState();
}

enum CalculationMode { price, percentage, fixedMoney }

class _PlaceOrderPageState extends State<PlaceOrderPage> {
  late bool _isBuy;
  bool _isMarketOrder = true;
  bool _isEditMode = false;

  bool _stopLossEnabled = false;
  bool _targetTriggerEnabled = false;
  bool _isTrailingSlEnabled = false;

  // NEW: Track if the parent order already has a bracket attached
  bool _hasExistingBracket = false;

  CalculationMode _selectedMode = CalculationMode.price;

  final _quantityController = TextEditingController(text: "1");
  final _limitPriceController = TextEditingController();

  final _targetTriggerPriceController = TextEditingController();
  final _targetLimitPriceController = TextEditingController();
  final _targetInputController = TextEditingController();

  final _stopLossTriggerPriceController = TextEditingController();
  final _stopLossLimitPriceController = TextEditingController();
  final _stopLossInputController = TextEditingController();

  double _currentLtp = 0.0;
  final double _usdToInr = 85.0;
  final double _contractMultiplier = 0.001;
  final double _marketOrderBrokeragePoints = 120.0;
  final double _limitOrderBrokeragePoints = 80.0;

  String _targetInfoText = "";
  String _stopLossInfoText = "";

  @override
  void initState() {
    super.initState();
    _isBuy = widget.isBuy;
    _currentLtp = widget.priceNotifier.value;

    if (widget.existingOrder != null || widget.isPositionMode) {
      _isEditMode = true;
      if (widget.existingOrder != null) {
        _quantityController.text = widget.existingOrder!['size'].toString().replaceAll('-', '');
        if (widget.isPositionMode) {
          double size = double.tryParse(widget.existingOrder!['size'].toString()) ?? 0;
          _isBuy = size > 0;
        } else {
          _isBuy = widget.existingOrder!['side'] == 'buy';
        }

        if (!widget.isPositionMode) {
          if (widget.existingOrder!['order_type'] == 'limit_order') {
            _isMarketOrder = false;
            _limitPriceController.text = widget.existingOrder!['limit_price'] ?? '0.0';
          } else {
            _isMarketOrder = true;
          }
        }

        // --- NEW: Detect Existing Bracket on Parent Order ---
        if (widget.existingOrder!.containsKey('bracket_take_profit_price') ||
            widget.existingOrder!.containsKey('bracket_stop_loss_price') ||
            widget.existingOrder!.containsKey('bracket_trail_amount')) {

          // Check if values are actually set (not null)
          if (widget.existingOrder!['bracket_take_profit_price'] != null ||
              widget.existingOrder!['bracket_stop_loss_price'] != null ||
              widget.existingOrder!['bracket_trail_amount'] != null) {
            _hasExistingBracket = true;
          }
        }
      }

      if (widget.initialTargetPrice != null && widget.initialTargetPrice != '-' && widget.initialTargetPrice != 'N/A') {
        _targetTriggerEnabled = true;
        _targetTriggerPriceController.text = widget.initialTargetPrice!;
      }

      // Check for Independent Trailing Order
      if (widget.existingSlOrder != null && widget.existingSlOrder!['order_type'] == 'trailing_stop_loss_order') {
        _stopLossEnabled = true;
        _isTrailingSlEnabled = true;
        _stopLossTriggerPriceController.text = widget.existingSlOrder!['trail_amount'].toString();
      }
      // Check for Attached Bracket Trailing
      else if (widget.existingOrder != null && widget.existingOrder!['bracket_trail_amount'] != null) {
        _stopLossEnabled = true;
        _isTrailingSlEnabled = true;
        _stopLossTriggerPriceController.text = widget.existingOrder!['bracket_trail_amount'].toString();
      }
      // Standard Stop Loss
      else if (widget.initialStopLossPrice != null && widget.initialStopLossPrice != '-' && widget.initialStopLossPrice != 'N/A') {
        _stopLossEnabled = true;
        _stopLossTriggerPriceController.text = widget.initialStopLossPrice!;
      }
    }

    widget.priceNotifier.addListener(_onPriceUpdate);

    _targetInputController.addListener(() => _calculateTargetPrice(fromInput: true));
    _stopLossInputController.addListener(() => _calculateStopLossPrice(fromInput: true));

    _targetTriggerPriceController.addListener(() => _calculateTargetPnL());
    _stopLossTriggerPriceController.addListener(() => _calculateStopLossPnL());

    _quantityController.addListener(_recalculateAll);
    _limitPriceController.addListener(_recalculateAll);
  }

  @override
  void dispose() {
    widget.priceNotifier.removeListener(_onPriceUpdate);
    _quantityController.dispose();
    _limitPriceController.dispose();
    _targetTriggerPriceController.dispose();
    _targetLimitPriceController.dispose();
    _targetInputController.dispose();
    _stopLossTriggerPriceController.dispose();
    _stopLossLimitPriceController.dispose();
    _stopLossInputController.dispose();
    super.dispose();
  }

  void _onPriceUpdate() {
    if (!mounted) return;
    setState(() {
      _currentLtp = widget.priceNotifier.value;
    });
    if (_isMarketOrder) _recalculateAll();
  }

  void _recalculateAll() {
    if (_targetTriggerEnabled) {
      if (_selectedMode == CalculationMode.price)
        _calculateTargetPnL();
      else
        _calculateTargetPrice(fromInput: false);
    }
    if (_stopLossEnabled && !_isTrailingSlEnabled) {
      if (_selectedMode == CalculationMode.price)
        _calculateStopLossPnL();
      else
        _calculateStopLossPrice(fromInput: false);
    }
  }

  double get _basePrice {
    if (widget.isPositionMode && widget.existingOrder != null) {
      return double.tryParse(widget.existingOrder!['entry_price'].toString()) ??
          _currentLtp;
    }
    if (_isMarketOrder) return _currentLtp > 0 ? _currentLtp : 0.0;
    return double.tryParse(_limitPriceController.text) ?? _currentLtp;
  }

  double get _quantity => double.tryParse(_quantityController.text) ?? 0.0;

  // --- Calculations ---
  void _calculateTargetPrice({required bool fromInput}) {
    if (_selectedMode == CalculationMode.price || !_targetTriggerEnabled)
      return;
    if (_basePrice <= 0) return;
    double inputVal = double.tryParse(_targetInputController.text) ?? 0.0;
    if (inputVal <= 0 || _quantity <= 0) {
      if (fromInput) setState(() => _targetInfoText = "");
      return;
    }
    double netProfitInr = 0.0;
    if (_selectedMode == CalculationMode.percentage) {
      double capitalInr = widget.accountBalance * _usdToInr;
      netProfitInr = capitalInr * (inputVal / 100);
    } else if (_selectedMode == CalculationMode.fixedMoney) {
      netProfitInr = inputVal;
    }
    double valPerPointInr = 1.0 * _quantity * _contractMultiplier * _usdToInr;
    double netPointsNeeded = netProfitInr / valPerPointInr;
    double brokeragePoints = _isMarketOrder
        ? _marketOrderBrokeragePoints
        : _limitOrderBrokeragePoints;
    double totalPoints = netPointsNeeded + brokeragePoints;
    double calculatedPrice = _isBuy
        ? (_basePrice + totalPoints)
        : (_basePrice - totalPoints);
    String newText = Utils.round(
      2,
      num: calculatedPrice,
      getAsDouble: false,
    ).toString();
    if (_targetTriggerPriceController.text != newText) {
      _targetTriggerPriceController.text = newText;
    }
  }

  void _calculateTargetPnL() {
    if (!_targetTriggerEnabled) return;
    double triggerPrice =
        double.tryParse(_targetTriggerPriceController.text) ?? 0.0;
    if (triggerPrice <= 0 || _quantity <= 0 || _basePrice <= 0) {
      setState(() => _targetInfoText = "");
      return;
    }
    double grossPoints = _isBuy
        ? (triggerPrice - _basePrice)
        : (_basePrice - triggerPrice);
    double grossPnlUsd = grossPoints * _quantity * _contractMultiplier;
    double grossPnlInr = grossPnlUsd * _usdToInr;
    double brokeragePoints = _isMarketOrder
        ? _marketOrderBrokeragePoints
        : _limitOrderBrokeragePoints;
    double brokerageCostInr =
        brokeragePoints * _quantity * _contractMultiplier * _usdToInr;
    double netPnlInr = grossPnlInr - brokerageCostInr;
    double netPnlPercent = (widget.accountBalance > 0)
        ? (netPnlInr / (_usdToInr * widget.accountBalance)) * 100
        : 0.0;
    setState(() {
      _targetInfoText =
          "Net: ₹${Utils.round(2, num: netPnlInr, getAsDouble: false)} (${Utils.round(2, num: netPnlPercent, getAsDouble: false)}%)";
    });
  }

  void _calculateStopLossPrice({required bool fromInput}) {
    if (_isTrailingSlEnabled) return;
    if (_selectedMode == CalculationMode.price || !_stopLossEnabled) return;
    if (_basePrice <= 0) return;
    double inputVal = double.tryParse(_stopLossInputController.text) ?? 0.0;
    if (inputVal <= 0 || _quantity <= 0) {
      if (fromInput) setState(() => _stopLossInfoText = "");
      return;
    }
    double maxNetLossInr = 0.0;
    if (_selectedMode == CalculationMode.percentage) {
      double capitalInr = widget.accountBalance * _usdToInr;
      maxNetLossInr = capitalInr * (inputVal / 100);
    } else if (_selectedMode == CalculationMode.fixedMoney) {
      maxNetLossInr = inputVal;
    }
    double valPerPointInr = 1.0 * _quantity * _contractMultiplier * _usdToInr;
    double brokeragePoints = _isMarketOrder
        ? _marketOrderBrokeragePoints
        : _limitOrderBrokeragePoints;
    double brokerageCostInr = brokeragePoints * valPerPointInr;
    double allowedPriceLossInr = maxNetLossInr - brokerageCostInr;
    if (allowedPriceLossInr < 0) allowedPriceLossInr = 0;
    double pointsAllowed = allowedPriceLossInr / valPerPointInr;
    double calculatedPrice = _isBuy
        ? (_basePrice - pointsAllowed)
        : (_basePrice + pointsAllowed);
    String newText = Utils.round(
      2,
      num: calculatedPrice,
      getAsDouble: false,
    ).toString();
    if (_stopLossTriggerPriceController.text != newText) {
      _stopLossTriggerPriceController.text = newText;
    }
  }

  void _calculateStopLossPnL() {
    if (_isTrailingSlEnabled) {
      setState(
        () => _stopLossInfoText =
            "Trailing by: ${_stopLossTriggerPriceController.text}",
      );
      return;
    }
    if (!_stopLossEnabled) return;
    double triggerPrice =
        double.tryParse(_stopLossTriggerPriceController.text) ?? 0.0;
    if (triggerPrice <= 0 || _quantity <= 0 || _basePrice <= 0) {
      setState(() => _stopLossInfoText = "");
      return;
    }
    double grossPoints = _isBuy
        ? (triggerPrice - _basePrice)
        : (_basePrice - triggerPrice);
    double grossPnlUsd = grossPoints * _quantity * _contractMultiplier;
    double grossPnlInr = grossPnlUsd * _usdToInr;
    double brokeragePoints = _isMarketOrder
        ? _marketOrderBrokeragePoints
        : _limitOrderBrokeragePoints;
    double brokerageCostInr =
        brokeragePoints * _quantity * _contractMultiplier * _usdToInr;
    double netPnlInr = grossPnlInr - brokerageCostInr;
    double netPnlPercent = (widget.accountBalance > 0)
        ? (netPnlInr / (_usdToInr * widget.accountBalance)) * 100
        : 0.0;
    setState(() {
      _stopLossInfoText =
          "Net Loss: ₹${Utils.round(2, num: netPnlInr.abs(), getAsDouble: false)} (${Utils.round(2, num: netPnlPercent.abs(), getAsDouble: false)}%)";
    });
  }

  /// --- LOGIC: Independent Order Handling (Position Mode) ---
  Future<void> _handleIndependentOrder({
    required Map<String, dynamic>? existingOrder,
    required bool isEnabled,
    required String value, // Price OR Trail Amount
    required String type,
    bool isTrailing = false,
  }) async {
    if (isEnabled && existingOrder != null) {
      // 1. Check for Type Mismatch (Standard vs Trailing)
      // Delta cannot change type via PUT. Must cancel and create new.
      bool typeMismatch = false;
      if (isTrailing &&
          existingOrder['order_type'] != 'trailing_stop_loss_order')
        typeMismatch = true;
      if (!isTrailing &&
          existingOrder['order_type'] == 'trailing_stop_loss_order')
        typeMismatch = true;

      if (typeMismatch) {
        await DeltaApi.delete('/v2/orders', {
          'id': existingOrder['id'].toString(),
          'product_id': int.parse(widget.stock['code'].toString()),
        });
        // Recursively create new
        await _handleIndependentOrder(
          existingOrder: null,
          isEnabled: true,
          value: value,
          type: type,
          isTrailing: isTrailing,
        );
        return;
      }

      // 2. Normal Update
      final payload = {
        'id': int.parse(existingOrder['id'].toString()),
        'product_id': widget.stock['code'],
        'size': int.tryParse(_quantityController.text) ?? 0,
      };

      if (isTrailing) {
        payload['trail_amount'] = value;
      } else {
        if (existingOrder['order_type'] == 'limit_order')
          payload['limit_price'] = value;
        else
          payload['stop_price'] = value;
      }

      await DeltaApi.put('/v2/orders', payload);
    } else if (isEnabled && existingOrder == null) {
      // 3. CREATE NEW INDEPENDENT ORDER (Attach to Position via reduce_only)
      final payload = {
        'product_id': widget.stock['code'],
        'size': int.tryParse(_quantityController.text) ?? 0,
        'side': _isBuy ? 'sell' : 'buy', // Opposite of position
        'reduce_only': true,
        'stop_order_type': type == 'take_profit'
            ? 'take_profit_order'
            : 'stop_loss_order',
      };

      if (isTrailing) {
        payload['order_type'] = 'trailing_stop_loss_order';
        payload['trail_amount'] = value;
      } else {
        payload['order_type'] = 'market_order'; // Stop Market
        payload['stop_price'] = value;
      }

      await DeltaApi.post('/v2/orders', payload);
    } else if (!isEnabled && existingOrder != null) {
      // 4. CANCEL EXISTING
      final payload = {
        'id': existingOrder['id'].toString(),
        'product_id': int.parse(widget.stock['code'].toString()),
      };
      await DeltaApi.delete('/v2/orders', payload);
    }
  }

  Future<void> _placeOrder() async {
    ShowDialogs.showProgressDialog();
    try {
      final doc = widget.existingOrder != null && !widget.isPositionMode
          ? DBUtils.userDoc.reference.collection("ORDERS").doc(widget.existingOrder!['client_order_id'])
          : DBUtils.userDoc.reference.collection("ORDERS").doc();

      // ============================================================
      // 1. POSITION MODE
      // ============================================================
      if (widget.isPositionMode) {
        // A. If Independent Bracket Orders exist, manage them (Fallback/Standard)
        if (widget.existingTpOrder != null || widget.existingSlOrder != null) {
          await _handleIndependentOrder(
            existingOrder: widget.existingTpOrder,
            isEnabled: _targetTriggerEnabled,
            value: _targetTriggerPriceController.text,
            type: 'take_profit',
          );
          await _handleIndependentOrder(
            existingOrder: widget.existingSlOrder,
            isEnabled: _stopLossEnabled,
            value: _stopLossTriggerPriceController.text,
            type: 'stop_loss',
            isTrailing: _isTrailingSlEnabled,
          );
        }
        // B. If NO Active Brackets but we have a Parent ID, use ATTACH BRACKET Endpoint
        else if (widget.existingOrder != null && widget.existingOrder!['id'] != null) {
          final bracketPayload = <String, dynamic>{
            'id': int.parse(widget.existingOrder!['id'].toString()),
            'product_id': widget.stock['code'],
            'product_symbol': widget.stock['name'],
            'bracket_stop_trigger_method': 'last_traded_price',
          };
          if (_targetTriggerEnabled) bracketPayload['bracket_take_profit_price'] = _targetTriggerPriceController.text;

          if (_stopLossEnabled) {
            if (_isTrailingSlEnabled) {
              bracketPayload['bracket_trail_amount'] = _stopLossTriggerPriceController.text;
            } else {
              bracketPayload['bracket_stop_loss_price'] = _stopLossTriggerPriceController.text;
            }
          }
          var response = await DeltaApi.put('/v2/orders/bracket', bracketPayload);
          var data = jsonDecode(response.body);
          if (response.statusCode == 200){}
        }
        else {
          // No Parent ID and No Active Brackets? Force Independent Orders (Create New)
          await _handleIndependentOrder(existingOrder: null, isEnabled: _targetTriggerEnabled, value: _targetTriggerPriceController.text, type: 'take_profit');
          await _handleIndependentOrder(existingOrder: null, isEnabled: _stopLossEnabled, value: _stopLossTriggerPriceController.text, type: 'stop_loss', isTrailing: _isTrailingSlEnabled);
        }

        ShowDialogs.dismissProgressDialog();
        if (mounted) Navigator.of(context).pop();
        ShowDialogs.showDialog(title: 'Success', msg: 'Brackets updated successfully.', type: DialogType.SUCCESS);
        return;
      }

      // ============================================================
      // 2. ORDER EDIT MODE
      // ============================================================
      if (_isEditMode && !widget.isPositionMode) {
        final updatePayload = {
          'id': int.parse(widget.existingOrder!['id'].toString()),
          'product_id': widget.stock['code'],
          'size': int.tryParse(_quantityController.text) ?? 0,
        };
        if (!_isMarketOrder) updatePayload['limit_price'] = _limitPriceController.text;

        final response = await DeltaApi.put('/v2/orders', updatePayload);
        if (response.statusCode != 200) {
          ShowDialogs.dismissProgressDialog();
          ShowDialogs.showDialog(title: 'Error', msg: 'Failed to update order.');
          return;
        }

        if (_targetTriggerEnabled || _stopLossEnabled) {
          final bracketPayload = <String, dynamic>{
            'id': int.parse(widget.existingOrder!['id'].toString()),
            'product_id': widget.stock['code'],
            'product_symbol': widget.stock['name'],
            'bracket_stop_trigger_method': 'last_traded_price',
          };
          if (_targetTriggerEnabled) bracketPayload['bracket_take_profit_price'] = _targetTriggerPriceController.text;
          if (_stopLossEnabled) {
            if (_isTrailingSlEnabled) bracketPayload['bracket_trail_amount'] = _stopLossTriggerPriceController.text;
            else bracketPayload['bracket_stop_loss_price'] = _stopLossTriggerPriceController.text;
          }
          await DeltaApi.put('/v2/orders/bracket', bracketPayload);
        }

        ShowDialogs.dismissProgressDialog();
        if (mounted) Navigator.of(context).pop();
        ShowDialogs.showDialog(title: 'Success', msg: 'Order updated.', type: DialogType.SUCCESS);
        return;
      }

      // ============================================================
      // 3. NEW ORDER MODE
      // ============================================================
      final payload = <String, dynamic>{
        'product_id': widget.stock['code'],
        'product_symbol': widget.stock['name'],
        'side': _isBuy ? 'buy' : 'sell',
        'order_type': _isMarketOrder ? 'market_order' : 'limit_order',
        'size': int.tryParse(_quantityController.text) ?? 0,
        'client_order_id': doc.id,
      };

      if (!_isMarketOrder) payload['limit_price'] = _limitPriceController.text;

      if (_targetTriggerEnabled || _stopLossEnabled) {
        payload['bracket_stop_trigger_method'] = 'last_traded_price';
      }

      if (_targetTriggerEnabled) {
        payload['bracket_take_profit_price'] = _targetTriggerPriceController.text;
      }

      if (_stopLossEnabled) {
        if (_isTrailingSlEnabled) {
          // SEND TRAIL AMOUNT
          payload['bracket_trail_amount'] = _stopLossTriggerPriceController.text;
        } else {
          // SEND STOP PRICE
          payload['bracket_stop_loss_price'] = _stopLossTriggerPriceController.text;
        }
      }

      final response = await DeltaApi.post('/v2/orders', payload);
      ShowDialogs.dismissProgressDialog();
      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await doc.set(responseBody);
        if (mounted) {
          Navigator.of(context).pop();
          ShowDialogs.showDialog(title: 'Success', msg: 'Order placed successfully.', type: DialogType.SUCCESS);
        }
      } else {
        if (mounted) ShowDialogs.showDialog(title: 'Error', msg: responseBody['message'] ?? 'Failed to place order.');
      }
    } catch (e) {
      if (mounted) {
        ShowDialogs.dismissProgressDialog();
        ShowDialogs.showDialog(title: 'Error', msg: 'An error occurred: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E2827).withOpacity(0.98),
              const Color(0xFF131A19).withOpacity(0.98),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditMode
                        ? 'Edit Order'
                        : 'Place Order: ${widget.stock['name']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Bal: ",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            "\$${Utils.round(2, num: widget.accountBalance)}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Text(
                            "LTP: ",
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                          Text(
                            "\$${_currentLtp.toStringAsFixed(2)}",
                            style: const TextStyle(
                              color: Color(0xFF32F5A3),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (!_isEditMode && !widget.isPositionMode) _buildBuySellToggle(),
              const SizedBox(height: 24),
              if (!widget.isPositionMode) _buildOrderTypeToggle(),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: widget.isPositionMode
                        ? _buildReadOnlyField(
                            'Position Size',
                            _quantityController.text,
                          )
                        : _buildTextField('Quantity', '0', _quantityController),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: (widget.isPositionMode || _isMarketOrder)
                        ? _buildReadOnlyField(
                            widget.isPositionMode ? 'Avg Entry' : 'Price',
                            widget.isPositionMode
                                ? Utils.round(2, num: _basePrice).toString()
                                : 'Market',
                          )
                        : _buildTextField(
                            'Limit Price',
                            '0.0',
                            _limitPriceController,
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'Bracket Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildModeSelector(),
              const SizedBox(height: 16),
              _buildTargetSection(),
              const SizedBox(height: 16),
              _buildTrailingStopLossSection(),
              const SizedBox(height: 24),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrailingStopLossSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Stop Loss',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                const Text(
                  "Trailing",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Checkbox(
                  value: _isTrailingSlEnabled,
                  onChanged: (v) => setState(() {
                    _isTrailingSlEnabled = v ?? false;
                    _stopLossEnabled = _isTrailingSlEnabled;
                    if (_isTrailingSlEnabled) {
                      _stopLossTriggerPriceController.clear();
                      _stopLossInputController.clear();
                    }
                  }),
                  activeColor: const Color(0xFF32F5A3),
                  checkColor: Colors.black,
                ),
                Switch(
                  value: _stopLossEnabled,
                  onChanged: (value) => setState(() {
                    _stopLossEnabled = value;
                    if (!value) _isTrailingSlEnabled = false;
                  }),
                  activeTrackColor: const Color(0xFF32F5A3),
                  activeColor: Colors.white,
                ),
              ],
            ),
          ],
        ),
        if (_stopLossEnabled) ...[
          const SizedBox(height: 8),
          if (_isTrailingSlEnabled)
            _buildTextField(
              'Trail Amount',
              '0.0',
              _stopLossTriggerPriceController,
            )
          else if (_selectedMode == CalculationMode.price) ...[
            _buildTextField(
              'Trigger Price',
              '0.0',
              _stopLossTriggerPriceController,
            ),
            if (_stopLossInfoText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                child: Text(
                  _stopLossInfoText,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    _selectedMode == CalculationMode.percentage
                        ? 'Stop Loss %'
                        : 'Stop Loss ₹',
                    '0',
                    _stopLossInputController,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadOnlyField(
                    'Price',
                    _stopLossTriggerPriceController.text,
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  // ... (Keep existing Widgets) ...
  Widget _buildModeSelector() {
    return ToggleButtons(
      isSelected: [
        _selectedMode == CalculationMode.price,
        _selectedMode == CalculationMode.percentage,
        _selectedMode == CalculationMode.fixedMoney,
      ],
      onPressed: (index) {
        setState(() {
          _selectedMode = CalculationMode.values[index];
          _targetInputController.clear();
          _stopLossInputController.clear();
          _targetInfoText = "";
          _stopLossInfoText = "";
        });
      },
      borderRadius: BorderRadius.circular(8),
      selectedColor: Colors.black,
      fillColor: const Color(0xFF32F5A3),
      color: Colors.white70,
      constraints: const BoxConstraints(minHeight: 36, minWidth: 80),
      children: const [Text("Price"), Text("% ROI"), Text("Fixed ₹")],
    );
  }

  Widget _buildTargetSection() {
    String label = _selectedMode == CalculationMode.price
        ? 'Target Price'
        : _selectedMode == CalculationMode.percentage
        ? 'Target %'
        : 'Target ₹';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Take Profit',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Switch(
              value: _targetTriggerEnabled,
              onChanged: (value) =>
                  setState(() => _targetTriggerEnabled = value),
              activeTrackColor: const Color(0xFF32F5A3),
              activeColor: Colors.white,
            ),
          ],
        ),
        if (_targetTriggerEnabled) ...[
          const SizedBox(height: 8),
          if (_selectedMode == CalculationMode.price) ...[
            _buildTextField(
              'Trigger Price',
              '0.0',
              _targetTriggerPriceController,
            ),
            if (_targetInfoText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                child: Text(
                  _targetInfoText,
                  style: const TextStyle(
                    color: Color(0xFF32F5A3),
                    fontSize: 11,
                  ),
                ),
              ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildTextField(label, '0', _targetInputController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadOnlyField(
                    'Price',
                    _targetTriggerPriceController.text,
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _buildStopLossSection() {
    String label = _selectedMode == CalculationMode.price
        ? 'Stop Price'
        : _selectedMode == CalculationMode.percentage
        ? 'Stop Loss %'
        : 'Stop Loss ₹';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Stop Loss',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Switch(
              value: _stopLossEnabled,
              onChanged: (value) => setState(() => _stopLossEnabled = value),
              activeTrackColor: const Color(0xFF32F5A3),
              activeColor: Colors.white,
            ),
          ],
        ),
        if (_stopLossEnabled) ...[
          const SizedBox(height: 8),
          if (_selectedMode == CalculationMode.price) ...[
            _buildTextField(
              'Trigger Price',
              '0.0',
              _stopLossTriggerPriceController,
            ),
            if (_stopLossInfoText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, left: 4.0),
                child: Text(
                  _stopLossInfoText,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
          ] else
            Row(
              children: [
                Expanded(
                  child: _buildTextField(label, '0', _stopLossInputController),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildReadOnlyField(
                    'Price',
                    _stopLossTriggerPriceController.text,
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildBuySellToggle() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _isBuy = true;
              _recalculateAll();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _isBuy ? const Color(0xFF32F5A3) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isBuy ? Colors.transparent : Colors.white24,
                ),
              ),
              child: Center(
                child: Text(
                  'Buy',
                  style: TextStyle(
                    color: _isBuy ? Colors.black : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _isBuy = false;
              _recalculateAll();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: !_isBuy ? Colors.redAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: !_isBuy ? Colors.transparent : Colors.white24,
                ),
              ),
              child: Center(
                child: Text(
                  'Sell',
                  style: TextStyle(
                    color: !_isBuy ? Colors.white : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
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
            onTap: () => setState(() {
              _isMarketOrder = true;
              _recalculateAll();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _isMarketOrder
                    ? const Color(0xFF2B403F)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Market Order',
                  style: TextStyle(
                    color: _isMarketOrder ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _isMarketOrder = false;
              _recalculateAll();
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: !_isMarketOrder
                    ? const Color(0xFF2B403F)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Limit Order',
                  style: TextStyle(
                    color: !_isMarketOrder ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    String label,
    String hint,
    TextEditingController controller,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF131A19),
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF32F5A3)),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _isEditMode ? 'Update' : 'Place Order',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
