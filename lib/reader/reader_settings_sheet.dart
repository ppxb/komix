import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../config/global/global_setting.dart';
import 'reader_layout.dart';

bool isCompactReaderViewport(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide < 600;
}

Future<void> showReaderSettingsSheet(
  BuildContext context, {
  required VoidCallback onLayoutChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _ReaderSettingsSheet(onLayoutChanged: onLayoutChanged);
    },
  );
}

class _ReaderSettingsSheet extends StatelessWidget {
  final VoidCallback onLayoutChanged;

  const _ReaderSettingsSheet({required this.onLayoutChanged});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('阅读设置', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              _ReadModeSection(onLayoutChanged: onLayoutChanged),
              const SizedBox(height: 22),
              const _TapModeSection(),
              const SizedBox(height: 22),
              const _BackgroundSection(),
              const SizedBox(height: 22),
              _LayoutSection(onLayoutChanged: onLayoutChanged),
              const SizedBox(height: 22),
              const _AutoScrollSection(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadModeSection extends StatelessWidget {
  final VoidCallback onLayoutChanged;

  const _ReadModeSection({required this.onLayoutChanged});

  @override
  Widget build(BuildContext context) {
    final setting = context.watch<GlobalSettingCubit>().state.readSetting;
    final cubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: '阅读模式',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ChoicePill(
            label: '条漫',
            selected: setting.readMode == kReadModeColumn,
            onTap: () {
              if (setting.readMode == kReadModeColumn) return;
              cubit.updateReadSetting(
                (current) => current.copyWith(readMode: kReadModeColumn),
              );
              onLayoutChanged();
            },
          ),
          _ChoicePill(
            label: '从左到右',
            selected: setting.readMode == kReadModeRowLtr,
            onTap: () {
              if (setting.readMode == kReadModeRowLtr) return;
              cubit.updateReadSetting(
                (current) => current.copyWith(readMode: kReadModeRowLtr),
              );
              onLayoutChanged();
            },
          ),
          _ChoicePill(
            label: '从右到左',
            selected: setting.readMode == kReadModeRowRtl,
            onTap: () {
              if (setting.readMode == kReadModeRowRtl) return;
              cubit.updateReadSetting(
                (current) => current.copyWith(readMode: kReadModeRowRtl),
              );
              onLayoutChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _TapModeSection extends StatelessWidget {
  const _TapModeSection();

  @override
  Widget build(BuildContext context) {
    final setting = context.watch<GlobalSettingCubit>().state.readSetting;
    if (isColumnReadMode(setting.readMode)) {
      return const SizedBox.shrink();
    }

    final cubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: '翻页触控',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ChoicePill(
            label: '全屏下一页',
            selected: setting.tapPageTurnMode == ReaderTapPageTurnMode.fullScreen,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  tapPageTurnMode: ReaderTapPageTurnMode.fullScreen,
                ),
              );
            },
          ),
          _ChoicePill(
            label: '左手',
            selected: setting.tapPageTurnMode == ReaderTapPageTurnMode.leftHand,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  tapPageTurnMode: ReaderTapPageTurnMode.leftHand,
                ),
              );
            },
          ),
          _ChoicePill(
            label: '右手',
            selected: setting.tapPageTurnMode == ReaderTapPageTurnMode.rightHand,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  tapPageTurnMode: ReaderTapPageTurnMode.rightHand,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BackgroundSection extends StatelessWidget {
  const _BackgroundSection();

  @override
  Widget build(BuildContext context) {
    final setting = context.watch<GlobalSettingCubit>().state.readSetting;
    final cubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: '背景',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _ChoicePill(
            label: '跟随系统',
            selected: setting.readerBackgroundMode == ReaderBackgroundMode.auto,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  readerBackgroundMode: ReaderBackgroundMode.auto,
                ),
              );
            },
          ),
          _ChoicePill(
            label: '黑色',
            selected: setting.readerBackgroundMode == ReaderBackgroundMode.black,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  readerBackgroundMode: ReaderBackgroundMode.black,
                ),
              );
            },
          ),
          _ChoicePill(
            label: '白色',
            selected: setting.readerBackgroundMode == ReaderBackgroundMode.white,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  readerBackgroundMode: ReaderBackgroundMode.white,
                ),
              );
            },
          ),
          _ChoicePill(
            label: '灰色',
            selected: setting.readerBackgroundMode == ReaderBackgroundMode.grey,
            onTap: () {
              cubit.updateReadSetting(
                (current) => current.copyWith(
                  readerBackgroundMode: ReaderBackgroundMode.grey,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LayoutSection extends StatelessWidget {
  final VoidCallback onLayoutChanged;

  const _LayoutSection({required this.onLayoutChanged});

  @override
  Widget build(BuildContext context) {
    final setting = context.watch<GlobalSettingCubit>().state.readSetting;
    final cubit = context.read<GlobalSettingCubit>();
    final isCompact = isCompactReaderViewport(context);
    final doublePageValue = !isCompact && setting.doublePageMode;

    return _SettingsSection(
      title: '版面',
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('双页阅读'),
            subtitle: Text(
              isCompact ? '手机小屏已禁用' : '大屏横向阅读时并排显示两页',
            ),
            value: doublePageValue,
            onChanged: isCompact
                ? null
                : (value) {
                    cubit.updateReadSetting(
                      (current) => current.copyWith(doublePageMode: value),
                    );
                    onLayoutChanged();
                  },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('页面侧边距'),
            value: setting.sidePaddingEnabled,
            onChanged: (value) {
              cubit.updateReadSetting(
                (current) => current.copyWith(sidePaddingEnabled: value),
              );
              onLayoutChanged();
            },
          ),
          if (setting.sidePaddingEnabled)
            _SliderRow(
              label: '侧边距',
              value: setting.sidePaddingPercent.clamp(0, 30).toInt(),
              min: 0,
              max: 30,
              divisions: 30,
              suffix: '%',
              onChanged: (value) {
                cubit.updateReadSetting(
                  (current) => current.copyWith(sidePaddingPercent: value),
                );
              },
              onChangeEnd: (_) => onLayoutChanged(),
            ),
        ],
      ),
    );
  }
}

class _AutoScrollSection extends StatelessWidget {
  const _AutoScrollSection();

  @override
  Widget build(BuildContext context) {
    final setting = context.watch<GlobalSettingCubit>().state.readSetting;
    final cubit = context.read<GlobalSettingCubit>();

    return _SettingsSection(
      title: '自动滚动',
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用自动滚动'),
            value: setting.autoScroll,
            onChanged: (value) {
              cubit.updateReadSetting(
                (current) => current.copyWith(autoScroll: value),
              );
            },
          ),
          if (setting.autoScroll) ...[
            _SliderRow(
              label: '条漫间隔',
              value: setting.autoScrollColumnIntervalMs
                  .clamp(300, 5000)
                  .toInt(),
              min: 300,
              max: 5000,
              divisions: 47,
              suffix: 'ms',
              onChanged: (value) {
                cubit.updateReadSetting(
                  (current) =>
                      current.copyWith(autoScrollColumnIntervalMs: value),
                );
              },
            ),
            _SliderRow(
              label: '分页间隔',
              value: setting.autoScrollPageIntervalMs
                  .clamp(800, 10000)
                  .toInt(),
              min: 800,
              max: 10000,
              divisions: 46,
              suffix: 'ms',
              onChanged: (value) {
                cubit.updateReadSetting(
                  (current) =>
                      current.copyWith(autoScrollPageIntervalMs: value),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _SettingsSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int divisions;
  final String suffix;
  final ValueChanged<int> onChanged;
  final ValueChanged<int>? onChangeEnd;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions,
            label: '$value$suffix',
            onChanged: (value) => onChanged(value.round()),
            onChangeEnd: onChangeEnd == null
                ? null
                : (value) => onChangeEnd!(value.round()),
          ),
        ),
        SizedBox(
          width: 64,
          child: Text(
            '$value$suffix',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
