# AGENTS.MD

## Project Direction

- Komix uses internal maintained providers for multiple comic sources; do not introduce Breeze's plugin/QJS plugin system.
- Provider request logic belongs in Rust where possible, with Flutter handling provider registry, UI, routing, and model mapping.
- Do not reference `jm-boom`; it is considered outdated for this project.

## Reference Projects

- `..\Breeze`: reference for Rust-side request/runtime architecture and general app behavior.
- `..\Breeze-plugin-JmComic`: reference for JM request signing, host resolution, response decoding, and source behavior.
- `..\komikku`: reference for manga detail UI structure, top actions, pull refresh behavior, and reader direction.

## Current State

- JM provider requests are routed through Rust/FRB instead of Dart/Dio.
- Search supports loading additional provider pages instead of showing only the first few results.
- Comic detail page is modeled after Komikku's practical detail layout:
  - Transparent top bar with back, download, and overflow actions.
  - Overflow menu contains refresh and add favorite.
  - Pull-to-refresh uses a spinner-style refresh indicator.
  - Detail metadata avoids source-specific favorite/view counts for multi-source compatibility.
  - Chapter heading shows `共 x 章`; a single chapter item is labeled `单章节`.
- Favorite and download actions are currently UI placeholders until persistence/download services are implemented.

## Next Work

- Build the reader next.
- Start from the existing provider contract: `getChapters(comicId)` and `getChapterImages(chapterId)`.
- Reader should stay source-agnostic and request pages through the selected provider.

## Verification

- Do not run project verification commands unless the user explicitly asks.
- This includes `flutter run`, `flutter test`, `flutter analyze`, `dart analyze`, `cargo check`, `cargo test`, and Android/Gradle build commands.
- When verification is needed, tell the user which command to run and ask them to share the output.
- Avoid starting Dart/Flutter/Cargo toolchain commands in the background as a substitute for user-run verification.

## Commit Guidance

- After each stage of meaningful work, provide a concise English commit message covering the staged scope.
