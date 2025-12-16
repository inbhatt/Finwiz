import 'package:finwiz/models/list_item.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class ListController{
  late ItemScrollController controller;
  late GlobalKey<dynamic> globalKey;
  late String id, filterField;

  late List<ListItem> list, filterList;

  late ListItem selectedItem;

  late Widget Function(BuildContext context, int index, ListItem item, Function(void Function())) itemBuilder;

  ListController({ItemScrollController? controller, GlobalKey<dynamic>? globalKey, String? id, String? filterField = "", List<ListItem>? list, List<ListItem>? filterList, ListItem? selectedItem, Color? inverseColor, Color? inverseTextColor, Widget Function(BuildContext context, int index, ListItem item)? itemBuilder}){
    this.controller = controller ?? ItemScrollController();
    this.globalKey = globalKey ?? GlobalKey();
    this.id = id ?? "";
    this.filterField = filterField!;
    this.list = list ?? List.empty(growable: true);
    this.filterList = filterList ?? List.empty(growable: true);


    this.itemBuilder = (itemBuilder ?? (c, i, item, setListState){
      return Container();
    }) as Widget Function(BuildContext context, int index, ListItem item, Function(void Function() p1) p1);
  }

  filter(String searchTerm){
    if (filterField.isNotEmpty){
      filterList = list.where((item) {
        String value = "";
        Map<dynamic, dynamic> data = item.document == null ? item.map! : item.document!.data() as Map<dynamic, dynamic>;
        if (filterField.contains(",")){
          var fields = filterField.split(",");
          for (String s in fields){
            if (s.contains("[")){
              String map = s.substring(0, s.indexOf("["));
              String field = Utils.getStringInBetween(s, "[", "]");
              value += data[map][field];
            }else{
              if (data[s] == null){
                try{
                  value += item.extras[s].toString();
                }catch (e){}
              }else{
                value += data[s].toString();
              }
            }
          }
        }else{
          if (filterField.contains("[")){
            String map = filterField.substring(0, filterField.indexOf("["));
            String field = Utils.getStringInBetween(filterField, "[", "]");
            value += data[map][field];
          }else{
            if (data[filterField] == null){
              try{
                value = item.extras[filterField].toString();
              }catch (e){}
            }else{
              value = data[filterField].toString();
            }
          }
        }

        final nameLower = value.toLowerCase();
        final patternLower = searchTerm.toLowerCase();
        return nameLower.contains(patternLower);
      }).toList();
    }
  }

  add(ListItem item){
    list.add(item);
    filterList.add(item);
  }
  remove(ListItem item){
    list.remove(item);
    filterList.remove(item);
  }
  removeAt(int index){
    list.removeAt(index);
    filterList.removeAt(index);
  }
}