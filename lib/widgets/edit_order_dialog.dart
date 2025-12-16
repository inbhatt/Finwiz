import 'package:flutter/material.dart';

class EditOrderDialog extends StatefulWidget {
  final Function(String, String) onSave;
  final String? initialTriggerPrice;
  final String? initialLimitPrice;

  const EditOrderDialog({
    Key? key,
    required this.onSave,
    this.initialTriggerPrice,
    this.initialLimitPrice,
  }) : super(key: key);

  @override
  _EditOrderDialogState createState() => _EditOrderDialogState();
}

class _EditOrderDialogState extends State<EditOrderDialog> {
  late final TextEditingController _triggerPriceController;
  late final TextEditingController _limitPriceController;

  @override
  void initState() {
    super.initState();
    _triggerPriceController = TextEditingController(text: widget.initialTriggerPrice ?? '');
    _limitPriceController = TextEditingController(text: widget.initialLimitPrice ?? '');
  }

  @override
  void dispose() {
    _triggerPriceController.dispose();
    _limitPriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E2827),
      title: const Text('Edit Order', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTextField('Trigger Price', _triggerPriceController),
          const SizedBox(height: 16),
          _buildTextField('Limit Price', _limitPriceController),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(
              _triggerPriceController.text,
              _limitPriceController.text,
            );
            Navigator.of(context).pop();
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF32F5A3)),
          child: const Text('Save', style: TextStyle(color: Colors.black)),
        ),
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        filled: true,
        fillColor: const Color(0xFF131A19),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
