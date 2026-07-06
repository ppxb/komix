# Komix 开发笔记

## 项目概览

Komix 是一个 Flutter + Rust 混合架构的跨平台漫画阅读器。当前重点是把多源能力收敛到内置 Provider 体系中：Rust 负责请求、签名、解密、解析和图片处理，Flutter 负责 Provider 注册、UI、业务服务、本地数据和阅读体验。

## 核心原则

1. 不引入动态插件系统，所有漫画源通过内置 Provider 维护。
2. 源请求优先在 Rust 实现，Flutter 只做调用、模型映射和业务编排。
3. 阅读器、下载、收藏、历史等服务保持源无关。
4. 参考 Breeze 时迁移能力和交互，不迁移插件/QJS 运行时。
5. 验证命令由开发者按需手动执行，协作过程中不主动运行 Flutter/Dart/Cargo 检查。

## 当前进度

### Rust 层

- [x] `rust/` 核心库初始化。
- [x] flutter_rust_bridge 接入和 Dart 绑定生成。
- [x] HTTP 客户端、通用请求辅助和基础错误处理。
- [x] JM API 请求签名、端点解析、响应解密和模型解析。
- [x] JM 搜索、详情、章节、章节图片、最新、排行接口。
- [x] JM 图片切图/解码并写入本地缓存。
- [ ] 通用 Provider 请求能力抽象。
- [x] 哔咔 API 基础认证、签名、分页和图片地址解析。

### Flutter Provider 层

- [x] `BaseProvider` 定义源无关契约。
- [x] `JmProvider` 通过 FRB 调用 Rust 侧 JM 实现。
- [x] `ProviderRegistry` 注册和订阅内置源。
- [x] 聚合搜索服务。
- [x] 阅读快照模型 `ReaderChapterSnapshot`。
- [x] `BikaProvider` 基础接入。
- [ ] Provider 能力声明，例如是否支持最新、排行、登录、下载、图片请求头。
- [ ] Provider 设置持久化和账号/鉴权状态的通用抽象。
- [ ] 多源错误、登录过期和重试策略。

### UI 和业务服务

- [x] 主页面底部导航：浏览、收藏、历史、更多。
- [x] 搜索页、订阅页和源管理入口。
- [x] 漫画详情页：刷新、收藏、下载、章节列表、继续阅读。
- [x] 阅读器：纵向/横向、左右方向、双页、进度、章节选择、键盘/音量键、自动滚动、阅读设置。
- [x] 收藏服务和收藏夹管理。
- [x] 历史服务和继续阅读。
- [x] 下载基础链路：队列、章节选择、已下载识别、取消、重试、移除、离线快照和本地阅读。
- [x] 图片缓存和阅读快照缓存。
- [x] 下载章节选择页。
- [x] 删除下载记录和本地文件管理。
- [ ] 下载任务详情、进度统计、并发/后台能力。
- [ ] 统一书架：收藏、历史、下载的搜索、筛选、排序和批量操作。
- [ ] 更完整的设置页：主题、阅读、缓存、代理、同步、调试。

## 当前三阶段任务

### 1. 更新文档

- [x] README 反映当前真实状态。
- [x] DEVELOPMENT 记录架构约束、进度和近期路线。
- [ ] 后续随下载和哔咔接入继续同步文档。

### 2. 迁移 Breeze 下载能力

迁移目标是补齐 Komix 下载体验，而不是照搬 Breeze 的插件下载运行时。优先参考：

- `../Breeze/lib/page/download/`
- `../Breeze/lib/page/donwload_task/`
- `../Breeze/lib/util/download/`
- `../Breeze/lib/util/foreground_task/data/download_task_json.dart`
- `../Breeze/lib/page/download/models/unified_comic_download.dart`

本阶段已迁移的能力：

- 章节选择页面，支持全选、反选、识别已下载章节。
- 更清晰的下载任务模型，保存章节逻辑 key、请求 id、存储 id、排序和标题。
- 补下新章节时合并既有离线索引，取消补下任务时只清理当前章节目录。
- 删除下载记录时同步删除本地文件和书架链接。

仍待继续迁移的能力：

- 下载任务页区分进行中、等待、失败、完成状态。
- 下载进度统计到章节和图片级别。
- 取消信号、恢复中断任务、失败重试和队列管理。
- 本地下载记录解析和离线阅读入口。

暂不迁移的能力：

- 插件/QJS 运行时下载接口。
- 与动态插件安装、更新、卸载绑定的下载清理逻辑。
- 和当前内置源架构不匹配的 schema 动态渲染。

### 3. 接入哔咔源

哔咔源以 Komix 内置 Provider 方式接入。接口实现参考 `../Breeze-plugin-bikaComic`，落地边界如下：

- Rust：已接入认证、签名、请求头、分页、搜索、详情、章节、图片、最新和排行。
- Flutter：已接入 `BikaProvider`、Provider 注册、登录入口和模型映射。
- 下载/阅读：已通过现有 `getChapters`、`getChapterImages`、`getReaderChapterSnapshot` 契约复用。

优先接口：

- [x] 登录/保存认证信息。
- [x] 搜索漫画。
- [x] 获取漫画详情。
- [x] 获取章节列表。
- [x] 获取章节图片。
- [x] 最新/排行。
- [ ] 分类列表、屏蔽分类、收藏、点赞、评论和签到。

## 开发规范

### 文件组织

```text
lib/
├── config/       # 全局设置和源设置
├── models/       # 跨层模型
├── providers/    # 内置 Provider
├── services/     # 收藏、历史、下载、搜索、缓存
├── pages/        # 页面
├── reader/       # 阅读器内部组件
└── util/         # 工具和任务数据

rust/src/
├── api/          # 源请求实现
├── decode/       # 图片处理
└── bridge.rs     # FRB 导出
```

### 命名约定

- Dart 类：`PascalCase`，例如 `BikaProvider`。
- Dart 文件：`snake_case`，例如 `bika_provider.dart`。
- Rust 模块：`snake_case`，例如 `api/bika/mod.rs`。
- Rust 函数：`snake_case`，例如 `bika_search`。
- Provider ID 使用稳定小写字符串，例如 `jm`、`bika`。

### 提交信息

- `docs: refresh project status and roadmap`
- `feat: add download chapter selection flow`
- `feat: add bika provider`
- `fix: resume interrupted download tasks`

## 参考资源

- Breeze：`../Breeze/`
  - 下载队列、任务页、书架、本地阅读和设置体验。
- Breeze-plugin-JmComic：`../Breeze-plugin-JmComic/`
  - JM 源请求签名、响应解码和图片处理。
- Breeze-plugin-bikaComic：`../Breeze-plugin-bikaComic/`
  - 哔咔认证、签名、请求参数和数据结构。
