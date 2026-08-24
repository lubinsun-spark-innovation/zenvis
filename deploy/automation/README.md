# Lubinsun 全系统自动部署

`lubinsun-deploy` 是部署主机上的统一控制器。各产品仓库的 GitHub Actions 只负责测试并通过专用 SSH key 调用它，生产 Token、数据库密码和 Provider 密钥始终只保存在服务器环境文件中。

## 固定流程

1. 取得跨仓库 `flock`，防止多个仓库同时修改 Compose、插件或数据库。
2. 检查 CPU 架构、内存、Swap、磁盘、NTP、Docker/Compose、环境文件权限和模板占位值。
3. 校验 GitHub 仓库白名单、40 位 SHA 与 `origin/main`，旧事件被更新 main 取代时安全跳过。
4. 在隔离的 Maven/Node 构建容器中从当前 main SHA 重新生成产物；镜像写入并复核 `org.opencontainers.image.revision`，插件记录包 SHA-256。
5. 数据库/插件变更前创建一致性备份；应用失败时恢复旧镜像或 ZenVis 一致性备份。
6. 验证容器状态、HTTP 入口、插件精确版本与业务 smoke，再写入 current/previous 发布台账。

正式插件包保持 main 中的原始版本不变。若服务器上的临时 `lubinsun` 插件版本号更高，控制器会先停机创建 ZenVis 数据与配置一致性备份，再以带包名、ID、当前版本和 `INSTALLED` 状态条件的 SQL 将版本元数据临时置为 `0.0.0`，随后仍调用正式升级 API 安装未经改写的 main 包。任何预检、升级、精确版本或业务 smoke 失败都会恢复整套一致性备份。

## 主机安装

```bash
install -m 0755 deploy/automation/lubinsun-deploy /home/lubinsun/.local/bin/lubinsun-deploy
install -m 0755 deploy/automation/lubinsun-deploy-ssh-entry /home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry
/home/lubinsun/.local/bin/lubinsun-deploy doctor
```

运行状态位于 `/home/lubinsun/.local/state/lubinsun-deploy`，权限为当前部署用户私有。不要提交这里的备份、清单或环境文件。

## 手工回滚

```bash
/home/lubinsun/.local/bin/lubinsun-deploy status
/home/lubinsun/.local/bin/lubinsun-deploy rollback zenvis-frontend
```

可回滚组件包括 `zenvis`、`zenvis-backend`、`zenvis-frontend`、`plugin-lubinsun`、`plugin-onesoc` 和 `lubinsun-agent`。会覆盖 ZenVis 数据的整套备份只允许回滚“全系统最后一次成功变更”，旧备份会被拒绝，避免覆盖后来发布的其他组件。数据库备份不在普通 Agent 镜像回滚时自动覆盖，避免抹掉发布后产生的新任务；需要数据恢复时必须进入维护窗口并人工确认。

## GitHub Secrets

六个仓库的 `production` Environment 需要以下 Secrets：

- `DEPLOY_HOST`
- `DEPLOY_PORT`
- `DEPLOY_USER`
- `DEPLOY_SSH_PRIVATE_KEY`
- `DEPLOY_SSH_KNOWN_HOSTS`

必须固定 `known_hosts`，禁止在工作流中以 `ssh-keyscan` 动态信任未知主机。SSH 密码不用于自动部署；专用公钥在 `authorized_keys` 中以 `restrict,command="/home/lubinsun/.local/bin/lubinsun-deploy-ssh-entry"` 限制，只允许六个仓库调用白名单部署命令。
