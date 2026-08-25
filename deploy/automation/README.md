# Lubinsun 自动部署与发布控制器

`lubinsun-deploy` 是部署主机上的唯一生产部署控制器。ZenVis 编排、ZenVis Frontend、ZenVis Backend、Analyzer 和 Lubinsun Agent 的 main Actions，以及服务器上的本地手工部署，都调用同一套版本判断、构建、备份、Compose、健康检查和回滚逻辑。插件工作流负责测试、可重复打包和发布不可变 GitHub Release，但不自动安装。生产 Token、数据库密码和 Provider 密钥始终只保存在服务器环境文件中。

## 单实例不变量

手工部署和上述三个生产 Actions 必须调用同一个 `lubinsun-deploy`，复用现有 Compose project、数据目录、容器名和端口：

| 组成 | 固定 Compose project | 现有入口 |
| --- | --- | --- |
| ZenVis 前后端与基础设施 | `zenvis` | Web `11000`、API `11001`、Vectum `11002` |
| Lubinsun Agent 前后端与执行器 | `lubinsun-test`（沿用历史名称） | API `192.168.100.20:18000`、Web `192.168.100.20:17000` |
| ZenVis Analyzer | `deploy` | 宿主机回环 `127.0.0.1:18080`；浏览器入口 `/analyzer/` |

禁止用新的 project 名或另一组端口并行启动“新版”；发布只允许在上述实例中原地重建目标容器。环境文件与数据卷保持服务器本地，不进入 Git。

Agent 固定组合发布源码快照内的 `docker-compose.yml` 与版本化的 `deploy/docker-compose.production.yml`，不使用会切换为 host network 和另一套固定容器名的 `docker-compose.server.yml`。首次接管时从正在运行的容器发现真实绑定地址、端口和 MySQL bind mount，写入权限为 `600` 的服务器运行状态；后续部署复用该状态、`lubinsun-test_agent-data` 与现有 MySQL 数据目录。系统 Skill 使用镜像内与源码摘要一致的副本，不再直接挂载开发工作树，避免本地编辑绕过发布立即影响运行环境。

## 统一版本与幂等规则

- 每个组件按真实部署输入计算 SHA-256 内容摘要。README、AGENTS 或 Workflow 等不进入应用镜像的文件不会制造无意义重建。
- 本地手工部署会用临时 Git index 捕获当前工作树，允许包含尚未提交的修改，但不会修改用户现有 index；随后从隔离快照构建。
- Action 从 `origin/main` 的提交树创建隔离快照，绝不切换或覆盖服务器上的开发工作树。
- 镜像使用 `src-<digest>` 不可变标签，并写入 `org.opencontainers.image.revision`、`org.opencontainers.image.source-digest` 与源码仓库标签。
- reconcile 直接检查运行容器的 image ID、镜像内容摘要，并将 `docker compose config --hash` 与每个容器的实际 `com.docker.compose.config-hash` 对照，再检查端口/挂载不变量和健康状态。完全一致时记录 `no-op` 并跳过构建、备份和容器重建。
- 因此，本地修改先部署、之后原样 commit/push 时，Action 仍会完成 CI 验证，但服务器识别到相同内容摘要后不会再次部署。
- 五个仓库的每次 main push 都会创建 reconcile 工作流，避免路径过滤与服务器摘要规则不一致造成漏部署；文档等非部署输入提交会在服务器快速 `no-op`。
- 旧 Action 事件若只被文档等不影响部署的 main 提交取代，会按当前 main 的等价部署内容继续校验；若部署内容已经变化，则让较新的工作流接管。
- 不得在包含部署输入变更的提交中使用 `[skip ci]`；它会让 GitHub 不创建工作流，服务器也就没有 reconcile 事件。仅文档/工作流元数据提交可以按团队规则使用。

## 自动与手工部署固定流程

1. 取得跨仓库 `flock`，防止五个仓库的工作流或本地部署同时修改 Compose 状态。
2. 检查 CPU 架构、内存、Swap、磁盘、NTP、Docker/Compose、环境文件权限和模板占位值。
3. 获取本地工作树或 GitHub main 的隔离源码快照，计算部署输入摘要。
4. 对比服务器实际容器镜像 ID、内容摘要、逐服务 Compose config hash、端口/挂载/密钥注入和健康状态；一致则 `no-op`。
5. 用固定版本的 Maven、Node 或 Go 工具链生成产物；镜像元数据必须与目标 revision 和内容摘要同时一致。
6. ZenVis 数据变更前创建一致性备份；Agent Backend 或运行编排变更前短暂停止应用写入，成对备份 MySQL 与 `agent-data` workspace；Analyzer 备份区域配置、环境与旧镜像。
7. 只在固定 Compose project 中原地替换受影响服务，不创建第二套端口、容器或数据卷。
8. 验证目标容器 image ID、内容摘要、原端口、API readiness、Web、执行器和业务 smoke，再原子写入 current/previous/last-verification 台账；失败自动切回旧镜像与旧源码快照。

Agent 的 Backend、Frontend 与 managed stack 分别计算摘要。每次发布还会记录 migration 文件逐项 SHA-256；历史 migration 被删除或改写时会在启动新 Backend 前拒绝部署。回滚优先做兼容的镜像/配置切换；若数据库含目标旧版本没有的 migration，控制器会先建立 rollback-safety 备份，再成对恢复该发布前的 MySQL 与 workspace，避免旧应用直接读取不兼容结构。

## 本地开发后的正式手工部署

本地开发、提交前验收和 GitHub Actions 共用同一个入口。以下命令部署当前工作树，而不是强制拉取 GitHub：

```bash
/home/lubinsun/.local/bin/lubinsun-deploy deploy-local zenvis
/home/lubinsun/.local/bin/lubinsun-deploy deploy-local zenvis-backend
/home/lubinsun/.local/bin/lubinsun-deploy deploy-local zenvis-frontend
/home/lubinsun/.local/bin/lubinsun-deploy deploy-local zenvis-analyzer
/home/lubinsun/.local/bin/lubinsun-deploy deploy-local lubinsun-agent
/home/lubinsun/.local/bin/lubinsun-deploy verify all
```

只运行受影响的组件。`lubinsun-agent` 会分别计算 Backend（含执行器、迁移和系统 Skill）、Frontend 与 managed stack 摘要，并按实际服务 config hash 只重建发生变化的容器；纯 Frontend 变化不会触碰 Backend、执行器或数据库。执行完先用 `status` 核对，再 commit/push。若 push 内容与本地已部署内容相同，Action 的服务器阶段输出 `no-op`。

## Backend 测试隔离

Backend main 当前有 9 个不能在生产主机直接运行的测试类：5 个完整 Spring 上下文/集成测试会执行 MySQL、ClickHouse 或 Redis 操作；另外 4 个存在未入库 JMR fixture、宿主机 OTF 字体兼容或过期 Mockito stub 等 main 测试债务。自动部署明确隔离这 9 类并运行其余 552 个测试，绝不把测试连接到生产数据库，也不读取生产 `open_config`。

这不是静默 `skipTests`：工作流摘要和控制器日志都会列出隔离原因。长期方案是给 Backend 增加专用 test profile 和一次性 MySQL/ClickHouse/Redis fixture，并把 JMR fixture、可嵌入的 glyf-based CJK TTF 与 Mockito 修复纳入 main；每完成一项就从 `BACKEND_SAFE_TEST_PATTERN` 和 Backend workflow 中删除对应隔离项，最终恢复 `clean verify` 全量门禁。

## 插件迭代

- main push 做 JSON/YAML 校验、Java 测试、版本严格递增校验和可重复打包，同时生成 Actions Artifact，并将 `tar.gz` 与 SHA-256 发布到对应的不可变 GitHub Release。
- 插件工作流没有 production environment、SSH 凭据、服务器命令或安装 API 调用，不能改变当前运行插件。
- 正式安装入口只有 ZenVis 插件页面：从 GitHub Release 下载 `tar.gz` 与 `.sha256`，校验通过后手动上传。
- 插件描述 `index.json` 与动态 API `pom.xml` 必须保持同一 SemVer；只有插件内容或构建入口变化时，main 版本才必须严格递增。
- Release tag 固定指向生成包的源码提交；重复执行同一版本只会校验 tag、源码提交和包摘要并安全跳过，不覆盖已有资产。

## Analyzer 迭代

Analyzer 沿用现有 `deploy` project、容器名和容器端口 `18080`，只原地替换一个带 main SHA 标签的镜像。宿主机发布端口强制绑定 `127.0.0.1:18080`，不得绑定 `0.0.0.0`、局域网地址或直接加入公网反代；部署前的 Compose 安全不变量检查会拒绝这类配置。浏览器统一使用 ZenVis 同源入口 `/analyzer/`，由 ZenVis 前端 Nginx 先向 Backend `GET /api/v1/system/login/session/check` 发起只转发 Cookie、无请求体的鉴权子请求，再通过 Docker 内网转发给 Analyzer，API 和 WebSocket 也必须使用此前缀。鉴权接口只接受 Cookie 中的有效 `JSESSIONID`：成功返回 `204`，缺失或过期返回 `401`，Bearer Token 不能替代浏览器会话。

`deploy/topology.env` 含连接配置，始终保留在服务器且权限为 `600`；`analyzer-zones.json` 只含区域映射，以只读方式挂载给非 root `topology` 用户，因此持久权限为 `644`。服务注册与服务器侧健康检查可以继续使用本机可达地址，但它们不是浏览器公开入口。Nginx 向上游保留 `/analyzer/` 前缀，由 Analyzer 路由统一识别并在内部剥离；这样页面生成的静态资源、API 和 WebSocket 路径保持一致。发布时先备份区域配置和旧镜像，失败或手工回滚时一起恢复；健康门禁从宿主机回环检查镜像 ID、`/healthz`、`/readyz` 和 10 秒稳定窗口内的重启次数。

### Analyzer 鉴权入口验收

发布 ZenVis Backend、Analyzer 和 Frontend 后依次确认：

1. `docker compose config` 中 Analyzer 的唯一发布规则是 `127.0.0.1:18080:18080`，宿主机局域网地址不能直接访问该端口。
2. 未携带有效 ZenVis 会话访问 `/analyzer/`、`/analyzer/api/v1/topology/snapshot` 或发起 `/analyzer/ws/topology` 握手时返回 `401`。
3. 已登录用户通过 `https://<ZenVis域名>/analyzer/` 加载页面，静态资源、快照 API 和 WebSocket 均保持同源，浏览器中不再出现 `192.168.*:18080` 请求。
4. Analyzer 独立替换或暂时不可用时，ZenVis 主站仍能启动；Analyzer 恢复后 Nginx 通过 Docker DNS 自动解析新容器地址。

当前 main 有两个测试硬编码依赖未入库的相邻私有仓库 fixture。工作流明确只排除这两个测试名，自动执行所有其他现有及未来测试并给出 warning；维护者把 fixture 移入本仓库 `testdata` 后，应立即删除排除逻辑并恢复 `go test ./...` 全量门禁。

## 主机安装

```bash
install -m 0755 deploy/automation/lubinsun-deploy /home/lubinsun/.local/bin/lubinsun-deploy
install -m 0755 deploy/automation/lubinsun-deploy-ssh-entry /home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry
/home/lubinsun/.local/bin/lubinsun-deploy doctor
```

所有 Node/Corepack 安装、测试和构建命令都会移除宿主机可能存在的 `NODE_TLS_REJECT_UNAUTHORIZED`，依赖下载必须通过正常 TLS 证书校验；禁止通过关闭 TLS 来绕过 registry 证书或网络问题。

主机的部署 `umask` 保持 `077` 以保护备份、环境文件和清单；只有即将复制进 Nginx 镜像的 `dist` 静态目录会显式归一化为目录 `0755`、文件 `0644`，避免 Nginx 非 root 工作进程返回 403。

本机优先使用 `/home/lubinsun/.local/jvm/temurin-17`、`/home/lubinsun/.local/lib/apache-maven-3.9.11` 与固定的 Node home；它们必须通过 `doctor` 的版本检查，当前 Node `24.15.0` 满足前端 `^20.19.0 || >=22.12.0` 且 Corepack 固定 Yarn `1.22.22`。缺少主机工具链时回退到固定 Maven/Temurin 或 Node 22 Docker 镜像。Java/Maven 来自 Adoptium 与 Apache 官方发行包，并在安装前按官方元数据校验 SHA-256/SHA-512。

运行状态位于 `/home/lubinsun/.local/state/lubinsun-deploy`，权限为当前部署用户私有。不要提交这里的备份、清单或环境文件。

源码快照、一致性备份和 SSH 部署任务日志不会在发布过程中按时间盲删。磁盘需要整理时显式执行 `lubinsun-deploy gc 3`；它会保留每类至少 3 个未引用恢复点和每组件至少 3 个已完成任务，永远跳过 current/previous/活动源码指针引用的目录、校验失败的备份、结构异常的快照以及尚无最终状态的任务。

## 手工回滚

```bash
/home/lubinsun/.local/bin/lubinsun-deploy status
/home/lubinsun/.local/bin/lubinsun-deploy rollback zenvis-frontend
```

可回滚组件包括 `zenvis`、`zenvis-backend`、`zenvis-frontend`、`zenvis-analyzer` 和 `lubinsun-agent`。插件由 ZenVis 页面手动上传与管理，不由控制器自动安装或回滚。会覆盖 ZenVis 数据的整套备份只允许回滚“全系统最后一次成功变更”，旧备份会被拒绝，避免覆盖后来发布的其他组件。Agent 只有在数据库 migration 无法向目标版本兼容时才恢复配对数据；该操作会明确创建 rollback-safety 恢复点。

Analyzer 镜像回滚仍保持 `127.0.0.1:18080` 的安全绑定；回滚不会重新开放旧的局域网或公网端口。若鉴权链路发布失败，应按 `zenvis`（恢复挂载的 Nginx 配置）→ `zenvis-analyzer` → `zenvis-backend` 的逆序回滚相关组件，并在外层反代继续禁止直通 `18080`。

## GitHub Secrets

以下五个仓库的 `production` Environment 使用同一组部署 Secrets：`zenvis`、`zenvis-frontend`、`zenvis-backend`、`zenvis-service-analyzer`、`lubinsun_agent`。

- `DEPLOY_HOST`
- `DEPLOY_PORT`
- `DEPLOY_USER`
- `DEPLOY_SSH_PRIVATE_KEY`
- `DEPLOY_SSH_KNOWN_HOSTS`

必须固定 `known_hosts`，禁止在工作流中以 `ssh-keyscan` 动态信任未知主机。SSH 密码不用于自动部署；专用公钥在 `authorized_keys` 中以 `restrict,command="/home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry"` 限制，只允许上述五个仓库调用各自白名单中的部署命令。受限入口用 `nohup + setsid` 启动私有后台任务，并把日志与最终退出码写入状态目录；正常连接会等待并回传结果，Actions 的 SSH 客户端临时断线也不会停在“服务已停止但备份未完成”的中间状态。
