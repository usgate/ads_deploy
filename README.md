# UG Ads 部署仓库

这是 `ug-ads` 私有项目的公开 GitHub Actions 部署仓库。

本仓库只保存部署脚本和 workflow，不保存私有业务代码，也不保存密钥。workflow 通过手动触发，在运行时拉取私有 `ug-ads` 仓库，完成构建和部署。

## 部署拓扑

### API 服务器

- App 域名：`api.edgepulse.top`
- systemd 服务：`ug-ads-api.service`
- Jar 路径：`/app/ug-ads-api.jar`
- Spring Profile：`api`
- Caddy 行为：`api.edgepulse.top` 的所有请求都会改写到 `/ug-ads/api/open/dispatch`，再转发到本机 `127.0.0.1:8080`。

### Analytics + 后台服务器

- App Analytics 域名：`analytics.edgepulse.top`
- 后台域名：`ads.299188.xyz`
- systemd 服务：`ug-ads-analytics.service`
- Jar 路径：`/app/ug-ads-analytics.jar`
- Spring Profile：`analytics`
- 前端静态目录：`/app/ug-ads-vue`
- Caddy 行为：
  - `analytics.edgepulse.top` 的所有请求都会改写到 `/ug-ads/api/open/dispatch`，再转发到本机 `127.0.0.1:8080`。
  - `ads.299188.xyz` 用于 HTTPS 直连访问后台前端页面，不经过 Cloudflare 代理。
  - `ads.299188.xyz/ug-ads/*` 直接转发到 analytics 后端，用于后台管理 API。

App API 域名显式使用 `http://`，对外 HTTPS 由 Cloudflare 提供，源站不维护这些 App 域名的 ACME 证书。后台域名 `ads.299188.xyz` 由 Caddy 直连提供 HTTPS，并由 Caddy 自动申请和续期证书。

部署脚本只在 `/etc/caddy/Caddyfile` 不存在时初始化一份最小配置。如果该文件已经存在，自动部署不会修改、格式化或覆盖 Caddyfile，后续站点、域名和路由由人工维护。

## Cloudflare 配置

- `api.edgepulse.top` 和 `analytics.edgepulse.top` 建议开启 Cloudflare 代理。
- Cloudflare 对外提供 HTTPS，但回源使用 HTTP。
- `ads.299188.xyz` 用于后台管理，使用 DNS only，直接解析到 analytics/admin 服务器，由源站 Caddy 提供 HTTPS 证书。

## 前端配置要求

前端 workflow 不会覆盖 `VITE_API_BASE_URL`，会直接使用私有仓库里的配置文件。

请确认私有 `ug-ads` 仓库中 `ug-ads-vue/.env.production` 配置为：

```env
VITE_API_BASE_URL=https://ads.299188.xyz/ug-ads
```

## Workflow 说明

### Deploy Backend

手动触发，用于部署后端。

触发参数：

- `target`：选择 `api` 或 `analytics`
- `ref`：私有 `ug-ads` 仓库的分支、tag 或 commit，默认 `master`

执行内容：

- 拉取私有 `ug-ads` 仓库
- 使用对应 Maven profile 构建 `ug-ads-boot`
- 上传 jar 到目标服务器
- 初始化或更新对应 systemd 服务
- 如果目标服务器没有 `/etc/caddy/Caddyfile`，初始化一份最小 Caddyfile
- 如果目标服务器已经存在 `/etc/caddy/Caddyfile`，跳过 Caddyfile 修改，由人工维护内容
- 重启对应后端服务，并在不影响部署结果的前提下尝试 reload Caddy

### Deploy Frontend

手动触发，用于部署后台前端。

触发参数：

- `ref`：私有 `ug-ads` 仓库的分支、tag 或 commit，默认 `master`

执行内容：

- 拉取私有 `ug-ads` 仓库
- 在 `ug-ads-vue` 中执行 `npm ci` 和 `npm run build`
- 将 `dist` 上传到 analytics/admin 服务器的 `/app/ug-ads-vue`
- 如果 analytics/admin 服务器没有 `/etc/caddy/Caddyfile`，初始化一份最小 Caddyfile
- 如果 analytics/admin 服务器已经存在 `/etc/caddy/Caddyfile`，跳过 Caddyfile 修改，由人工维护内容
- 在不影响部署结果的前提下尝试 reload Caddy

## 必需 Secrets

### 私有仓库访问

- `APP_GIT_URL`：私有 `ug-ads` 仓库 SSH 地址，例如 `git@github.com:owner/ug-ads.git`
- `APP_REPO_SSH_KEY`：用于拉取私有仓库的只读私钥

兼容旧的 `action-script` 示例：如果 `APP_REPO_SSH_KEY` 为空，workflow 会尝试使用 `SSH_PRIVATE_KEY` 作为拉取私有仓库的备用密钥。新配置建议优先使用 `APP_REPO_SSH_KEY`。

### API 服务器

- `API_HOST`：API 服务器 IP 或域名
- `API_SSH_PRIVATE_KEY`：登录 `root@API_HOST` 的私钥
- `API_SSH_PORT`：可选，默认 `22`

### Analytics + 后台服务器

- `ANALYTICS_HOST`：Analytics + 后台服务器 IP 或域名
- `ANALYTICS_SSH_PRIVATE_KEY`：登录 `root@ANALYTICS_HOST` 的私钥
- `ANALYTICS_SSH_PORT`：可选，默认 `22`

## 服务器前置条件

- SSH 登录用户为 `root`
- 已安装 JDK 25
- 后端服务监听本机 `8080`
- 部署目录为 `/app`
- workflow 会在 Debian / Ubuntu 服务器上自动安装 Caddy
- 如果服务器不是 Debian / Ubuntu，需要提前手动安装 Caddy
- 已存在的 `/etc/caddy/Caddyfile` 由人工维护，自动部署不会覆盖

建议防火墙：

- 对外开放 `80`
- 如果 `ads.299188.xyz` 由源站 Caddy 提供 HTTPS，需要对外开放 `443`
- 尽量不要对外开放 `8080`，让 `8080` 只被本机 Caddy 访问
- App 侧 HTTPS 由 Cloudflare 提供，不由源站 Caddy 提供；后台域名 `ads.299188.xyz` 的 HTTPS 由源站 Caddy 提供

## 手动部署步骤

1. 在 GitHub 打开本部署仓库
2. 进入 Actions
3. 运行 `Deploy Backend`，选择 `api` 或 `analytics`
4. 运行 `Deploy Frontend`，部署后台前端

通常建议先部署 `analytics` 后端，再部署前端。
