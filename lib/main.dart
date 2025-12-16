import 'package:finwiz/firebase_options.dart';
import 'package:finwiz/login_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:finwiz/widgets/show_dialogs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  Utils.prefs = await SharedPreferences.getInstance();
  DBUtils.connectDatabase();
  runApp(const MyApp());
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
