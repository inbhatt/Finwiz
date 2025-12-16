import 'dart:convert';
import 'dart:io' show Platform;

import 'package:async/async.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:finwiz/utils/custom_snapshot.dart';
import 'package:finwiz/utils/storage_utils.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:finwiz/widgets/show_dialogs.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class DBUtils {
  static late FirebaseFirestore db;
  static late FirebaseFunctions functions;

  static late DocumentSnapshot userDoc, paraDoc;

  static String documentID = "__name__";

  static Future<void> connectDatabase({bool? forceDef = false, DocumentSnapshot? doc, String? docId = ""}) async {
    db = FirebaseFirestore.instance;
    functions = FirebaseFunctions.instanceFor(app: Firebase.app(), region: "asia-south1");
    StorageUtils.storage = FirebaseStorage.instance.ref();
  }

  static Future<CustomSnapshot> getData(
      {required String collection,
      String? document = "",
      String? condition = "",
      String? order = "",
      bool? isGroup = false,
      int? limit = -1,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    var snapshots = await getMultipleData(
        collections: [collection],
        documents: [document!],
        conditions: [condition!],
        orders: [order!],
        isGroups: [isGroup!],
        limits: [limit!],
        showProgress: showProgress,
        dismissProgress: dismissProgress);
    return snapshots[0];
  }

  static Future<List<CustomSnapshot>> getMultipleData(
      {required List<String> collections,
      required List<String>? documents,
      required List<String>? conditions,
      List<String>? orders,
      List<bool>? isGroups,
      List<int>? limits,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    limits ??= List.filled(collections.length, -1, growable: true);

    if (showProgress!) {
      ShowDialogs.showProgressDialog();
    }
    if (documents == null || documents.length != collections.length) {
      documents = List.filled(collections.length, "");
    }
    if (conditions == null || conditions.length != collections.length) {
      conditions = List.filled(collections.length, "");
    }
    if (orders == null || orders.length != collections.length) {
      orders = List.filled(collections.length, "");
    }
    if (isGroups == null || isGroups.length != collections.length) {
      isGroups = List.filled(collections.length, false);
    }
    var futureGroup = FutureGroup();
    for (int i = 0; i < collections.length; i++) {
      String collection = collections[i];
      String document = documents[i];
      String condition = conditions[i];
      String order = orders[i];
      bool isGroup = isGroups[i];

      Query? query;
      bool execute = true;

      if (isGroup) {
        query = db.collectionGroup(collection);
      } else {
        if (document.isEmpty) {
          query = db.collection(collection);
        } else {
          execute = false;
          if (collection.isNotEmpty) {
            futureGroup.add(db.collection(collection).doc(document).get());
          }
        }
      }
      if (execute) {
        if (collection.isNotEmpty) {
          query = createConditionQuery(query!, condition, order);
          if (limits[i] > -1) {
            futureGroup.add(query.limit(limits[i]).get());
          } else {
            futureGroup.add(query.get());
          }
        }
      }
    }
    futureGroup.close();
    var list = await futureGroup.future;
    int taskPos = 0;
    List<CustomSnapshot> snapshots = List.empty(growable: true);
    for (int i = 0; i < collections.length; i++) {
      String collection = collections[i];
      if (collection.isEmpty) {
        snapshots.add(CustomSnapshot());
      } else {
        Object object = list[taskPos];
        if (object is QuerySnapshot) {
          snapshots.add(CustomSnapshot(querySnapshot: object));
        } else if (object is DocumentSnapshot) {
          snapshots.add(CustomSnapshot(documentSnapshot: object));
        }
        taskPos++;
      }
    }
    if (showProgress && dismissProgress!) {
      ShowDialogs.dismissProgressDialog();
    }
    return snapshots;
  }

  static Future<String> insertData(
      {required String collection,
      String? id = "",
      required List<String> fields,
      required List<Object?> values,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    var docIds = await insertMultipleData(
        collections: [collection], ids: [id!], fields: [fields], values: [values], showProgress: showProgress, dismissProgress: dismissProgress);
    return docIds[0];
  }

  static Future<List<String>> insertMultipleData(
      {required List<String> collections,
      List<String>? ids,
      required List<List<String>> fields,
      required List<List<Object?>> values,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    ids ??= List.filled(collections.length, "", growable: true);

    if (showProgress!) {
      ShowDialogs.showProgressDialog();
    }
    final List<String> frbDocIds = List.empty(growable: true);
    WriteBatch batch = db.batch();
    for (int i = 0; i < collections.length; i++) {
      String collection = collections[i];
      String id = ids[i];
      List<String> currentFields = fields[i];
      List<Object?> currentValues = values[i];

      DocumentReference docRef;
      if (id.isEmpty) {
        docRef = db.collection(collection).doc();
      } else {
        docRef = db.collection(collection).doc(id);
      }

      frbDocIds.add(docRef.id);
      dynamic data = getDataMap(currentFields, currentValues, docRef: docRef);
      data["USER"] = userDoc.data();

      batch.set(docRef, data, SetOptions(merge: true));
      if (i % 400 == 0) {
        batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    if (showProgress && dismissProgress!) {
      ShowDialogs.dismissProgressDialog();
    }
    return frbDocIds;
  }

  static Future<void> updateData(
      {required String collection,
      String? document = "",
      String? conditions = "",
      bool? isGroup = false,
      required List<String> updateFields,
      required List<Object?> values,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    return await updateMultipleData(
        collections: [collection],
        documents: [document!],
        conditions: [conditions!],
        isGroups: [isGroup!],
        updateFields: [updateFields],
        values: [values],
        showProgress: showProgress,
        dismissProgress: dismissProgress);
  }

  static Future<void> updateMultipleData(
      {required List<String> collections,
      List<String>? documents,
      List<String>? conditions,
      List<bool>? isGroups,
      required List<List<String>> updateFields,
      required List<List<Object?>> values,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    if (showProgress!) {
      ShowDialogs.showProgressDialog();
    }

    documents ??= List.filled(collections.length, "");
    conditions ??= List.filled(collections.length, "");
    isGroups ??= List.filled(collections.length, false);

    var snapshots = await getMultipleData(
        collections: collections, documents: documents, conditions: conditions, isGroups: isGroups, showProgress: showProgress, dismissProgress: dismissProgress);
    WriteBatch batch = db.batch();
    for (int i = 0; i < snapshots.length; i++) {
      CustomSnapshot snapshot = snapshots[i];
      List<String> currentUpdateFields = updateFields[i];
      List<Object?> currentValues = values[i];

      dynamic data = getDataMap(currentUpdateFields, currentValues, docRef: snapshot.documentSnapshot?.reference);

      if (snapshot.documentSnapshot == null) {
        QuerySnapshot querySnapshot = snapshot.querySnapshot!;
        for (DocumentSnapshot document in querySnapshot.docs) {
          batch.set(document.reference, data, SetOptions(merge: true));
        }
      } else if (snapshot.querySnapshot == null) {
        DocumentSnapshot document = snapshot.documentSnapshot!;
        batch.set(document.reference, data, SetOptions(merge: true));
      }
      if (i % 400 == 0) {
        batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    if (showProgress && dismissProgress!) {
      ShowDialogs.dismissProgressDialog();
    }
  }

  static Future<void> deleteData(
      {required String collection, String? id = "", String? conditions = "", bool? isGroup = false, bool? showProgress = true, bool? dismissProgress = true}) async {
    return await deleteMultipleData(
        collections: [collection], ids: [id!], conditions: [conditions!], isGroups: [isGroup!], showProgress: showProgress, dismissProgress: dismissProgress);
  }

  static Future<void> deleteMultipleData(
      {required List<String> collections,
      List<String>? ids,
      List<String>? conditions,
      List<bool>? isGroups,
      bool? showProgress = true,
      bool? dismissProgress = true}) async {
    if (showProgress!) {
      ShowDialogs.showProgressDialog();
    }
    var snapshots = await getMultipleData(
        collections: collections, documents: ids, conditions: conditions, isGroups: isGroups, showProgress: showProgress, dismissProgress: dismissProgress);
    WriteBatch batch = db.batch();
    for (int i = 0; i < snapshots.length; i++) {
      CustomSnapshot snapshot = snapshots[i];
      if (snapshot.documentSnapshot == null) {
        QuerySnapshot querySnapshot = snapshot.querySnapshot!;
        for (DocumentSnapshot document in querySnapshot.docs) {
          if (document.exists) {
            batch.delete(document.reference);
          }
        }
      } else if (snapshot.querySnapshot == null) {
        DocumentSnapshot document = snapshot.documentSnapshot!;
        if (document.exists) {
          batch.delete(document.reference);
        }
      }
      if (i % 400 == 0) {
        batch.commit();
        batch = db.batch();
      }
    }
    await batch.commit();
    if (showProgress && dismissProgress!) {
      ShowDialogs.dismissProgressDialog();
    }
  }

  static deleteCollection(String collection, bool showProgress, bool dismissProgress) async {
    var snapshot = await getData(collection: collection, showProgress: showProgress, dismissProgress: dismissProgress);
    QuerySnapshot querySnapshot = snapshot.querySnapshot!;
    for (DocumentSnapshot document in querySnapshot.docs) {
      document.reference.delete();
    }
  }

  static Future<String> callCloudFunction(String name, Map data) async {
    final url = Uri.parse('https://asia-south1-${Utils.prefs.get("PROJ_ID")}.cloudfunctions.net/$name');

    final headers = {
      'Content-Type': 'application/json',
    };

    final body = jsonEncode(data);

    try {
      final response = await http.post(url, headers: headers, body: body);

      return response.body;
    } catch (e) {
      return "Error";
    }
  }

  static Query createConditionQuery(Query query, String conditions, String orders) {
    List<String> conditionsArr = conditions.split(",");
    List<String> ordersArr = orders.split(",");

    for (String condition in conditionsArr) {
      if (condition.split(" ARRAYAND ").length > 1) {
        List<String> arr = condition.split(" ARRAYAND ");

        List<String> vals = arr[1].split("|");
        List<Object?> values = List.filled(vals.length, Object());

        for (int i = 0; i < vals.length; i++) {
          values[i] = checkDataType(vals[i]);
        }

        query = query.where(arr[0], arrayContains: values);
      } else if (condition.split(" ARRAYOR ").length > 1) {
        List<String> arr = condition.split(" ARRAYOR ");

        List<String> vals = arr[1].split("|");
        List<Object?> values = List.filled(vals.length, Object());

        for (int i = 0; i < vals.length; i++) {
          values[i] = checkDataType(vals[i]);
        }

        query = query.where(arr[0], arrayContainsAny: values);
      } else if (condition.split(" OR ").length > 1) {
        List<String> arr = condition.split(" OR ");

        List<String> vals = arr[1].split("|");
        List<Object?> values = List.filled(vals.length, Object());

        for (int i = 0; i < vals.length; i++) {
          values[i] = checkDataType(vals[i]);
        }

        query = query.where(arr[0], whereIn: values);
      } else if (condition.split(" NOT ").length > 1) {
        List<String> arr = condition.split(" NOT ");

        List<String> vals = arr[1].split("|");
        List<Object?> values = List.filled(vals.length, Object());

        for (int i = 0; i < vals.length; i++) {
          values[i] = checkDataType(vals[i]);
        }

        query = query.where(arr[0], whereNotIn: values);
      } else if (condition.split("!=").length > 1) {
        List<String> arr = condition.split("!=");
        query = query.where(arr[0], isNotEqualTo: checkDataType(arr[1]));
      } else if (condition.split(">=").length > 1) {
        List<String> arr = condition.split(">=");
        query = query.where(arr[0], isGreaterThanOrEqualTo: checkDataType(arr[1]));
      } else if (condition.split("<=").length > 1) {
        List<String> arr = condition.split("<=");
        query = query.where(arr[0], isLessThanOrEqualTo: checkDataType(arr[1]));
      } else if (condition.split(">").length > 1) {
        List<String> arr = condition.split(">");
        query = query.where(arr[0], isGreaterThan: checkDataType(arr[1]));
      } else if (condition.split("<").length > 1) {
        List<String> arr = condition.split("<");
        query = query.where(arr[0], isLessThan: checkDataType(arr[1]));
      } else if (condition.split("=").length > 1) {
        List<String> arr = condition.split("=");
        query = query.where(arr[0], isEqualTo: checkDataType(arr[1]));
      }
    }
    if (orders.isNotEmpty) {
      for (String order in ordersArr) {
        query = query.orderBy(order.split(" ")[0], descending: order.endsWith("DESC"));
      }
    }
    return query;
  }

  static Object? checkDataType(Object? value) {
    try {
      if (value is String) {
        String s = value;
        if (value == "true" || value == "false") {
          return (bool.parse(s));
        } else if (s.contains("DATE(") || s.contains("TIME(")) {
          s = s.substring(s.indexOf("(") + 1);
          s = s.substring(0, s.lastIndexOf(")"));
          String datetime = s.split("|")[0];
          String format = s.split("|")[1];

          return getTimestamp(datetime, format, false);
        } else if (s.contains("TEXT(")) {
          s = s.substring(s.indexOf("(") + 1);
          s = s.substring(0, s.lastIndexOf(")"));

          return s;
        } else {
          return num.parse(s);
        }
      }
      return value;
    } catch (e) {
      return value;
    }
  }

  static Map<String, Object> getDataMap(List<String> fields, List<Object?> values, {DocumentReference? docRef}) {
    dynamic data = <String, Object>{};
    for (int j = 0; j < fields.length; j++) {
      if (values[j] != null && values[j].toString() == "FRBDOCID" && docRef != null) {
        values[j] = docRef.id;
      }
      data[fields[j]] = checkDataType(values[j])!;
    }
    return data;
  }

  static Timestamp getTimestamp([String? date, String? format = "dd-MM-yy", bool? addTime = true]) {
    DateTime currentTime = DateTime.now();
    DateTime formatDate =
        date == null ? DateTime(currentTime.year, currentTime.month, currentTime.day) : DateFormat(format).parse(date);

    if (addTime!) {
      return Timestamp.fromDate(DateTime(formatDate.year, formatDate.month, formatDate.day, currentTime.hour,
          currentTime.minute, currentTime.second, currentTime.millisecond, currentTime.microsecond));
    } else {
      return Timestamp.fromDate(formatDate);
    }
  }

  static DocumentSnapshot? getDocument({required QuerySnapshot snapshot, int? pos = 0}) {
    if (snapshot.size > 0) {
      return snapshot.docs[pos!];
    }
    return null;
  }

  static String getValue({required DocumentSnapshot? doc, required String field, String? defVal = ""}) {
    if (doc != null) {
      dynamic val;
      try {
        val = doc.get(field);
        return val.toString();
      } catch (e) {
        return defVal!;
      }
    }
    return defVal!;
  }

  static dynamic getMapValue({required DocumentSnapshot? doc, required String field, String? mapField = "NAME"}) {
    if (doc != null) {
      dynamic val;
      try {
        val = doc.get(field);
        return val[mapField];
      } catch (e) {
        return "";
      }
    }
    return "";
  }

  static String getDateCondition({required String date1, String? date2, String? format = "dd-MM-yy"}) {
    date2 ??= date1;
    return "DATE>=DATE($date1|$format),DATE<DATE(${Utils.modifyDate(date2, format!, days: 1)}|$format)";
  }

  static Future<void> transferDeletedEntry(
      String mainCollection, String mainDoc, String conditions, List subCollections, [bool? dismissProgress = false]) async {
    List<DocumentSnapshot> docs = [];
    if (mainDoc.isEmpty) {
      var snapshot = await DBUtils.getData(collection: mainCollection, condition: conditions, dismissProgress: false);
      docs.addAll(snapshot.querySnapshot!.docs);
    } else {
      var snapshot = await DBUtils.getData(collection: mainCollection, document: mainDoc, dismissProgress: false);
      docs.add(snapshot.documentSnapshot!);
    }

    for (DocumentSnapshot doc in docs) {
      DocumentReference tDoc = db.collection("${mainCollection}_DEL").doc(doc.id);
      for (String sub in subCollections) {
        QuerySnapshot q = await doc.reference.collection(sub).get();
        for (DocumentSnapshot d in q.docs) {
          Map<String, dynamic> m = d.data() as Map<String, dynamic>;
          m["DEL_DATE"] = getTimestamp();
          String subName = !sub.endsWith("_DEL") ? "${sub}_DEL" : sub;
          tDoc.collection(sub).doc(d.id).set(m, SetOptions(merge: true));
        }
      }
    }
    if (dismissProgress!) {
      ShowDialogs.dismissProgressDialog();
    }
  }
}
