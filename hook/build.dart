import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_rust/native_toolchain_rust.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    await RustBuilder(
      assetName: 'src/rust/frb_generated.dart',
      extraCargoEnvironmentVariables: _extraCargoEnvironmentVariables(
        input.config.code,
        input.packageRoot.toFilePath(),
      ),
    ).run(input: input, output: output);
  });
}

Map<String, String> _extraCargoEnvironmentVariables(
  CodeConfig codeConfig,
  String projectRoot,
) {
  if (codeConfig.targetOS == OS.android) {
    return _androidEnvironmentVariables(codeConfig, projectRoot);
  }
  return const <String, String>{};
}

Map<String, String> _androidEnvironmentVariables(
  CodeConfig codeConfig,
  String projectRoot,
) {
  final ndkPath = _findAndroidNdk(projectRoot);
  final llvmBase = p.join(
    ndkPath,
    'toolchains',
    'llvm',
    'prebuilt',
    _hostPlatform(),
  );
  final sysroot = p.join(llvmBase, 'sysroot');
  final ndkTargetTriple = _ndkTargetTriple(codeConfig.targetArchitecture);
  final clangVersion = _detectClangVersion(llvmBase);

  final bindgenArgs = [
    '--sysroot=${sysroot.replaceAll('\\', '/')}',
    '-isystem ${p.join(sysroot, 'usr', 'include').replaceAll('\\', '/')}',
    if (ndkTargetTriple case final target?)
      '-isystem ${p.join(sysroot, 'usr', 'include', target).replaceAll('\\', '/')}',
    if (clangVersion case final version?)
      '-isystem ${p.join(llvmBase, 'lib', 'clang', version, 'include').replaceAll('\\', '/')}',
  ].join(' ');

  return <String, String>{
    'CLANG_PATH': p
        .join(llvmBase, 'bin', 'clang${_exeSuffix()}')
        .replaceAll('\\', '/'),
    'LIBCLANG_PATH': _libClangPath(llvmBase).replaceAll('\\', '/'),
    'BINDGEN_EXTRA_CLANG_ARGS': bindgenArgs,
    'PATH':
        '${p.join(llvmBase, 'bin')}${_pathSep()}${Platform.environment['PATH'] ?? ''}',
  };
}

String _findAndroidNdk(String projectRoot) {
  final envNdk = Platform.environment['ANDROID_NDK_HOME'];
  if (envNdk != null && Directory(envNdk).existsSync()) return envNdk;

  final sdkRoots = <String>[
    ...[
      Platform.environment['ANDROID_SDK_ROOT'],
      Platform.environment['ANDROID_HOME'],
      _readAndroidSdkPath(projectRoot),
    ].whereType<String>(),
  ];

  for (final sdkRoot in sdkRoots) {
    final ndkRoot = Directory(p.join(sdkRoot, 'ndk'));
    if (!ndkRoot.existsSync()) continue;
    final versions = ndkRoot.listSync().whereType<Directory>().toList()
      ..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    if (versions.isNotEmpty) return versions.first.path;
  }

  throw StateError(
    'Cannot find Android NDK. Set ANDROID_NDK_HOME or install an NDK under Android SDK.',
  );
}

String? _readAndroidSdkPath(String projectRoot) {
  final file = File(p.join(projectRoot, 'android', 'local.properties'));
  if (!file.existsSync()) return null;

  for (final line in file.readAsLinesSync()) {
    final index = line.indexOf('=');
    if (index <= 0) continue;
    if (line.substring(0, index).trim() != 'sdk.dir') continue;
    return line.substring(index + 1).trim().replaceAll(r'\\', r'\');
  }

  return null;
}

String _hostPlatform() {
  if (Platform.isWindows) return 'windows-x86_64';
  if (Platform.isMacOS) return 'darwin-x86_64';
  return 'linux-x86_64';
}

String? _ndkTargetTriple(Architecture arch) {
  return switch (arch) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'arm-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    Architecture.ia32 => 'i686-linux-android',
    _ => null,
  };
}

String _libClangPath(String llvmBase) {
  if (Platform.isWindows) return p.join(llvmBase, 'bin');
  final lib64 = Directory(p.join(llvmBase, 'lib64'));
  if (lib64.existsSync()) return lib64.path;
  return p.join(llvmBase, 'lib');
}

String? _detectClangVersion(String llvmBase) {
  final clangDir = Directory(p.join(llvmBase, 'lib', 'clang'));
  if (!clangDir.existsSync()) return null;

  for (final entity in clangDir.listSync()) {
    if (entity is Directory &&
        RegExp(r'^\d+').hasMatch(p.basename(entity.path))) {
      return p.basename(entity.path);
    }
  }

  return null;
}

String _pathSep() => Platform.isWindows ? ';' : ':';

String _exeSuffix() => Platform.isWindows ? '.exe' : '';
