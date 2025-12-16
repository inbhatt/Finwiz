import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart';

class Utils{
  static late SharedPreferences prefs;

  static Future<bool> checkInternet() async {
    return InternetConnectionChecker.instance.hasConnection;
  }

  static Future<void> openScreen(Widget page, [Function()? onResume]) async {
    onResume ??= (){};
    String name = page.runtimeType.toString();
    await Navigator.push(ShowDialogs.navState.currentContext!, MaterialPageRoute(builder: (context) => page, settings: RouteSettings(name: name, arguments: {}))).then((val){
      onResume!();
    });
  }

  static openScreenAndClear(Widget page, [Function()? onResume]){
    onResume ??= (){};
    Navigator.of(ShowDialogs.navState.currentContext!).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => page, settings: const RouteSettings(arguments: {})), (Route<dynamic> route) => false).then((val){
      onResume!();
    });
  }

  static closeScreenUntil(Widget page, [dynamic value]){
    String name = page.runtimeType.toString();
    Navigator.popUntil(ShowDialogs.navState.currentContext!, (route) {
      if (route.settings.arguments != null){
        (route.settings.arguments as Map)['result'] = value;
      }
      return route.settings.name == name;
    });
  }

  static String convertDate(String pFormat, {String? cFormat = "yyyy-MM-dd", String? strDate, DateTime? dateTime, Timestamp? timestamp}){
    DateTime date = DateTime.now();
    if (strDate != null){
      date = DateFormat(cFormat).parse(strDate);
    }else if (dateTime != null){
      date = dateTime;
    }else if (timestamp != null){
      date = timestamp.toDate();
    }
    return DateFormat(pFormat).format(date);
  }

  static int daysBetween(DateTime from, DateTime to) {
    from = DateTime(from.year, from.month, from.day);
    to = DateTime(to.year, to.month, to.day);
    return (to.difference(from).inHours / 24).round();
  }

  static int daysBetween30daysMonth(DateTime date1, DateTime date2) {
    if (date1.isAfter(date2)) {
      DateTime temp = date1;
      date1 = date2;
      date2 = temp;
    }

    // Calculate year difference and convert to days (assuming each year has 360 days)
    int yearsDifference = date2.year - date1.year;
    int days = yearsDifference * 360;

    // Calculate month difference and convert to days (assuming each month has 30 days)
    int monthsDifference = date2.month - date1.month;
    days += monthsDifference * 30;

    // Calculate day difference
    int daysDifference = date2.day - date1.day;
    days += daysDifference;

    return days;
  }

  static String modifyDate(String dateStr, String format, {int? days, int? months, int? years,}) {
    DateFormat dateFormat = DateFormat(format);
    DateTime date = dateFormat.parse(dateStr);

    if (days != null) {
      date = date.add(Duration(days: days));
    }

    if (months != null) {
      int newYear = date.year + (months ~/ 12);
      int newMonth = date.month + (months % 12);
      if (newMonth > 12) {
        newYear++;
        newMonth -= 12;
      }
      if (newMonth < 1) {
        newYear--;
        newMonth += 12;
      }
      date = DateTime(newYear, newMonth, date.day);
    }

    if (years != null) {
      date = DateTime(date.year + years, date.month, date.day);
    }

    return dateFormat.format(date);
  }

  static round(int places, {String? s, num? num, bool? getAsDouble = false}){
    if (s == null && num == null){

    }else{
      if (num == null && s != null){
        num = double.parse(s);
      }
      String str = num!.toStringAsFixed(places);
      return getAsDouble! ? double.parse(str) : str;
    }
  }
  static removeZeroesAfterDecimal({String? s, num? num, bool? getAsDouble = false}) {
    if (s == null && num == null){
      return getAsDouble! ? 0 : "0";
    }else{
      if (s == null && num != null){
        s = num.toString();
      }
      if(s!.contains('.')){
        s = s.replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
      }
      return getAsDouble! ? double.parse(s) : s;
    }
  }

  static String getStringInBetween(String str, String start, String end){
    final startIndex = str.indexOf(start);
    final endIndex = str.indexOf(end, startIndex + start.length);

    return str.substring(startIndex + start.length, endIndex);
  }

  static Color hexToColor(String code) {
    return Color(int.parse(code.substring(1, 7), radix: 16) + 0xFF000000);
  }

  static int randomNumber(int min, int max) {
    return (min + Random().nextInt(max - min)).toInt();
  }

  static Future<File?> downloadFromURL(BuildContext context, String url, String savePath) async {
    String path = savePath.endsWith("/") ? savePath : "$savePath/";
    String fileName = basename(url);
    File f = File(path + fileName);
    if (await f.exists()){
      await f.delete();
    }
    await Dio().download(url,
        "$path$fileName");
    return f;
  }
}