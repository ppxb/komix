enum LoginStatus { logout, login }

@Deprecated('不再使用，仅作为迁移时作为参考数据结构')
class JmSettingState {
  final String account;
  final String password;
  final String userInfo;
  final LoginStatus loginStatus;
  final int favoriteSet;

  const JmSettingState({
    this.account = '',
    this.password = '',
    this.userInfo = '',
    this.loginStatus = LoginStatus.logout,
    this.favoriteSet = 0,
  });

  factory JmSettingState.fromJson(Map<String, dynamic> json) {
    return JmSettingState(
      account: json['account'] as String? ?? '',
      password: json['password'] as String? ?? '',
      userInfo: json['userInfo'] as String? ?? '',
      loginStatus: LoginStatus.values.firstWhere(
        (value) => value.name == json['loginStatus'],
        orElse: () => LoginStatus.logout,
      ),
      favoriteSet: (json['favoriteSet'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account': account,
      'password': password,
      'userInfo': userInfo,
      'loginStatus': loginStatus.name,
      'favoriteSet': favoriteSet,
    };
  }
}
