import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String labelText;
  final String hintText;
  final bool obscureText;
  final IconData? suffixIcon;
  final TextEditingController? controller;

  const CustomTextField({
    Key? key,
    required this.labelText,
    required this.hintText,
    this.obscureText = false,
    this.suffixIcon,
    this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2E3D3B).withOpacity(0.8),
                const Color(0xFF1E2827).withOpacity(0.5),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.transparent,
              hintText: hintText,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              suffixIcon: suffixIcon != null
                  ? Icon(
                      suffixIcon,
                      color: Colors.white.withOpacity(0.5),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
