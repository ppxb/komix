import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/global/global.dart';
import '../main.dart';

bool get _isPortableStrategy => Platform.isWindows;

bool get _isStandardDesktop => Platform.isLinux || Platform.isMacOS;

Future<String> getAppDirectory() async {
  if (_isPortableStrategy) {
    return p.dirname(Platform.resolvedExecutable);
  } else if (Platform.isAndroid) {
    final tempDir = await getApplicationSupportDirectory();
    return p.normalize(p.join(tempDir.path, '..'));
  } else {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }
}

Future<String> getDbPath() async {
  String dbDirPath;

  if (_isPortableStrategy) {
    final appDir = await getAppDirectory();
    dbDirPath = p.join(appDir, '..', 'db');
  } else if (Platform.isAndroid) {
    final appDir = await getAppDirectory();
    dbDirPath = p.join(appDir, 'app_flutter');
  } else {
    final appDir = await getAppDirectory();
    dbDirPath = p.join(appDir, 'db');
  }

  await _ensureDirExists(dbDirPath);
  return dbDirPath;
}

Future<String> getFilePath() async {
  final appDir = await getAppDirectory();
  final path = _isPortableStrategy
      ? p.join(appDir, '..', 'files')
      : p.join(appDir, 'files');
  await _ensureDirExists(path);
  return path;
}

Future<String> getCachePath() async {
  if (_isPortableStrategy) {
    final appDir = await getAppDirectory();
    final path = p.join(appDir, '..', 'cache');
    await _ensureDirExists(path);
    return path;
  } else if (_isStandardDesktop) {
    final cacheDir = await getApplicationCacheDirectory();
    await _ensureDirExists(cacheDir.path);
    return cacheDir.path;
  } else {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }
}

Future<String> getDownloadPath() async {
  final fileDir = await getFilePath();
  final downloadPath = p.join(fileDir, 'downloads');
  await _ensureDirExists(downloadPath);
  return downloadPath;
}

Future<File> getLogPath() async {
  String logDirPath;

  if (_isPortableStrategy) {
    final appDir = await getAppDirectory();
    logDirPath = p.join(appDir, '..', 'log');
  } else if (Platform.isAndroid) {
    final docDir = await getApplicationDocumentsDirectory();
    logDirPath = p.join(docDir.path, 'log');
  } else {
    final appDir = await getAppDirectory();
    logDirPath = p.join(appDir, 'log');
  }

  await _ensureDirExists(logDirPath);

  final logFile = File(p.join(logDirPath, 'komix.log'));
  if (!await logFile.exists()) {
    await logFile.create();
  }
  return logFile;
}

Future<String> createDownloadDir() async {
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null) {
        final path = p.join(downloadDir.path, appName);
        await _ensureDirExists(path);
        return path;
      }

      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, 'Downloads', appName);
      }

      final fallbackDir = await getFilePath();
      return p.join(fallbackDir, 'Downloads', appName);
    }

    if (Platform.isAndroid) {
      final savePath = p.join('/storage/emulated/0/Download', appName);
      try {
        await _ensureDirExists(savePath);
        return savePath;
      } catch (_) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          return externalDir.path;
        }
        rethrow;
      }
    }

    final docDir = await getApplicationDocumentsDirectory();
    return docDir.path;
  } catch (error) {
    logger.e('Create download dir failed: $error');
    rethrow;
  }
}

Future<void> _ensureDirExists(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}
