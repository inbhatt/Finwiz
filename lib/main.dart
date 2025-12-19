import 'dart:convert';

import 'package:finwiz/firebase_options.dart';
import 'package:finwiz/login_page.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/windows/option_chain_window_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finwiz/widgets/show_dialogs.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  Utils.prefs = await SharedPreferences.getInstance();

  if (args.firstOrNull == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args[2].isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(args[2]) as Map<String, dynamic>;

    // Important: Initialize Firebase for this new window/isolate
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (argument.containsKey('apiKey')) {
      DeltaApi.apiKey = argument['apiKey'];
    }
    if (argument.containsKey('apiSecret')) {
      DeltaApi.apiSecret = argument['apiSecret'];
    }

    Utils.prefs = await SharedPreferences.getInstance();
    await DBUtils.connectDatabase();

    runApp(OptionChainWindowScreen(windowId: windowId, args: argument));
  } else {
    // --- MAIN APP ENTRY POINT ---
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await DBUtils.connectDatabase();

    Utils.prefs = await SharedPreferences.getInstance();

    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: ShowDialogs.navState,
      title: 'Finwiz',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
