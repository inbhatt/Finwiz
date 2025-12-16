
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ListItem extends ChangeNotifier{
  DocumentSnapshot? document;
  Map<String, dynamic>? map;
  var extras = <String, dynamic>{}.obs;

  Color? backColor, textColorBold, textColor;

  ListItem(this.document, this.map, [this.backColor = Colors.white, this.textColorBold = Colors.black, this.textColor = Colors.black54]);

  getValue(String field, [bool? asString = false]){
    Map<String, Object?> newMap = document != null ? document!.data() as Map<String, Object?> : map!;
    if (asString!){
      if (newMap[field] != null){
        return newMap[field].toString();
      }else{
        return "";
      }
    }else{
      return newMap[field];
    }
  }
}