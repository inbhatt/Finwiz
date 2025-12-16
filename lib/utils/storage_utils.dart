import 'dart:io';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:finwiz/utils/utils.dart';

class StorageUtils {
  static late Reference storage;

  static Future<String> upload({required String path, File? file, String? filePath, String? fileName, bool? showProgress = true, int? totalSize}) async {
    if (file == null && filePath != null){
      file = File(filePath);
    }

    final extension = p.extension(file!.path);
    fileName ??= Utils.randomNumber(1000, 10001).toString() + extension;
    totalSize ??= file.lengthSync();
    final ref = storage.child("$path/$fileName");

    var progress = (0 as num).obs;
    UploadTask task = ref.putFile(file);
    task.snapshotEvents.listen((taskSnapshot) async {
      switch (taskSnapshot.state) {
        case TaskState.running:
          if (showProgress!){
            progress.value = 100 * (taskSnapshot.bytesTransferred / totalSize!);
          }
          break;
        case TaskState.paused:
          break;
        case TaskState.success:
          break;
        case TaskState.canceled:
          break;
        case TaskState.error:
          break;
      }
    });
    await task;
    return await ref.getDownloadURL();
  }
  static Future<List<String>> uploadFiles(String path, {List<File>? files, List<String?>? filePaths, bool? showProgress = true}) async {
    int totalSize = 0;
    if (files == null && filePaths != null){
      files = List.empty(growable: true);
      for (String? filePath in filePaths){
        if (filePath != null){
          File f = File(filePath);
          files.add(f);
          totalSize += f.lengthSync();
        }
      }
    }
    var paths = await Future.wait(files!.map((file) => upload(path: path, file: file, totalSize: totalSize, showProgress: showProgress)));
    List<String> list = [];
    for (String s in paths){
      list.add(s);
    }
    return list;
  }
}
