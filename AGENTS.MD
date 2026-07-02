# AGENTS.MD

## Verification

- Do not run project verification commands unless the user explicitly asks.
- This includes `flutter run`, `flutter test`, `flutter analyze`, `dart analyze`, `cargo check`, `cargo test`, and Android/Gradle build commands.
- When verification is needed, tell the user which command to run and ask them to share the output.
- Avoid starting Dart/Flutter/Cargo toolchain commands in the background as a substitute for user-run verification.
