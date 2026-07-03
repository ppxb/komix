import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'config/global/global_setting.dart';
import 'object_box/model.dart';
import 'object_box/object_box.dart';
import 'src/rust/frb_generated.dart';
import 'providers/provider_registry.dart';
import 'pages/main_page.dart';

late final ObjectBox objectbox;
final logger = _KomixLogger();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  objectbox = await ObjectBox.create();
  if (objectbox.userSettingBox.get(1) == null) {
    objectbox.userSettingBox.put(UserSetting());
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProviderRegistry()),
        BlocProvider(create: (_) => GlobalSettingCubit()..initBox()),
      ],
      child: BlocBuilder<GlobalSettingCubit, GlobalSettingState>(
        builder: (context, setting) {
          return MaterialApp(
            title: 'Komix',
            debugShowCheckedModeBanner: false,
            themeMode: setting.themeMode,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: setting.seedColor,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              fontFamily: 'Inter',
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: setting.seedColor,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              fontFamily: 'Inter',
            ),
            home: const MainPage(),
          );
        },
      ),
    );
  }
}

class _KomixLogger {
  void d(Object? message) {
    debugPrint(message?.toString());
  }

  void w(Object? message, {Object? error}) {
    debugPrint(error == null ? message?.toString() : '$message: $error');
  }

  void e(Object? message, {Object? error}) {
    debugPrint(error == null ? message?.toString() : '$message: $error');
  }
}
