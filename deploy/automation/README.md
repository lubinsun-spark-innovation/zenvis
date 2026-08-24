# Lubinsun 全系统自动部署

`lubinsun-deploy` 是部署主机上的统一控制器。各产品仓库的 GitHub Actions 只负责测试并通过专用 SSH key 调用它，生产 Token、数据库密码和 Provider 密钥始终只保存在服务器环境文件中。

## 单实例不变量

手工部署和 GitHub Actions 都必须调用同一个 `lubinsun-deploy`，复用现有 Compose project、数据目录、容器名和端口：

| 组成 | 固定 Compose project | 现有入口 |
| --- | --- | --- |
| ZenVis 前后端与基础设施 | `zenvis` | Web `11000`、API `11001`、Vectum `11002` |
| Lubinsun Agent 前后端与执行器 | `lubinsun-test`（沿用历史名称） | API `192.168.100.20:18000`、Web `192.168.100.20:17000` |
| ZenVis Analyzer | `deploy` | HTTP `18080` |

禁止用新的 project 名或另一组端口并行启动“新版”；发布只允许在上述实例中原地重建目标容器。环境文件与数据卷保持服务器本地，不进入 Git。


## 固定流程

1. 取得跨仓库 `flock`，防止多个仓库同时修改 Compose、插件或数据库。
2. 检查 CPU 架构、内存、Swap、磁盘、NTP、Docker/Compose、环境文件权限和模板占位值。
3. 校验 GitHub 仓库白名单、40 位 SHA 与 `origin/main`，旧事件被更新 main 取代时安全跳过。
4. 用固定版本的 Maven/Node/Go 工具链从当前 main SHA 重新生成产物；镜像写入并复核 `org.opencontainers.image.revision`，插件记录包 SHA-256。
5. 数据库/插件变更前创建一致性备份；Analyzer 发布前备份生产环境、区域配置和旧镜像；应用失败时恢复旧镜像或 ZenVis 一致性备份。
6. 验证容器状态、HTTP 入口、插件精确版本与业务 smoke，再写入 current/previous 发布台账。

## Backend 测试隔离

Backend main 当前有 9 个不能在生产主机直接运行的测试类：5 个完整 Spring 上下文/集成测试会执行 MySQL、ClickHouse 或 Redis 操作；另外 4 个存在未入库 JMR fixture、宿主机 OTF 字体兼容或过期 Mockito stub 等 main 测试债务。自动部署明确隔离这 9 类并运行其余 552 个测试，绝不把测试连接到生产数据库，也不读取生产 `open_config`。

这不是静默 `skipTests`：工作流摘要和控制器日志都会列出隔离原因。长期方案是给 Backend 增加专用 test profile 和一次性 MySQL/ClickHouse/Redis fixture，并把 JMR fixture、可嵌入的 glyf-based CJK TTF 与 Mockito 修复纳入 main；每完成一项就从 `BACKEND_SAFE_TEST_PATTERN` 和 Backend workflow 中删除对应隔离项，最终恢复 `clean verify` 全量门禁。

## 插件迭代

- main push 只做 JSON/YAML、Java 测试、版本严格递增校验和打包，生成包含原始 `tar.gz` 与 `SHA-256` 的 Actions Artifact，不自动改变生产插件。
- 正式安装入口仍是 ZenVis 插件页面：下载并校验 Artifact 后手动上传。需要远程操作时，也可手动触发插件工作流并明确勾选生产部署；它调用的仍是 ZenVis 正式升级 API。
- 插件描述 `index.json` 与动态 API `pom.xml` 必须保持同一 SemVer；每次涉及插件内容的 main push 必须严格高于推送前 main 版本。
- 每次安装前创建 ZenVis 数据与配置一致性备份；安装后核对精确版本、包 SHA-256 和业务 smoke，失败则恢复整套备份。

本次把临时 `lubinsun` 分支插件切回正式 main 是一次性基线迁移。若服务器临时版本号更高，控制器会在备份后以带包名、ID、当前版本和 `INSTALLED` 状态条件的 SQL 将版本元数据暂存为 `0.0.0`，再调用正式升级 API 安装未经改写的 main 包。基线完成后禁止再次降版本，后续只按 main SemVer 正向递增。

## Analyzer 迭代

Analyzer 沿用现有 `deploy` project、容器名和 `18080` 端口，只原地替换一个带 main SHA 标签的镜像。`deploy/topology.env` 始终保留在服务器且权限为 `600`；`configs/zones.json` 由 main 管理，发布时先备份再更新，失败或手工回滚时与旧镜像一起恢复。健康门禁同时检查容器实际 image ID、`/healthz`、`/readyz` 和 10 秒稳定窗口内的重启次数。

当前 main 有两个测试硬编码依赖未入库的相邻私有仓库 fixture。工作流明确只排除这两个测试名，自动执行所有其他现有及未来测试并给出 warning；维护者把 fixture 移入本仓库 `testdata` 后，应立即删除排除逻辑并恢复 `go test ./...` 全量门禁。

## 主机安装

```bash
install -m 0755 deploy/automation/lubinsun-deploy /home/lubinsun/.local/bin/lubinsun-deploy
install -m 0755 deploy/automation/lubinsun-deploy-ssh-entry /home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry
/home/lubinsun/.local/bin/lubinsun-deploy doctor
```

本机优先使用 `/home/lubinsun/.local/jvm/temurin-17` 与 `/home/lubinsun/.local/lib/apache-maven-3.9.11`；两者必须同时存在且通过 `doctor` 的精确版本检查。未安装时回退到固定 Maven/Temurin Docker 镜像。当前主机工具链来自 Adoptium 与 Apache 官方发行包，并在安装前按官方元数据校验 SHA-256/SHA-512。

运行状态位于 `/home/lubinsun/.local/state/lubinsun-deploy`，权限为当前部署用户私有。不要提交这里的备份、清单或环境文件。

## 手工回滚

```bash
/home/lubinsun/.local/bin/lubinsun-deploy status
/home/lubinsun/.local/bin/lubinsun-deploy rollback zenvis-frontend
```

可回滚组件包括 `zenvis`、`zenvis-backend`、`zenvis-frontend`、`zenvis-analyzer`、`plugin-lubinsun`、`plugin-onesoc` 和 `lubinsun-agent`。会覆盖 ZenVis 数据的整套备份只允许回滚“全系统最后一次成功变更”，旧备份会被拒绝，避免覆盖后来发布的其他组件。数据库备份不在普通 Agent 镜像回滚时自动覆盖，避免抹掉发布后产生的新任务；需要数据恢复时必须进入维护窗口并人工确认。

## GitHub Secrets

七个仓库需要以下 Secrets；具备 Admin 权限的仓库使用 `production` Environment，只有 Maintain 权限的私有仓库暂用 repository-level Actions Secrets：

- `DEPLOY_HOST`
- `DEPLOY_PORT`
- `DEPLOY_USER`
- `DEPLOY_SSH_PRIVATE_KEY`
- `DEPLOY_SSH_KNOWN_HOSTS`

必须固定 `known_hosts`，禁止在工作流中以 `ssh-keyscan` 动态信任未知主机。SSH 密码不用于自动部署；专用公钥在 `authorized_keys` 中以 `restrict,command="/home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry"` 限制，只允许七个白名单仓库调用对应组件的部署命令。
