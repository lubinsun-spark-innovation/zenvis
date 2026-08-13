# Zenvis GitHub Actions 生产部署

## 架构

- 前端由 Cloudflare Workers Static Assets 托管，域名为 `soc.lubinsun.2333123.xyz`。
- Worker 将同域的 `/zenvis/*` 请求转发到 `https://apisoc.lubinsun.2333123.xyz/*`，沿用前端现有的 Cookie 和接口路径约定。
- 阿里云服务器运行 Kafka、Redis、Redis Stack、MySQL、ClickHouse、Zenvis 后端和 Vectum。
- 后端只监听 `127.0.0.1:11001`，公网入口由已经配置好的 `apisoc.lubinsun.2333123.xyz` 反向代理提供。
- 生产数据保存在服务器 `/root/lubinsun/zenvis/data`，每次发布只更新镜像、编排文件和版本化配置，不覆盖数据目录。

## 分支与触发方式

- `zenvis`：`feature/aliyun-cloudflare-deployment-20260813`
- `zenvis-backend`：`feature/aliyun-cloudflare-deployment-20260813`
- `zenvis-frontend`：`feature/frontend-ui-revision-20260810`

三个分支都直接推送到 `lubinsun-spark-innovation` 组织仓库，不修改 `main`，也不向上游项目创建 Pull Request。

- 修改后端分支会执行 505 项不依赖外部服务的后端单元测试、构建 Docker 镜像并部署整套服务。依赖 MySQL、ClickHouse 和 Redis 的集成测试保留在完整测试环境执行。
- 修改 `zenvis/deploy` 会用指定的后端分支重新构建并部署整套服务。
- 修改前端分支会执行类型检查和单元测试，然后发布 Cloudflare Worker。

## GitHub Secrets

服务端部署仓库需要：

- `SERVER_HOST`
- `SERVER_USER`
- `SERVER_SSH_KEY`
- `SERVER_SSH_KNOWN_HOSTS`（可选；未设置时由流水线首次扫描）
- `ZENVIS_BOOTSTRAP_SUPER_ADMIN_PASSWORD`
- `ZENVIS_BOOTSTRAP_ADMIN_PASSWORD`

前端仓库需要：

- `CF_ACCOUNT_ID`
- `CF_API_TOKEN`

引导管理员密码仅在服务器第一次生成 `.env` 时写入，以后的部署不会覆盖服务器运行时密码。

## 服务器目录与回滚

生产目录为 `/root/lubinsun/zenvis`。发布前会把现有 `.env`、Compose 文件和配置保存到 `backups/release-日期时间.tar.gz`。健康检查失败时，脚本会恢复上一个发布包并重新启动后端；MySQL、ClickHouse、Redis、Kafka 和 Vectum 的数据目录始终保留。

服务器排查命令：

```bash
cd /root/lubinsun/zenvis
docker compose -f docker-compose.yml -f docker-compose.production.yml ps
docker compose -f docker-compose.yml -f docker-compose.production.yml logs --tail=200 zenvis-backend
curl -fsS http://127.0.0.1:11001/actuator/health/readiness
```

手工回滚时，先解压目标备份，再启动服务：

```bash
cd /root/lubinsun/zenvis
tar -xzf backups/release-YYYYMMDD-HHMMSS.tar.gz
docker compose -f docker-compose.yml -f docker-compose.production.yml up -d
```
