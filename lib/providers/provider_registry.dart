import 'package:flutter/foundation.dart';
import 'base_provider.dart';
import 'bika_provider.dart';
import 'jm_provider.dart';

/// 数据源注册表
/// 管理所有内置数据源
class ProviderRegistry extends ChangeNotifier {
  static final ProviderRegistry _instance = ProviderRegistry._internal();
  factory ProviderRegistry() => _instance;
  ProviderRegistry._internal() {
    _registerProviders();
  }

  final Map<String, BaseProvider> _providers = {};
  final List<String> _subscribedProviders = [];

  /// 注册所有内置数据源
  void _registerProviders() {
    final jmProvider = JmProvider();
    _providers[jmProvider.id] = jmProvider;

    final bikaProvider = BikaProvider();
    _providers[bikaProvider.id] = bikaProvider;

    // 默认订阅 JM 源
    _subscribedProviders.add(jmProvider.id);
  }

  /// 获取所有可用的数据源
  List<BaseProvider> getAllProviders() {
    return _providers.values.toList();
  }

  /// 获取已订阅的数据源
  List<BaseProvider> getSubscribedProviders() {
    return _subscribedProviders
        .map((id) => _providers[id])
        .whereType<BaseProvider>()
        .toList();
  }

  /// 根据 ID 获取数据源
  BaseProvider? getProvider(String id) {
    return _providers[id];
  }

  /// 订阅数据源
  void subscribe(String providerId) {
    if (!_subscribedProviders.contains(providerId) &&
        _providers.containsKey(providerId)) {
      _subscribedProviders.add(providerId);
      notifyListeners();
    }
  }

  /// 取消订阅数据源
  void unsubscribe(String providerId) {
    if (_subscribedProviders.contains(providerId)) {
      _subscribedProviders.remove(providerId);
      notifyListeners();
    }
  }

  /// 检查是否已订阅
  bool isSubscribed(String providerId) {
    return _subscribedProviders.contains(providerId);
  }
}
