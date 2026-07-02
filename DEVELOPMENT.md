# Komix 开发笔记

## 项目概览

Komix 是一个跨平台漫画阅读器，采用 Flutter + Rust 混合架构。

### 核心设计理念

1. **不使用插件系统** - 所有数据源都是内置的，通过 Provider 模式管理
2. **早期引入 Rust** - 避免后期重构，核心逻辑用 Rust 实现
3. **双层 Tab 结构** - 浏览 Tab 内包含搜索和订阅两个子页面
4. **聚合搜索** - 可同时搜索多个已订阅的数据源

## 当前进度 (2026-07-02)

### ✅ 已完成

#### Rust 层
- [x] 创建 Rust 库项目 (`rust/`)
- [x] 配置 `Cargo.toml` 依赖
  - reqwest (HTTP)
  - tokio (异步)
  - serde (序列化)
  - aes + md5 (加密)
  - flutter_rust_bridge (FFI)
- [x] 定义 JM API 数据结构
  - Comic, Chapter, ChapterImages, SearchResult
- [x] 创建 FFI 桥接函数框架
  - `jm_search`, `jm_get_comic_detail` 等
- [x] 创建 JmProvider 骨架

#### Flutter 层
- [x] 项目初始化和依赖配置
- [x] 数据模型 (`lib/models/comic.dart`)
- [x] 数据源抽象层
  - `BaseProvider` - 数据源接口
  - `JmProvider` - 禁漫天堂实现（Mock）
  - `ProviderRegistry` - 数据源注册和订阅管理
- [x] 服务层
  - `SearchAggregator` - 聚合搜索服务
- [x] UI 层
  - `MainPage` - 底部导航容器
  - `BrowseTab` - 浏览 Tab（包含顶部 tabs）
    - `SearchPage` - 聚合搜索页
    - `SubscribePage` - 订阅管理页
  - `FavoriteTab` - 收藏页（占位）
  - `HistoryTab` - 历史页（占位）
  - `MoreTab` - 设置页（含数据源管理）

### ⏳ 下一步计划

#### 优先级 1: Rust 核心实现
- [ ] 参考 Breeze-plugin-JmComic 实现 JM API
  - [ ] HTTP 客户端配置（请求签名、token、gzip）
  - [ ] AES 解密逻辑
  - [ ] 响应解析
  - [ ] 搜索、详情、章节接口
- [ ] 配置 flutter_rust_bridge
  - [ ] 添加 build.rs
  - [ ] 生成 Dart 绑定代码
  - [ ] 集成到 Flutter 项目

#### 优先级 2: 详情和阅读
- [ ] 漫画详情页
  - [ ] 封面和元数据展示
  - [ ] 章节列表
  - [ ] 相关推荐
  - [ ] 收藏/点赞按钮
- [ ] 阅读器
  - [ ] 单页模式（左右翻页）
  - [ ] 竖屏连续滚动
  - [ ] 图片预加载
  - [ ] 阅读进度保存

#### 优先级 3: 本地功能
- [ ] 收藏系统
  - [ ] SQLite 存储
  - [ ] 收藏列表展示
  - [ ] 收藏夹管理
- [ ] 历史记录
  - [ ] 阅读历史记录
  - [ ] 继续阅读
- [ ] 图片缓存
  - [ ] 封面缓存
  - [ ] 章节图片缓存

## 技术栈

### 前端
- Flutter 3.12.2+
- provider (状态管理)
- go_router (路由)
- dio (HTTP - 备用)
- sqflite (本地数据库)
- cached_network_image (图片缓存)

### 后端
- Rust 1.95.0+
- reqwest (HTTP 客户端)
- tokio (异步运行时)
- serde/serde_json (序列化)
- aes + md5 (加密)
- scraper (HTML 解析)
- flutter_rust_bridge 2.10 (FFI)

## 开发规范

### 文件组织
```
lib/
├── models/      # 数据模型（与 Rust 对应）
├── providers/   # 数据源实现
├── services/    # 业务逻辑服务
└── pages/       # UI 页面
```

### 命名约定
- Dart 类：PascalCase (`JmProvider`)
- Dart 文件：snake_case (`jm_provider.dart`)
- Rust 模块：snake_case (`jm/mod.rs`)
- Rust 函数：snake_case (`jm_search`)

### Git 提交规范
- feat: 新功能
- fix: 修复
- refactor: 重构
- docs: 文档
- style: 格式
- test: 测试

## 参考资源

### API 契约
- Breeze-plugin-JmComic: `../Breeze-plugin-JmComic/src/index.ts`
  - 请求签名逻辑
  - 响应解密逻辑
  - API 端点定义

### 架构参考
- Breeze: `../breeze/`
  - Rust FFI 集成
  - 数据库设计
  - 阅读器实现
