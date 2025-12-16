import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:finwiz/home_page.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/utils/delta_api.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:finwiz/widgets/custom_button.dart';
import 'package:finwiz/widgets/custom_text_field.dart';
import 'package:finwiz/widgets/finwiz_logo.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  void _checkAutoLogin() {
    final rememberMe = Utils.prefs.getBool("REM_LOGIN") ?? false;
    if (rememberMe) {
      final mobile = Utils.prefs.getString("MOBILE");
      final password = Utils.prefs.getString("PASS");
      if (mobile != null && password != null) {
        _mobileController.text = mobile;
        _passwordController.text = password;
        setState(() {
          _rememberMe = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _logIn();
        });
      }
    }
  }

  void _logIn() async {
    final mobile = _mobileController.text.trim();
    final password = _passwordController.text.trim();

    if (mobile.isEmpty || password.isEmpty) {
      ShowDialogs.showDialog(title: 'Error', msg: 'Please enter mobile and password');
      return;
    }

    ShowDialogs.showProgressDialog();

    try {
      if (await Utils.checkInternet()) {
        var snapshot = await DBUtils.getData(
            collection: "USERS",
            condition: "MOBILE=TEXT($mobile)",
            showProgress: false,
            dismissProgress: false);

        if (snapshot.querySnapshot != null && snapshot.querySnapshot!.size > 0) {
          DocumentSnapshot document = snapshot.querySnapshot!.docs.first;
          if (document.get("PASS") == password) {
            final paraDoc = await DBUtils.getData(collection: "PARA", document: "1", showProgress: false);
            ShowDialogs.dismissProgressDialog();

            if (paraDoc.documentSnapshot != null && paraDoc.documentSnapshot!.exists) {
              final data = paraDoc.documentSnapshot!.data() as Map<String, dynamic>;
              DeltaApi.apiKey = data['DELTA_API_KEY'];
              DeltaApi.apiSecret = data['DELTA_API_SECRET'];

              Utils.prefs.setBool("REM_LOGIN", _rememberMe);
              if (_rememberMe) {
                Utils.prefs.setString("MOBILE", mobile);
                Utils.prefs.setString("PASS", password);
              } else {
                Utils.prefs.remove("MOBILE");
                Utils.prefs.remove("PASS");
              }

              DBUtils.userDoc = document;
              Utils.openScreen(const HomePage());
            } else {
              ShowDialogs.showDialog(title: "Error", msg: "Failed to load API credentials.");
            }
          } else {
            ShowDialogs.dismissProgressDialog();
            ShowDialogs.showDialog(title: "Error", msg: "Incorrect password");
          }
        } else {
          ShowDialogs.dismissProgressDialog();
          ShowDialogs.showDialog(title: "Error", msg: "Sign up pending for $mobile");
        }
      } else {
        ShowDialogs.dismissProgressDialog();
        ShowDialogs.showDialog(
            title: "No internet",
            msg: "Please connect to internet to login",
            onPositive: () {
              setState(() {});
            });
      }
    } catch (e) {
      ShowDialogs.dismissProgressDialog();
      ShowDialogs.showDialog(title: 'Error', msg: 'An unknown error occurred.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131A19),
      body: Center(
        child: Container(
          padding: const EdgeInsets.all(32.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1E2827).withOpacity(0.9),
                const Color(0xFF131A19).withOpacity(0.9),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          width: 800,
          height: 600,
          child: Row(
            children: [
              // Left side
              const Expanded(
                child: FinwizLogo(),
              ),
              // Right side
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sign In',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Welcome back, please enter your details.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 30),
                    CustomTextField(
                      labelText: 'Mobile',
                      hintText: 'Enter your mobile number',
                      controller: _mobileController,
                    ),
                    const SizedBox(height: 20),
                    CustomTextField(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      obscureText: true,
                      suffixIcon: Icons.visibility_off,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value!;
                                });
                              },
                              checkColor: const Color(0xFF1E2827),
                              fillColor: MaterialStateProperty.resolveWith<Color>((states) {
                                if (states.contains(MaterialState.selected)) {
                                  return const Color(0xFF32F5A3);
                                }
                                return Colors.transparent;
                              }),
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                            Text(
                              'Remember me',
                              style: TextStyle(color: Colors.white.withOpacity(0.7)),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () {},
                          child: const Text(
                            'Forgot Password?',
                            style: TextStyle(color: Color(0xFF32F5A3)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    CustomButton(
                      text: 'Login',
                      onPressed: _logIn,
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(color: Colors.white.withOpacity(0.7)),
                        ),
                        TextButton(
                          onPressed: () {},
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(color: Color(0xFF32F5A3)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
