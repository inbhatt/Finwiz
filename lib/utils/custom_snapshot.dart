import 'package:cloud_firestore/cloud_firestore.dart';

class CustomSnapshot{
  QuerySnapshot? querySnapshot;
  DocumentSnapshot? documentSnapshot;

  CustomSnapshot({this.querySnapshot, this.documentSnapshot});
}