class BikaSettingState {
  final String account;
  final String password;
  final String authorization;
  final int level;
  final int proxy;
  final String imageQuality;
  final Map<String, bool> shieldCategoryMap;
  final Map<String, bool> shieldHomePageCategoriesMap;
  final bool signIn;
  final bool brevity;
  final bool slowDownload;

  const BikaSettingState({
    this.account = '',
    this.password = '',
    this.authorization = '',
    this.level = 0,
    this.proxy = 3,
    this.imageQuality = 'original',
    this.shieldCategoryMap = const <String, bool>{},
    this.shieldHomePageCategoriesMap = const <String, bool>{},
    this.signIn = false,
    this.brevity = false,
    this.slowDownload = false,
  });

  factory BikaSettingState.fromJson(Map<String, dynamic> json) {
    return BikaSettingState(
      account: json['account'] as String? ?? '',
      password: json['password'] as String? ?? '',
      authorization: json['authorization'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 0,
      proxy: (json['proxy'] as num?)?.toInt() ?? 3,
      imageQuality: json['imageQuality'] as String? ?? 'original',
      shieldCategoryMap: _boolMap(json['shieldCategoryMap']),
      shieldHomePageCategoriesMap: _boolMap(
        json['shieldHomePageCategoriesMap'],
      ),
      signIn: json['signIn'] as bool? ?? false,
      brevity: json['brevity'] as bool? ?? false,
      slowDownload: json['slowDownload'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account': account,
      'password': password,
      'authorization': authorization,
      'level': level,
      'proxy': proxy,
      'imageQuality': imageQuality,
      'shieldCategoryMap': shieldCategoryMap,
      'shieldHomePageCategoriesMap': shieldHomePageCategoriesMap,
      'signIn': signIn,
      'brevity': brevity,
      'slowDownload': slowDownload,
    };
  }

  static Map<String, bool> _boolMap(dynamic value) {
    if (value is! Map) return const <String, bool>{};
    return value.map((key, value) => MapEntry(key.toString(), value == true));
  }
}
