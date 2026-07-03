import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../config/global/global_setting.dart';
import 'reader_cubit.dart';
import 'reader_layout.dart';

class ReaderPageInfoOverlay extends StatefulWidget {
  final int totalPageCount;
  final bool enableDoublePage;

  const ReaderPageInfoOverlay({
    super.key,
    required this.totalPageCount,
    required this.enableDoublePage,
  });

  @override
  State<ReaderPageInfoOverlay> createState() => _ReaderPageInfoOverlayState();
}

class _ReaderPageInfoOverlayState extends State<ReaderPageInfoOverlay> {
  final Battery _battery = Battery();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _timer;
  ConnectivityResult _connectivityResult = ConnectivityResult.none;
  BatteryState _batteryState = BatteryState.full;
  int _batteryLevel = 100;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _initBattery();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateTime();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          _updateTime();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _connectivitySubscription?.cancel();
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initConnectivity() async {
    try {
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      if (results.isNotEmpty) {
        _updateConnectivityResult(results);
      }
      _connectivitySubscription = connectivity.onConnectivityChanged.listen((
        results,
      ) {
        if (mounted && results.isNotEmpty) {
          _updateConnectivityResult(results);
        }
      });
    } catch (_) {}
  }

  Future<void> _initBattery() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() => _batteryLevel = level);
      }

      final state = await _battery.batteryState;
      if (mounted) {
        setState(() => _batteryState = state);
      }

      _batteryStateSubscription = _battery.onBatteryStateChanged.listen((
        state,
      ) {
        if (mounted) {
          setState(() => _batteryState = state);
        }
      });
    } catch (_) {}
  }

  void _updateConnectivityResult(List<ConnectivityResult> results) {
    final result = _highestPriorityConnectivity(results);
    if (mounted && result != _connectivityResult) {
      setState(() => _connectivityResult = result);
    }
  }

  ConnectivityResult _highestPriorityConnectivity(
    List<ConnectivityResult> results,
  ) {
    const priorityOrder = [
      ConnectivityResult.wifi,
      ConnectivityResult.mobile,
      ConnectivityResult.satellite,
      ConnectivityResult.ethernet,
      ConnectivityResult.bluetooth,
      ConnectivityResult.vpn,
      ConnectivityResult.other,
      ConnectivityResult.none,
    ];
    for (final type in priorityOrder) {
      if (results.contains(type)) return type;
    }
    return ConnectivityResult.none;
  }

  void _updateTime() {
    final now = DateTime.now();
    final formatted =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (formatted != _currentTime) {
      setState(() => _currentTime = formatted);
      _refreshBatteryLevel();
    }
  }

  void _refreshBatteryLevel() {
    _battery.batteryLevel
        .then((level) {
          if (mounted && level != _batteryLevel) {
            setState(() => _batteryLevel = level);
          }
        })
        .catchError((_) {});
  }

  IconData _networkIcon() {
    switch (_connectivityResult) {
      case ConnectivityResult.bluetooth:
        return Icons.bluetooth;
      case ConnectivityResult.wifi:
        return Icons.wifi;
      case ConnectivityResult.ethernet:
        return Icons.router;
      case ConnectivityResult.mobile:
        return Icons.network_cell;
      case ConnectivityResult.satellite:
        return Icons.satellite_alt;
      case ConnectivityResult.vpn:
        return Icons.vpn_key;
      case ConnectivityResult.none:
        return Icons.signal_wifi_off;
      case ConnectivityResult.other:
        return Icons.signal_cellular_off;
    }
  }

  IconData _batteryIcon() {
    if (_batteryState == BatteryState.charging) {
      return Icons.battery_charging_full;
    }
    if (_batteryLevel >= 95) return Icons.battery_full;
    if (_batteryLevel >= 80) return Icons.battery_6_bar;
    if (_batteryLevel >= 60) return Icons.battery_5_bar;
    if (_batteryLevel >= 50) return Icons.battery_4_bar;
    if (_batteryLevel >= 30) return Icons.battery_3_bar;
    if (_batteryLevel >= 20) return Icons.battery_2_bar;
    if (_batteryLevel >= 10) return Icons.battery_1_bar;
    return Icons.battery_alert;
  }

  @override
  Widget build(BuildContext context) {
    final pageIndex = context.select<ReaderCubit, int>(
      (cubit) => cubit.state.pageIndex,
    );
    final readSetting = context.select<GlobalSettingCubit, ReadSettingState>(
      (cubit) => cubit.state.readSetting,
    );
    final showPage = readSetting.pageInfoShowPage;
    final showNetwork = readSetting.pageInfoShowNetwork;
    final showBattery = readSetting.pageInfoShowBattery;
    final showTime = readSetting.pageInfoShowTime;

    if (!showPage && !showNetwork && !showBattery && !showTime) {
      return const SizedBox.shrink();
    }

    final mediaPadding = MediaQuery.paddingOf(context);
    final totalPageCount = widget.totalPageCount > 0
        ? widget.totalPageCount
        : 1;
    final displayPage = getDisplayPageNumber(
      slotIndex: pageIndex,
      enableDoublePage: widget.enableDoublePage,
    ).clamp(1, totalPageCount).toInt();
    final pageText = '$displayPage/$totalPageCount';
    final opacityPercent = readSetting.pageInfoOpacityPercent
        .clamp(20, 100)
        .toInt();
    final fontSize = readSetting.pageInfoFontSize.clamp(10, 20).toDouble();
    final edge = readSetting.pageInfoEdgePadding.clamp(0, 48).toDouble();
    final sideExtra =
        readSetting.pageInfoHorizontalPosition ==
            ReaderInfoHorizontalPosition.center
        ? 0.0
        : (Platform.isIOS ? 22.0 : 12.0);
    final verticalExtra = Platform.isIOS ? 6.0 : 2.0;
    final isTop =
        readSetting.pageInfoVerticalPosition == ReaderInfoVerticalPosition.top;
    final showInStatusBar = isTop && readSetting.pageInfoTopInStatusBar;
    final verticalOffset = isTop
        ? (showInStatusBar ? edge : mediaPadding.top + edge + verticalExtra)
        : mediaPadding.bottom + edge + verticalExtra;

    final panel = _ReaderPageInfoPanel(
      pageText: pageText,
      showPage: showPage,
      showNetwork: showNetwork,
      showBattery: showBattery,
      showTime: showTime,
      currentTime: _currentTime,
      batteryLevel: _batteryLevel,
      networkIcon: _networkIcon(),
      batteryIcon: _batteryIcon(),
      opacityPercent: opacityPercent,
      fontSize: fontSize,
    );

    final horizontalPosition = readSetting.pageInfoHorizontalPosition;
    if (horizontalPosition == ReaderInfoHorizontalPosition.center) {
      return Positioned(
        top: isTop ? verticalOffset : null,
        bottom: isTop ? null : verticalOffset,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Align(
            alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
            child: panel,
          ),
        ),
      );
    }

    final left = horizontalPosition == ReaderInfoHorizontalPosition.left
        ? mediaPadding.left + edge + sideExtra
        : null;
    final right = horizontalPosition == ReaderInfoHorizontalPosition.right
        ? mediaPadding.right + edge + sideExtra
        : null;

    return Positioned(
      top: isTop ? verticalOffset : null,
      bottom: isTop ? null : verticalOffset,
      left: left,
      right: right,
      child: IgnorePointer(child: panel),
    );
  }
}

class _ReaderPageInfoPanel extends StatelessWidget {
  final String pageText;
  final bool showPage;
  final bool showNetwork;
  final bool showBattery;
  final bool showTime;
  final String currentTime;
  final int batteryLevel;
  final IconData networkIcon;
  final IconData batteryIcon;
  final int opacityPercent;
  final double fontSize;

  const _ReaderPageInfoPanel({
    required this.pageText,
    required this.showPage,
    required this.showNetwork,
    required this.showBattery,
    required this.showTime,
    required this.currentTime,
    required this.batteryLevel,
    required this.networkIcon,
    required this.batteryIcon,
    required this.opacityPercent,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: fontSize,
    );
    final iconSize = (fontSize + 1).clamp(10, 24).toDouble();
    final items = <Widget>[];

    if (showPage) {
      items.add(Text(pageText, style: textStyle));
    }
    if (showNetwork) {
      items.add(Icon(networkIcon, color: Colors.white, size: iconSize));
    }
    if (showBattery) {
      items.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(batteryIcon, color: Colors.white, size: iconSize),
            const SizedBox(width: 2),
            Text('$batteryLevel%', style: textStyle),
          ],
        ),
      );
    }
    if (showTime) {
      items.add(Text(currentTime, style: textStyle));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: opacityPercent / 100),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              items[i],
              if (i != items.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}
