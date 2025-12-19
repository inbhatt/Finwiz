import 'package:finwiz/widgets/option_chain_graphs.dart';
import 'package:flutter/material.dart';

class OptionChainWindowScreen extends StatelessWidget {
  final int windowId;
  final Map<String, dynamic> args;

  const OptionChainWindowScreen({
    Key? key,
    required this.windowId,
    required this.args,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Determine symbol from arguments passed during window creation
    final String symbol = args['symbol'] ?? 'BTC';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF131A19),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text("$symbol Option Chain Analysis"),
          backgroundColor: const Color(0xFF1E2827),
          elevation: 0,
        ),
        body: OptionChainGraphs(symbol: symbol),
      ),
    );
  }
}