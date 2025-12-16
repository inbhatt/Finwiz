import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_dialogs/shared/types.dart';
import 'package:material_dialogs/widgets/dialogs/dialog_widget.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:finwiz/models/list_item.dart';
import 'package:finwiz/utils/utils.dart';
import 'package:finwiz/utils/db_utils.dart';
import 'package:finwiz/widgets/custom_text_field.dart';
import 'package:flutter/material.dart' hide RadioGroup;
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:material_dialogs/widgets/buttons/icon_button.dart';
import 'package:material_dialogs/widgets/buttons/icon_outline_button.dart';

enum DialogType {SUCCESS, ERROR, WARNING, INFO, DELETE}

class ShowDialogs{
  static DialogRoute? progressRoute, percentRoute;
  static BuildContext? alertDialogContext;

  static GlobalKey<NavigatorState> navState = GlobalKey<NavigatorState>();

  static void showProgressDialog([bool? dismissible]){
    if (progressRoute == null || !progressRoute!.isActive){
      var dialog = SpinKitWave(
        size: 40,
        itemCount: 6,
        itemBuilder: (context, index) {
          return const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xFF32F5A3),
            ),
          );
        },
      );
      progressRoute = DialogRoute(
          context: navState.currentContext!,
          builder: (context){
            return PopScope(
              canPop: kDebugMode,
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  width: 150,
                  height: 50,
                  decoration: BoxDecoration(color: const Color(0xFF1E2827), borderRadius: BorderRadius.circular(10)),
                  child: dialog,
                ),
              ),
            );
          }
      );
      Navigator.of(navState.currentContext!).push(progressRoute!);
    }
  }

  static void showPercentDialog(Rx<num> progress){
    if (percentRoute == null || !percentRoute!.isActive){
      var dialog = Obx((){
        return CircularPercentIndicator(
          radius: 25.0,
          lineWidth: 3.0,
          percent: progress / 100,
          center: Text(Utils.round(0, num: progress.value) + "%"),
          backgroundColor: Colors.black12,
          progressColor: Colors.green,
        );
      });
      percentRoute = DialogRoute(
          context: navState.currentContext!,
          builder: (context){
            return PopScope(
              canPop: kDebugMode,
              child: Dialog(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  width: 150,
                  height: 70,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: dialog,
                ),
              ),
            );
          }
      );
      Navigator.of(navState.currentContext!).push(percentRoute!);
    }
  }

  static dismissProgressDialog(){
    if (progressRoute != null && progressRoute!.isActive){
      Navigator.of(navState.currentContext!).removeRoute(progressRoute!);
    }else if (percentRoute != null && percentRoute!.isActive){
      Navigator.of(navState.currentContext!).removeRoute(percentRoute!);
    }
  }

  static showCustomDialog(Widget dialog){
    showGeneralDialog(
      context: navState.currentContext!,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, a1, a2) {
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            width: MediaQuery.of(context).size.height * 0.85,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: dialog,
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        Tween<Offset> tween;
        if (anim.status == AnimationStatus.reverse) {
          tween = Tween(begin: const Offset(-1, 0), end: Offset.zero);
        } else {
          tween = Tween(begin: const Offset(1, 0), end: Offset.zero);
        }

        return SlideTransition(
          position: tween.animate(anim),
          child: FadeTransition(
            opacity: anim,
            child: child,
          ),
        );
      },
    );
  }

  static void showDialog({required String title, required String msg, DialogType? type = DialogType.ERROR, String? posText = "OK", String? negText = "", IconData? posIcon, IconData? negIcon = Icons.cancel_outlined, Function? onPositive, Function? onNegative, bool? dismissible = true}){
    ShowDialogs.dismissProgressDialog();
    List<Widget> buttons = List.empty(growable: true);
    if (negText!.isNotEmpty){
      buttons.add(IconsOutlineButton(
        onPressed: (){
          Navigator.of(navState.currentContext!).pop();
          if (onNegative != null){
            onNegative();
          }
        },
        text: negText,
        iconData: negIcon,
        textStyle: TextStyle(color: Theme.of(navState.currentContext!).textTheme.bodyLarge!.color),
        iconColor: Theme.of(navState.currentContext!).textTheme.bodyLarge!.color,
      ));
    }
    buttons.add(IconsButton(
      onPressed: (){
        Navigator.of(navState.currentContext!).pop();
        if (onPositive != null){
          onPositive();
        }
      },
      text: posText!,
      iconData: posIcon ?? (type == DialogType.SUCCESS ? Icons.check : type == DialogType.ERROR ? Icons.error : type == DialogType.WARNING ? Icons.warning : type == DialogType.INFO ? Icons.info : Icons.delete_forever),
      color: type == DialogType.SUCCESS ? Colors.green : type == DialogType.ERROR ? Colors.red : type == DialogType.WARNING ? Colors.orange : type == DialogType.INFO ? Colors.blue : Colors.red,
      textStyle: const TextStyle(color: Colors.white),
      iconColor: Colors.white,
    ));
    showAlertDialog(title: title, msg: msg, buttons: buttons, barrierDismissible: dismissible);
  }
  static void showAlertDialog({String? title, String? msg, bool? barrierDismissible = false, List<Widget>? buttons}){
    showModalBottomSheet(
      context: navState.currentContext!,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16), topRight: Radius.circular(16))),
      backgroundColor: const Color(0xfffefefe),
      isDismissible: barrierDismissible!,
      builder: (context) => PopScope(
        canPop: false,
        child: DialogWidget(
          title: title,
          msg: msg,
          actions: buttons,
          customViewPosition: CustomViewPosition.BEFORE_TITLE,
          titleStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          msgStyle: const TextStyle(fontSize: 16),
          color: const Color(0xfffefefe),
        ),
      ),
    );
  }

  static showBottomSheet({required Widget widget, bool? isScrollControlled = true, bool? isDismissible = true, Function? onDismiss, ShapeBorder? shape}){
    showModalBottomSheet(
      useRootNavigator: true,
      context: navState.currentContext!,
      isScrollControlled: isScrollControlled!,
      isDismissible: isDismissible!,
      shape: shape,
      builder: (context) {
        return Container(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(navState.currentContext!).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: widget,
                ),
              ],
            ),
          ),
        );
      }
    ).then((value){
      if (onDismiss != null){
        onDismiss();
      }
    });
  }

  static showSingleChoiceDialog({State? state, required String title, required List<String> values, required Function(num choice) onSelected}){
    num selection = -1;
    showBottomSheet(widget: StatefulBuilder(builder: (context, setSheetState) {
      return Container(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Column(
                children: List.generate(values.length, (index) {
                  return RadioListTile<int>(
                    title: Text(values[index], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black),),
                    value: index,               // each radio gets its index as value
                    groupValue: selection as int, // currently selected index
                    onChanged: (value) {
                      setSheetState(() {
                        selection = value!;
                      });
                    },
                  );
                }),
              ),
              SizedBox(height: 20,),
              Align(
                alignment: Alignment.bottomCenter,
                child: ElevatedButton(
                  onPressed: (){
                    if (selection > -1){
                      Navigator.pop(navState.currentContext!);
                      onSelected(selection);
                    }
                  },
                  child: const Text('OK'),
                ),
              ),
            ],
          )
      );
    }), isDismissible: true);
  }
}
