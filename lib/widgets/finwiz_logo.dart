import 'package:flutter/material.dart';

class FinwizLogo extends StatelessWidget {
  const FinwizLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              color: const Color(0xFF32F5A3),
            ),
            const SizedBox(width: 5),
            Container(
              width: 20,
              height: 20,
              color: const Color(0xFF32F5A3),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 20,
              height: 20,
              color: const Color(0xFF32F5A3),
            ),
            const SizedBox(width: 5),
            Container(
              width: 20,
              height: 20,
              color: const Color(0xFF32F5A3),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'FinWiz',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Your Secure Gateway to the Market',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
