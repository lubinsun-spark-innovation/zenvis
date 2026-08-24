# Lubinsun 自动部署与发布控制器

`lubinsun-deploy` 是部署主机上的统一控制器。只有 `zenvis-frontend`、`zenvis-backend` 和 `zenvis-service-analyzer` 的 main Actions 可以通过专用 SSH key 调用生产部署；ZenVis 总仓库与 Lubinsun Agent 只做验证，插件工作流只测试和打包。生产 Token、数据库密码和 Provider 密钥始终只保存在服务器环境文件中。

## 单实例不变量

手工部署和上述三个生产 Actions 必须调用同一个 `lubinsun-deploy`，复用现有 Compose project、数据目录、容器名和端口：

| 组成 | 固定 Compose project | 现有入口 |
| --- | --- | --- |
| ZenVis 前后端与基础设施 | `zenvis` | Web `11000`、API `11001`、Vectum `11002` |
| Lubinsun Agent 前后端与执行器 | `lubinsun-test`（沿用历史名称） | API `192.168.100.20:18000`、Web `192.168.100.20:17000` |
| ZenVis Analyzer | `deploy` | HTTP `18080` |

禁止用新的 project 名或另一组端口并行启动“新版”；发布只允许在上述实例中原地重建目标容器。环境文件与数据卷保持服务器本地，不进入 Git。

Agent 受控手工部署固定组合 main 的 `docker-compose.yml` 与 `agent-compose.automation.yml`，不使用会切换为 host network 和另一套固定容器名的 `docker-compose.server.yml`。首次接管时从正在运行的 `lubinsun-test-backend-1` 与 `lubinsun-test-frontend-1` 读取真实绑定地址和端口，写入权限为 `600` 的服务器运行状态；后续手工部署复用该状态、`lubinsun-test_agent-data`、skills 挂载与现有 MySQL 数据目录。Agent Actions 不调用生产部署。


## 三组件自动部署固定流程

1. 取得跨仓库 `flock`，防止 frontend、backend 和 analyzer 工作流同时修改 Compose 状态。
2. 检查 CPU 架构、内存、Swap、磁盘、NTP、Docker/Compose、环境文件权限和模板占位值。
3. 校验 GitHub 仓库白名单、40 位 SHA 与 `origin/main`，旧事件被更新 main 取代时安全跳过。
4. 用固定版本的 Maven、Node 或 Go 工具链从当前 main SHA 重新生成产物；镜像写入并复核 `org.opencontainers.image.revision`。
5. Backend 数据变更前创建一致性备份；Analyzer 发布前备份生产环境、区域配置和旧镜像；应用失败时自动恢复旧镜像或一致性备份。
6. 验证目标容器状态、原端口 HTTP 入口和业务 smoke，再写入 current/previous 发布台账。

## Backend 测试隔离

Backend main 当前有 9 个不能在生产主机直接运行的测试类：5 个完整 Spring 上下文/集成测试会执行 MySQL、ClickHouse 或 Redis 操作；另外 4 个存在未入库 JMR fixture、宿主机 OTF 字体兼容或过期 Mockito stub 等 main 测试债务。自动部署明确隔离这 9 类并运行其余 552 个测试，绝不把测试连接到生产数据库，也不读取生产 `open_config`。

这不是静默 `skipTests`：工作流摘要和控制器日志都会列出隔离原因。长期方案是给 Backend 增加专用 test profile 和一次性 MySQL/ClickHouse/Redis fixture，并把 JMR fixture、可嵌入的 glyf-based CJK TTF 与 Mockito 修复纳入 main；每完成一项就从 `BACKEND_SAFE_TEST_PATTERN` 和 Backend workflow 中删除对应隔离项，最终恢复 `clean verify` 全量门禁。

## 插件迭代

- main push 只做 JSON/YAML 校验、Java 测试、版本严格递增校验和打包，生成包含 `tar.gz` 与 SHA-256 的 Actions Artifact。
- 插件工作流没有 production environment、SSH 凭据、服务器命令或安装 API 调用，不能改变当前运行插件。
- 正式安装入口只有 ZenVis 插件页面：下载并校验 Artifact 后手动上传。
- 插件描述 `index.json` 与动态 API `pom.xml` 必须保持同一 SemVer；只有插件内容或构建入口变化时，main 版本才必须严格递增。

## Analyzer 迭代

Analyzer 沿用现有 `deploy` project、容器名和 `18080` 端口，只原地替换一个带 main SHA 标签的镜像。`deploy/topology.env` 含连接配置，始终保留在服务器且权限为 `600`；`analyzer-zones.json` 只含区域映射，以只读方式挂载给非 root `topology` 用户，因此持久权限为 `644`。公开地址和服务注册统一使用 `192.168.100.20:18080`。发布时先备份区域配置和旧镜像，失败或手工回滚时一起恢复；健康门禁检查镜像 ID、`/healthz`、`/readyz` 和 10 秒稳定窗口内的重启次数。

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

## 手工回滚

```bash
/home/lubinsun/.local/bin/lubinsun-deploy status
/home/lubinsun/.local/bin/lubinsun-deploy rollback zenvis-frontend
```

可回滚组件包括 `zenvis`、`zenvis-backend`、`zenvis-frontend`、`zenvis-analyzer`、`plugin-lubinsun`、`plugin-onesoc` 和 `lubinsun-agent`。会覆盖 ZenVis 数据的整套备份只允许回滚“全系统最后一次成功变更”，旧备份会被拒绝，避免覆盖后来发布的其他组件。数据库备份不在普通 Agent 镜像回滚时自动覆盖，避免抹掉发布后产生的新任务；需要数据恢复时必须进入维护窗口并人工确认。

## GitHub Secrets

仅以下三个仓库的 `production` Environment 需要部署 Secrets：`zenvis-frontend`、`zenvis-backend`、`zenvis-service-analyzer`。

- `DEPLOY_HOST`
- `DEPLOY_PORT`
- `DEPLOY_USER`
- `DEPLOY_SSH_PRIVATE_KEY`
- `DEPLOY_SSH_KNOWN_HOSTS`

必须固定 `known_hosts`，禁止在工作流中以 `ssh-keyscan` 动态信任未知主机。SSH 密码不用于自动部署；专用公钥在 `authorized_keys` 中以 `restrict,command="/home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry"` 限制，只允许 frontend、backend 和 analyzer 三个仓库调用对应部署命令。
