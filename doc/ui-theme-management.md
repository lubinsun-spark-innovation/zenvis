# UI 主题管理架构与插件迁移方案

> 状态：架构设计基线，供 ZenVis 平台主题管理、Plugin UI Contract 演进和 OneSOC/Lubinsun 插件迁移共同遵循。本文不表示所有能力已经实现。

## 1. 目标与非目标

ZenVis 需要把主站、低代码页面、插件页面、图表和驾驶舱的视觉规则收敛为平台能力，并在 **系统管理 → UI 管理** 中完成主题创建或导入、校验、预览、切换和回滚。主题切换不能要求 OneSOC、Lubinsun 或后续插件各自复制 CSS、JavaScript 动效或 Naive UI 配置。

本方案目标：

- 将现有 ZenVis/Naive UI 亮色表现固化为内置主题 `zenvis-naive-light`，保证当前主站和严格 `STANDARD` 插件页面升级后不退化。
- 提供内置深色运营主题 `zenvis-command-dark`，作为高频运维控制台和未来主题化驾驶舱的视觉基线。
- 使用同一份语义 Token 同步驱动 Vue/Naive UI、AMIS、Plugin UI Contract 和 ECharts。
- 允许管理员在多个受控主题之间切换，并在激活失败时立即回滚到最近一次有效快照。
- 保持 Plugin UI Contract v1 的 `STANDARD` 页面兼容；不以修改 v1 既有类语义的方式实现主题切换。
- 为未来 Plugin UI Contract v2 的 `COCKPIT`/`IMMERSIVE` 能力建立明确迁移路径。
- 让插件继续拥有业务结构、数据和交互，平台拥有跨插件可复用的视觉规则。

本方案不做以下事情：

- 不允许主题包携带或执行任意 JavaScript。
- 不允许主题包上传任意 CSS、字体、HTML、SVG 或远程资源。
- 不允许主题绕过页面、菜单、接口或数据权限。
- 不让主题配置决定 OneSOC 的业务指标、API、字段、筛选、路由和处置流程。
- 不通过在宿主中长期维护 `soc-*`、`lubinsun-*` 等业务选择器解决兼容问题。
- 不把主题切换等同于插件升级、数据库迁移或看板资源重装。

## 2. 核心原则

### 2.1 一份语义，多套表现

插件只声明“指标卡”“危险状态”“图表容器”“代码块”等语义。平台主题决定颜色、字体、间距、圆角、阴影、密度和动效。

```text
主题 Manifest
   │
   ├── 语义 Token ──> ZenVis Vue / Naive UI themeOverrides
   ├── 语义 Token ──> AMIS / Plugin UI CSS Variables
   ├── Chart 配置  ──> ECharts Palette / Axis / Tooltip
   └── Motion 配置 ──> 平台允许的声明式动效预设
```

主题不能修改业务数据，也不能按具体插件包名覆盖页面。

### 2.2 向后兼容优先

- Plugin UI Contract v1 的稳定 `zv-*` 类名和语义保持不变。
- 新主题通过替换 Token 和适配器参数改变表现，不直接改变 v1 DOM 结构要求。
- 不要求插件改变既有 DOM 的可选通用 `zv-*` recipe 可在 v1 增量提供；新增 `COCKPIT` Profile、强制结构语义或破坏性行为时发布 Contract v2。
- 旧插件继续可用；平台对已确认的旧版本提供有明确删除条件的短期兼容桥。

### 2.3 默认安全、显式激活

主题通过管理页粘贴或选择 JSON 创建，并在浏览器和服务端完成 Schema、字段白名单与安全校验。创建后形成草稿 revision；草稿可继续编辑，激活时发布且发布后不可改写。第一阶段不公开独立的 publish API，只有超级管理员可以激活平台默认主题。

### 2.4 视觉配置不能成为执行代码

主题表达能力限定为：

- 允许列表中的语义 Token；
- 受控组件外观枚举；
- ECharts 色板和可读性参数；
- 声明式 Motion 预设；
- 平台内置资产引用。

主题包不得包含脚本、样式表、表达式、模板代码、网络地址或可执行内容。

## 3. 平台与插件职责边界

| 能力 | ZenVis 平台主题 | 业务插件 |
| --- | --- | --- |
| 品牌色、状态色、表面、文字、边框 | 负责 | 只引用语义 |
| 字体、间距、圆角、阴影、密度 | 负责 | 不复制主题值 |
| Naive UI、AMIS、ECharts 外观同步 | 负责 | 不维护独立 themeOverrides |
| 通用 Hero、KPI、图表卡、表格、代码块 | 负责 | 组合公共组件 |
| focus、hover、loading、empty、error | 负责通用表现 | 提供真实业务状态 |
| 动效曲线、持续时间、减少动效 | 负责 | 只选择允许的语义事件 |
| 页面结构、字段、筛选和按钮 | 不负责 | 负责 |
| API、轮询、状态机、错误语义 | 不负责 | 负责 |
| 图表类型、维度、指标和业务排序 | 不负责 | 负责 |
| 驾驶舱业务布局和响应式编排 | 提供通用皮肤与 Token | 负责结构和业务断点 |
| 插件菜单与角色授权 | 提供平台机制 | 声明入口，管理员授权 |

### 3.1 `STANDARD` 普通页面

普通菜单、低代码应用和低代码页面默认使用 `STANDARD`。插件：

- 使用公开 `zv-*` 语义类和 AMIS 原生组件；
- 提供 `md`、`sm`、`xs` 响应式布局；
- 不写固定主题颜色、背景、阴影或圆角；
- 不携带主题 JavaScript；
- 业务状态通过 `alert`、`tag` 或稳定语义传递。

平台：

- 在 AMIS 容器加载版本化 Token、UI Kit、AMIS Adapter 和 Chart Adapter；
- 将活动主题同步到 iframe；
- 提供主题切换、图表重绘和减少动效；
- 对加载、空数据、错误、无权限和 stale 状态提供一致基线。

### 3.2 驾驶舱与沉浸式页面

Contract v1 的 `IMMERSIVE` 仍是自包含隔离档案。现有页面不会因为平台上线主题管理就被强制换肤。

Contract v2 计划新增 `COCKPIT`：

- 适用于需要沉浸式布局但希望继承平台主题的第一方驾驶舱；
- 平台注入 Cockpit Token、公共卡片/面板皮肤、状态组件、图表主题和 Motion Runtime；
- 插件保留布局、数据查询、业务状态机、路由和领域交互；
- 主题可以为 `STANDARD` 与 `COCKPIT` 分别提供表现，但使用同一语义色体系。

`IMMERSIVE` 在 v2 中继续保留：

- 默认不注入平台组件皮肤；
- 适用于必须完全自包含或由外部设计系统负责的页面；
- 可以显式接收只读的基础主题上下文，但不会因全局主题切换而被破坏；
- 迁移前保持原视觉并作为回滚路径。

## 4. 主题 Manifest

### 4.1 首期 JSON 导入约束

第一期不接收 ZIP 主题包。UI 管理提供两种等价入口：

- 在编辑器中粘贴一个 JSON Manifest；
- 从本机选择单个 `manifest.json` 文件。

两种入口都向 singular `POST /api/v1/system/ui-theme` 提交 JSON 对象，由服务端重新解析、规范化和校验；浏览器端校验只用于即时反馈，不能代替服务端安全边界。

Manifest 不接受以下内容或引用：

- JavaScript、CSS、HTML、模板和表达式；
- 字体、SVG、视频、音频或可执行资源；
- 远程 URL、`data:` URI、协议相对 URL；
- CSS 选择器、CSS 函数和 DOM 选择器级覆盖；
- 插件包名、路由或按具体业务页面生效的规则。

首期 Manifest 不包含品牌图片或资产字段。ZIP、图片资产以及平台登记资产 ID 均属于未来扩展；如果开放，必须另行定义归档路径安全、文件类型、解码重编码、大小、hash 和回滚规范，不能改变首期“Manifest 不执行任意 JS/CSS”的约束。

### 4.2 示例 Manifest

```json
{
  "schema_version": "1.0",
  "id": "company-command-dark",
  "name": "Company Command Dark",
  "version": "1.0.0",
  "color_scheme": "dark",
  "extends": "zenvis-command-dark",
  "tokens": {
    "--zv-primary": "#34d399",
    "--zv-primary-rgb": "52 211 153",
    "--zv-bg-canvas": "#070b0a",
    "--zv-bg-surface": "#101614",
    "--zv-text-primary": "#f1f7f3",
    "--zv-border": "#33413b"
  },
  "chart_palette": {
    "primary": "#34d399",
    "success": "#22c55e",
    "warning": "#f5b942",
    "danger": "#ff5d68"
  },
  "density": "compact",
  "motion_preset": "command"
}
```

### 4.3 Schema 规则

- `id` 使用小写字母、数字和连字符并以字母开头，最长 80 个字符；内置主题 ID 保留且不可覆盖。
- `version` 使用 SemVer；草稿 revision 可原地更新，激活时发布，发布后的 revision 不再改写。
- 顶层字段仅允许 `schema_version/id/name/version/color_scheme/extends/tokens/chart_palette/density/motion_preset`，未知字段直接拒绝。
- `extends` 只能引用 `zenvis-naive-light` 或 `zenvis-command-dark`。
- Token Key 必须在当前 Theme Contract 白名单中；图表色板也使用固定 Key。
- Token 值是受长度限制的字符串，并拒绝外链协议、`var()`、`url()`、`calc()`、`color-mix()`、HTML/SVG 标记、分号和样式块。
- `density` 只能是 `compact/comfortable`；`motion_preset` 只能是 `none/subtle/standard/command`。
- Manifest 最大 64 KiB；首期不接收数组、额外文件或自由 CSS/JavaScript。
- 服务端保存 Manifest、Token 快照、SHA-256 和操作者；浏览器校验只用于预览反馈。

## 5. 内置主题

### 5.1 `zenvis-naive-light`

定位：现有 ZenVis 主站、Naive UI 风格和 Plugin UI Contract v1 的兼容基线。

要求：

- 首次上线主题管理时成为默认活动主题；
- Token 由当前生产视觉值生成，避免首次升级改变已有页面；
- 同步生成 Naive UI、AMIS 和 ECharts 配置；
- 不可删除、不可被导入包覆盖；
- 自定义主题失败时始终可回退；
- 对旧 `STANDARD` 插件保持 v1 行为。

### 5.2 `zenvis-command-dark`

定位：图三方向的深色运营控制台主题，同时为未来 OneSOC `COCKPIT` 提供迁移基线。

要求：

- 使用暗色 surface、克制的边框与阴影和明确的危险/警告/成功语义；
- 优先保证表格、长文本、表单、权限状态和图表可读性，不做营销式高饱和装饰；
- 动效只用于状态变化、空间关系、刷新和加载；
- 为普通 `STANDARD` 页面提供完整暗色映射；
- 在 Contract v2 前不强制覆盖现有 `IMMERSIVE` 看板。

## 6. 运行时同步

### 6.1 主题快照

平台把一次可激活主题编译为不可变运行快照：

```json
{
  "theme_id": "zenvis-command-dark",
  "theme_version": "1.0.0",
  "theme_contract": "1.0.0",
  "mode": "dark",
  "density": "compact",
  "token_hash": "sha256:...",
  "compiled_at": "2026-08-17T15:00:00+08:00"
}
```

编译产物由平台代码生成，不执行主题提供的代码：

- CSS Variables；
- Naive UI `themeOverrides`；
- AMIS Adapter 参数；
- ECharts Theme/Palette；
- Motion 预设映射。

浏览器只消费已校验并激活的快照。活动主题切换使用 revision 或 Token hash 标识，避免浏览器、Nginx 和 iframe 继续命中旧资源。

### 6.2 主站和 Naive UI

- 在应用初始化时先读取活动主题快照，再挂载主 UI，减少闪白和布局跳变。
- 根节点设置稳定的 `data-zv-theme`、`data-zv-mode` 和 `data-zv-density`。
- Naive UI 从主题编译结果生成 `themeOverrides`；业务组件不单独覆盖品牌色和圆角。
- 用户预览只在当前会话生效，未激活主题不会写入全局活动指针。

### 6.3 AMIS 与 `STANDARD` iframe

继续使用 Plugin UI Contract 的版本化资源和生命周期握手。主题信息作为兼容性字段追加，不能破坏 v1 ready 消息：

```json
{
  "type": "zenvis:host-ui",
  "contractVersion": "1.0.0",
  "renderer": "amis@6.7",
  "profile": "STANDARD",
  "theme": {
    "id": "zenvis-command-dark",
    "version": "1.0.0",
    "mode": "dark",
    "density": "compact",
    "tokenHash": "sha256:..."
  }
}
```

同步要求：

- 父窗口校验目标 iframe 与 origin；子窗口校验 `event.source` 和 origin。
- iframe 在首次绘制前应用缓存的有效主题，握手后再校验最新 hash。
- 主题切换通过增量消息更新 CSS Variables，不要求重建业务页面或丢失筛选、分页和展开项。
- 同步失败时回退 `zenvis-naive-light`，显示可诊断错误但不泄露 Manifest 原文或内部路径。
- `LEGACY_UNSPECIFIED` 只保证旧行为，不承诺在所有主题下完整换肤。

### 6.4 ECharts

- 业务插件继续声明数据、series、轴类型、维度和布局。
- 平台 Chart Adapter 提供色板、文字、轴线、分隔线、tooltip、强调状态、loading 和 empty 样式。
- 主题切换时已挂载图表应用新 Palette/Theme，并执行 `resize`；不能让插件轮询重新发请求来完成换肤。
- 业务严重性使用语义色映射，不按 series 顺序猜测危险等级。
- `prefers-reduced-motion` 时关闭或极度缩短图表过渡。

### 6.5 `COCKPIT` 和 `IMMERSIVE`

- v1 `IMMERSIVE` 页面保持自包含，平台只提供容器、安全和导航消息。
- v2 `COCKPIT` 使用独立的版本化 Cockpit UI Kit，不能复用普通 AMIS DOM 选择器硬套大屏。
- Cockpit Runtime 可提供数字过渡、toast、skeleton、focus、状态徽标和图表主题，但 API 请求、刷新、业务状态和路由仍在插件。
- `IMMERSIVE` 页面只有显式 opt-in 时才接收基础 Theme Snapshot；未 opt-in 不因全局切换改变外观。

## 7. 系统管理 → UI 管理

### 7.1 菜单与权限

新增内置菜单：

```text
系统管理
└── UI 管理
```

建议权限：

| 权限 | 能力 | 默认角色 |
| --- | --- | --- |
| `system:ui-theme:view` | 查看活动主题、列表、兼容范围和校验报告 | 超级管理员、受权管理员 |
| `system:ui-theme:preview` | 创建当前会话预览 | 超级管理员、受权管理员 |
| `system:ui-theme:manage` | 粘贴/选择 JSON 创建主题、更新或删除非内置主题 | 超级管理员 |
| `system:ui-theme:activate` | 修改平台默认主题 | 超级管理员 |
| `system:ui-theme:rollback` | 在实现可选回滚接口后恢复历史有效快照 | 超级管理员 |

菜单权限只控制入口可见性。创建、更新、删除、激活以及可选回滚接口必须再次验证后端权限，并写入操作者、主题 revision、前后活动指针、校验结果和时间。

### 7.2 页面信息架构

UI 管理页面包含：

1. 当前活动主题：主题 ID、版本、模式、激活时间、操作者和快照 hash。
2. 内置主题：`zenvis-naive-light`、`zenvis-command-dark`，不可删除。
3. 自定义主题：状态、兼容范围、校验结果、使用范围和版本历史。
4. 预览工作区：主导航、菜单、表单、表格、弹窗、空态、错误态、AMIS、ECharts 和 Cockpit Fixture。
5. 激活历史：前后版本、成功/失败、回滚点和审计说明。
6. 兼容性提示：当前插件 UI Contract、旧插件兼容桥和不支持换肤的 `IMMERSIVE` 页面。

### 7.3 管理工作流

```text
粘贴或选择 manifest.json
  → Schema、Token 白名单与安全校验
  → POST/PUT 保存或更新草稿 revision
  → 会话级预览
  → 激活最新 revision，并在事务内发布
  → 更新全局活动指针和激活审计
  → 当前页热更新，刷新或新标签页读取活动主题
```

具体规则：

- 第一阶段没有显式 publish API；激活操作会发布最新草稿 revision。
- 预览不能影响其他用户，也不能改变插件、菜单或数据库业务数据。
- `STANDARD` 主站和插件页跟随主题热更新；`IMMERSIVE/EXTERNAL` 保持隔离，`COCKPIT` 留到 Contract v2。
- 激活事务支持可选 `expected_activation_version` 冲突校验；事务失败时活动指针不变。
- `DELETE` 归档未激活的自定义主题；内置主题和当前活动主题受保护，历史 revision 与激活审计保留。

### 7.4 配置作用域

第一期只支持：

- 平台全局默认主题；
- 当前管理员的会话级预览；
- `STANDARD` 与未来 `COCKPIT` 的 surface 映射。

后续再评估用户偏好、角色主题或租户主题。不得在第一期同时引入多层覆盖，否则会显著增加权限、缓存、回滚和问题复现复杂度。

## 8. 数据、API 与缓存建议

### 8.1 数据模型

建议使用平台 MySQL 保存：

- `t_sys_ui_theme`：主题逻辑身份、名称、内置标记、模式、状态、创建人和更新时间；
- `t_sys_ui_theme_revision`：保存 Manifest、SHA-256 和发布状态；草稿可原地更新，发布后的 revision 不可变，后续修改创建新草稿；
- `t_sys_ui_theme_active`：平台当前活动主题/revision 的唯一指针，并为未来 surface 扩展保留稳定边界；
- `t_sys_ui_theme_activation`：激活前后指针、操作者、原因、结果、失败信息和可选回滚关系。

数据库迁移只向前追加。内置主题由应用迁移或幂等初始化注册，不允许管理员修改或删除；公开 API 不暴露 revision 表的内部写能力。

### 8.2 API 草案

```text
GET    /api/v1/system/ui-theme/active          # 读取当前活动主题；唯一公开的安全运行投影
GET    /api/v1/system/ui-theme/list            # 超级管理员读取主题列表
POST   /api/v1/system/ui-theme                 # 粘贴/选择 JSON 后创建或导入主题
PUT    /api/v1/system/ui-theme/{id}            # 更新草稿；已发布主题则派生新草稿 revision
POST   /api/v1/system/ui-theme/{id}/activate   # 激活指定主题的有效 revision
DELETE /api/v1/system/ui-theme/{id}            # 删除未激活、非内置的自定义主题
GET    /api/v1/system/ui-theme/{id}/export     # 导出指定主题的最新 revision
```

核心 API 使用 singular `/api/v1/system/ui-theme`。写接口校验超级管理员权限、当前活动 revision 和请求幂等语义；响应不返回服务器文件路径、内部 revision 写接口或无关审计详情。

按 activation 回滚是后续扩展；如果启用，应继续使用 singular 前缀并补充权限、审计和冲突测试。独立 publish/archive/version API 不属于第一阶段公开契约，revision 由后端内部管理。

### 8.3 缓存

- Runtime Snapshot URL 带主题 ID、版本和 Token hash。
- `manifest.json` 管理接口响应不作为浏览器静态主题资源直接执行。
- HTML 入口和活动主题指针使用 `no-cache, must-revalidate`。
- 不可变编译产物可使用长缓存和 `immutable`，但 URL 必须包含 hash。
- Nginx、Service Worker、浏览器和 iframe 的缓存键必须包含主题版本。

## 9. Plugin UI Contract 兼容策略

### 9.1 Contract v1

v1 继续保证：

- `amis@6.7`；
- `STANDARD`、`IMMERSIVE`、`EXTERNAL`、`LEGACY_UNSPECIFIED` 的现有含义；
- 当前公开 `zv-*` 类；
- 既有 ready/host-ui 生命周期兼容；
- 当前插件未声明新字段时使用 `zenvis-naive-light`。

主题系统可以改变 Token 值，但不能让已有语义类突然承担不同结构责任。

### 9.2 Contract v2

v2 才引入：

- `COCKPIT` Profile；
- Cockpit 公共组件语义；
- `zv-code-block`、`zv-action-row`、`zv-stat-grid` 等新增公共类；
- Theme Snapshot 的强类型字段和兼容协商；
- 驾驶舱 Motion Runtime 与图表主题协同；
- 页面对主题 surface 的显式能力声明。

插件只有在完成 v2 测试并提高 `min_host_contract` 后才能依赖这些能力。平台应同时保留 v1 静态资源目录，不能原地覆盖。

## 10. OneSOC 与 Lubinsun 迁移

### 10.1 当前版本漂移

截至 2026-08-17：

| 插件 | `lubinsun` 分支源码 | 当前已安装 | 影响 |
| --- | --- | --- | --- |
| OneSOC | `2.7.8` | `2.7.9` | 源码版本低于运行版本，禁止直接构建安装或降级 |
| Lubinsun | `2.1.9` | `2.1.8` | 源码版本更高，可按正式升级流程验证并升级 |

OneSOC 当前活动 `overview.json` 和沉浸式 Dashboard 与源码文件一致，但已安装包描述符仍是 `2.7.9`。这只能证明两个活动资源相同，不能证明 Meta、推送任务、JAR、菜单、其他 UI 和包内容完全一致。

禁止：

- 用 OneSOC `2.7.8` 覆盖 `2.7.9`；
- 直接复制仓库文件到已安装插件目录；
- 仅修改一个版本字段绕过升级检查；
- 通过卸载重装试错，因为卸载可能删除 Meta 关联表和数据。

### 10.2 第一阶段保持不动

平台主题基础设施上线前，以下插件文件保持不动：

- OneSOC `04_ui/**`、`05_dashboard/**`、`08_menu/**`、根 `index.json`；
- Lubinsun `04_ui/**`、`08_menu/**`、根 `index.json`；
- 两个插件的动态 API、迁移、Meta、推送任务和运行配置。

第一阶段只修改 ZenVis 平台主题注册、管理 UI、Token 编译、AMIS/iframe/ECharts 同步和测试。

运行中的 Lubinsun `2.1.8` 仍有 `lubinsun-*` 选择器和固定色值。平台可以提供仅针对该已确认版本的临时兼容桥，但必须：

- 标注兼容版本范围；
- 不作为新插件示例；
- 在升级到 `2.1.9` 并完成验收后删除；
- 不扩展为长期业务选择器体系。

### 10.3 Lubinsun `2.1.9`

源码 `2.1.9` 的任务中心和审批中心已经迁移为严格 `STANDARD`，不自带主题色。正式升级至少验证：

- 连接、容量和 Skill；
- 创建任务、FIFO 排队和权威状态；
- 审批回复、中断和终态结果；
- Agent 不可达、Token 错误和权限拒绝；
- 主题切换时筛选、展开项、轮询和 Drawer 状态不丢失。

升级完成且运行稳定后再移除 2.1.8 兼容桥。

### 10.4 OneSOC `2.8.0` 迁移批次

OneSOC 必须先取得和审查当前 `2.7.9` 的完整基线，再从该基线创建高于已安装版本的 `2.8.0`。建议批次：

| 批次 | 范围 | 插件 Profile | 完成条件 |
| --- | --- | --- | --- |
| M0 基线 | 备份 2.7.9 包、资源清单、版本、活动配置、截图和 hash | 不变 | 能解释 2.7.8/2.7.9 全部差异 |
| M1 核心普通页 | 总览、资产、威胁、脆弱性、工单 | `STANDARD` v1 | 无硬编码主题；真实 API、跳转和状态不变 |
| M2 运营与调查 | IP 队列、IP 统计、工单详情、NSG/WAF 高频概览 | `STANDARD` v1/v2 兼容 | 公共代码块、动作行和指标语义收敛 |
| M3 长尾页面 | 普通列表、70 个详情和原始日志视图 | `STANDARD` | 全部进入严格契约清单 |
| M4 驾驶舱 | 当前安全态势大屏 | 先保持 `IMMERSIVE`，通过验收后迁到 `COCKPIT` v2 | `zenvis-command-dark` 下视觉回归达标，原布局和业务闭环不变 |

每批次都只能替换视觉表达，不能顺手修改实体、API、字段、统计口径和数据留存。

### 10.5 OneSOC 驾驶舱保真

必须留在插件：

- 搜索、KPI、事件看板、态势卡、事件表和详情栏的业务布局；
- 实体查询、工单摘要、刷新、fresh/stale/unavailable 状态机；
- IP/CVE/工单/威胁路由和处置建议；
- 业务响应式编排。

迁入平台：

- `--soc-*` 对应的颜色、表面、边框、文字、圆角、阴影和动效 Token；
- 通用按钮、卡片、面板、表格、状态徽标、toast、skeleton 和 focus 皮肤；
- ECharts 色板和通用动效；
- `prefers-reduced-motion` 统一行为。

迁移时先把当前表现固化为 `zenvis-command-dark` 的 Cockpit Fixture，再逐项替换。未达到视觉和交互基线前保持 `IMMERSIVE` 原文件作为回滚版本。

### 10.6 版本同步

OneSOC `2.8.0` 需要同步核对：

- 根 `index.json`；
- Maven `pom.xml`；
- Java 版本常量和测试；
- JAR 文件名与插件 `03_api`；
- README、CHANGELOG、UI Contract；
- 构建产物名称和升级说明。

只改主题 Manifest 不需要插件升级；修改插件 JSON、HTML、描述符或 Contract 声明则必须走正式插件升级。

## 11. 验证矩阵

### 11.1 功能与视觉

| 维度 | 验证项 |
| --- | --- |
| 内置主题 | `zenvis-naive-light`、`zenvis-command-dark` 均可预览、激活和回滚 |
| 主站 | 顶栏、侧栏、菜单、表单、表格、Dialog、Drawer、通知、登录态 |
| OneSOC `STANDARD` | 总览、资产、威胁、脆弱性、工单、IP 分析、详情 |
| Lubinsun `STANDARD` | 任务中心、审批中心、详情、权限按钮、结果 |
| Cockpit | 当前 OneSOC 大屏的 KPI、看板、详情、搜索、全屏和刷新 |
| 图表 | Palette、轴、图例、tooltip、empty、resize、主题切换 |
| 状态 | loading、empty、success、error、permission denied、stale、partial stale |
| 文本 | 长中文、长英文、长 ID、大数值、JSON、原始日志 |
| 动效 | hover、focus、loading、数字变化、图表动画、reduced-motion |

### 11.2 视口与交互

| 页面 | 视口 |
| --- | --- |
| 普通主站和 `STANDARD` | 1680、1280、1024 宽度，必要时补充 768 |
| OneSOC Cockpit | 1920×1080、1440×900、顶部导航后的 1366×708 |

每个视口验证：

- 根页面无意外横向滚动和双纵向滚动；
- 长列表只在内部滚动；
- 卡片点击、筛选参数和目标页面一致；
- 刷新、返回、直接 URL、权限拒绝和不存在记录可恢复；
- 主题切换不覆盖筛选、分页、展开项和输入。

### 11.3 兼容组合

| 宿主 | 插件 | 期望 |
| --- | --- | --- |
| 新主题宿主 | OneSOC 2.7.9 | v1 页面正常；旧 `IMMERSIVE` 不被强制换肤 |
| 新主题宿主 | OneSOC 2.8.0 | `STANDARD` 完整继承；迁移批次可独立验收 |
| 新主题宿主 | Lubinsun 2.1.8 | 临时兼容桥生效并显示升级提示 |
| 新主题宿主 | Lubinsun 2.1.9 | 严格 `STANDARD`，不依赖业务选择器 |
| 旧宿主 | 依赖 v2 的插件 | 安装/加载前因 `min_host_contract` 不满足而明确拒绝 |

### 11.4 安全和管理

- 导入包含 JS/CSS/HTML/SVG/远程 URL 时拒绝。
- 未知 Token、非法色值、超限字段和对比度失败时拒绝保存或激活。
- 无权限用户不能创建、更新、删除、激活或执行可选回滚。
- 菜单隐藏后，写 API 仍执行后端权限校验。
- iframe 消息来源不匹配时忽略并记录受限诊断。
- 激活并发冲突时拒绝后一请求，不静默覆盖。
- 审计记录包含前后主题、版本、hash、操作者、时间和结果。

## 12. 回滚矩阵

| 故障 | 自动动作 | 人工动作 | 数据影响 |
| --- | --- | --- | --- |
| Manifest 校验失败 | 保持原活动主题 | 修正后重新导入 | 无 |
| 编译快照失败 | 不更新活动指针 | 查看校验报告 | 无 |
| 激活健康检查失败 | 恢复上一有效快照 | 检查主站与 iframe 日志 | 无 |
| 浏览器命中旧主题 | hash 资源失效并重取 | 强制刷新仅作排障 | 无 |
| AMIS iframe 同步失败 | 回退 `zenvis-naive-light` | 检查握手和 origin | 无 |
| ECharts 换肤失败 | 使用内置安全 Palette | 检查 Chart Adapter | 无 |
| `zenvis-command-dark` 可读性不达标 | 回滚主题，不回滚插件 | 修正新主题版本 | 无 |
| Lubinsun 2.1.8 兼容异常 | 保留兼容桥或回退宿主快照 | 正式升级 2.1.9 | 无任务数据迁移 |
| OneSOC 2.8.0 升级失败 | 使用插件持久化快照恢复 | 保留现场并检查生命周期日志 | 依插件升级阶段，禁止卸载试错 |
| Cockpit 迁移视觉回归 | 保持/恢复原 `IMMERSIVE` HTML | 修正 `zenvis-command-dark` 或 Cockpit Kit | 无业务数据影响 |

主题回滚与插件回滚分离：主题问题只切换活动快照；插件升级问题使用插件生命周期恢复。不得为了恢复颜色而卸载 OneSOC 或清空运行数据。

## 13. 交付顺序

1. 固化 `zenvis-naive-light` Token、Fixture 和视觉快照。
2. 建立主题 Manifest Schema、安全校验、存储和编译器。
3. 实现 UI 管理菜单、权限、JSON 创建/更新、预览、激活、审计和回滚。
4. 打通 Vue/Naive UI、AMIS iframe 和 ECharts 的 Theme Snapshot。
5. 加入 Lubinsun 2.1.8 临时兼容桥并正式升级到 2.1.9。
6. 完成 `zenvis-command-dark` 的普通页面验证。
7. 对齐 OneSOC 2.7.9 基线，按 M0–M3 形成 2.8.0 普通页面升级。
8. 发布 Plugin UI Contract v2 和 Cockpit Fixture。
9. 将 OneSOC 驾驶舱按 M4 从自包含 `IMMERSIVE` 迁移为可主题化 `COCKPIT`。
10. 完成连续观察后删除已无消费者的插件专用兼容桥。

## 14. 完成定义

- `zenvis-naive-light` 上线前后视觉和交互基线无非预期变化。
- `zenvis-command-dark` 在主站、AMIS 和 ECharts 中语义一致且满足对比度要求。
- UI 管理具备后端权限、审计、预览、激活和一键回滚。
- 主题 Manifest 不能执行任意 JS/CSS，也不能加载远程资源。
- v1 插件无需改包即可继续运行；v2 插件有明确版本协商。
- OneSOC 与 Lubinsun 不再维护普通页面主题。
- OneSOC 2.8.0 高于已安装 2.7.9，升级不突破数据和资源所有权边界。
- Lubinsun 2.1.9 升级后可删除 2.1.8 临时兼容桥。
- 驾驶舱的布局、真实数据、刷新、错误、跳转和处置闭环均保持。
- 所有目标主题、Profile、视口、状态和版本组合均有真实验证结果和回滚路径。

## 关联文档

- [UI、看板与菜单](/03-插件开发与集成/UI看板与菜单.md)
- [插件与扩展架构](/06-架构设计/插件与扩展架构.md)
- [安全与权限架构](/06-架构设计/安全与权限架构.md)
- [插件生命周期与发布验证](/03-插件开发与集成/生命周期与发布验证.md)
- [升级与回滚](/02-安装部署与升级/升级与回滚.md)
