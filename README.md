# Komix

一个跨平台的漫画阅读器，使用 Flutter + Rust 构建。

## 项目架构

### 技术栈

- **Flutter**: UI 框架，跨平台支持（Android, iOS, Windows, Linux, macOS）
- **Rust**: 核心业务逻辑（网络请求、数据解析、加密解密）
- **Provider**: 状态管理
- **flutter_rust_bridge**: Flutter 与 Rust 的 FFI 桥接（待配置）

### 目录结构

```
komix/
├── lib/
│   ├── main.dart                    # 应用入口
│   ├── models/                      # 数据模型
│   │   └── comic.dart              # 漫画、章节等数据模型
│   ├── providers/                   # 数据源层
│   │   ├── base_provider.dart      # 数据源基类
│   │   ├── jm_provider.dart        # 禁漫天堂数据源
│   │   └── provider_registry.dart  # 数据源注册表
│   ├── services/                    # 业务服务
│   │   └── search_aggregator.dart  # 聚合搜索服务
│   └── pages/                       # 页面
│       ├── main_page.dart          # 主页（底部导航容器）
│       └── tabs/                    # Tab 页面
│           ├── browse/             # 浏览 Tab
│           │   ├── browse_tab.dart      # 浏览容器（包含顶部 tabs）
│           │   ├── search_page.dart     # 搜索页（聚合搜索）
│           │   └── subscribe_page.dart  # 订阅页（源管理）
│           ├── favorite_tab.dart   # 收藏 Tab
│           ├── history_tab.dart    # 历史 Tab
│           └── more_tab.dart       # 更多 Tab（设置）
│
└── rust/                            # Rust 核心
    ├── src/
    │   ├── lib.rs                  # Rust 库入口
    │   ├── bridge.rs               # FFI 桥接层
    │   └── api/                     # API 实现
    │       └── jm/                 # 禁漫天堂 API
    │           └── mod.rs          # JM API 客户端
    └── Cargo.toml                  # Rust 依赖配置
```

## 核心设计

### 1. 底部导航结构

```
┌─────────┬─────────┬─────────┬─────────┐
│  浏览   │  收藏   │  历史   │  更多   │
│ Browse  │Favorite │History  │  More   │
└─────────┴─────────┴─────────┴─────────┘
```

### 2. 浏览 Tab 结构

浏览 Tab 内部包含顶部 Tabs：

```
┌─────────────────────────────────────┐
│  浏览                               │  ← 底部导航
├─────────────────────────────────────┤
│  [搜索] [订阅]                      │  ← 顶部 Tabs
├─────────────────────────────────────┤
│                                     │
│  搜索: 聚合搜索所有内置源           │
│  订阅: 管理和浏览不同的内置源       │
│                                     │
└─────────────────────────────────────┘
```

- **搜索页**: 聚合搜索所有已订阅的数据源，显示各源的搜索结果
- **订阅页**: 管理内置数据源的订阅，浏览各源的最新内容

### 3. 数据源架构

**不使用插件系统**，所有数据源都是内置的 Provider：

- `BaseProvider`: 抽象基类，定义数据源接口
- `JmProvider`: 禁漫天堂数据源实现
- `ProviderRegistry`: 管理所有内置数据源的注册和订阅

优势：
- ✅ 架构简单，易于维护
- ✅ 性能更好（直接调用，无需动态加载）
- ✅ 后续扩展灵活（直接添加新 Provider 类）

### 4. Rust 层设计

Rust 负责：
- HTTP 网络请求
- 响应数据解密（JM API 需要 AES 解密）
- HTML/JSON 解析
- 图片处理（解密、预处理）

Dart 负责：
- UI 渲染
- 状态管理
- 本地存储（收藏、历史）
- 路由导航

## 当前状态

### 已完成

- ✅ 项目基础架构搭建
- ✅ Rust 核心项目初始化
- ✅ Flutter 层目录结构和基础组件
- ✅ 底部导航（浏览、收藏、历史、更多）
- ✅ 浏览 Tab 双层结构（搜索 + 订阅）
- ✅ 数据源抽象和 JmProvider Mock 实现
- ✅ 聚合搜索服务
- ✅ 数据源注册表和管理
- ✅ 基础 UI 界面

### 待实现

- ⏳ flutter_rust_bridge 配置
- ⏳ JM API Rust 实现（参考 Breeze-plugin-JmComic）
  - HTTP 客户端和请求签名
  - AES 解密
  - 响应解析
- ⏳ 漫画详情页
- ⏳ 阅读器
- ⏳ 收藏功能
- ⏳ 历史记录
- ⏳ 本地存储（SQLite）
- ⏳ 图片缓存
- ⏳ 下载管理

## 开发指南

### 环境要求

- Flutter SDK >= 3.12.2
- Rust >= 1.70
- Android NDK（Android 构建）
- Xcode（iOS/macOS 构建）

### 运行项目

```bash
# 安装 Flutter 依赖
flutter pub get

# 运行（目前使用 Mock 数据，无需编译 Rust）
flutter run
```

### 编译 Rust 库（待配置 flutter_rust_bridge）

```bash
cd rust
cargo build --release
```

## 参考项目

- [Breeze](https://github.com/deretame/Breeze) - Rust FFI 架构参考
- [Breeze-plugin-JmComic](https://github.com/deretame/Breeze-plugin-JmComic) - JM API 契约参考
- [jm-boom](https://github.com/ppxb/jm-boom) - Tauri 桌面端实现

## License

MIT
