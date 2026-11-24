# gh-proxy

GitHub Release、Archive、项目文件和 Git Clone 加速代理，提供 Cloudflare Workers 和 Python/Docker 两种部署方式。

## 使用方式

将代理域名加在原始 GitHub URL 前面：

```text
https://你的代理域名/https://github.com/用户/仓库/路径
```

示例：

```text
https://proxy.example.com/https://github.com
https://proxy.example.com/https://github.com/user/repo
https://proxy.example.com/https://github.com/user/repo/archive/main.zip
https://proxy.example.com/https://github.com/user/repo/releases/download/v1.0.0/app.zip
https://proxy.example.com/https://raw.githubusercontent.com/user/repo/main/file.txt
https://proxy.example.com/https://codeload.github.com/user/repo/zip/refs/heads/main
```

Git Clone：

```bash
git clone https://proxy.example.com/https://github.com/user/repo.git
```

支持的目标类型包括：

- GitHub Release 和 Archive
- GitHub 首页、仓库首页和其他 Web 页面
- GitHub `blob`/`raw` 文件
- `raw.githubusercontent.com` 文件
- `codeload.github.com` 下载文件
- Gist
- Git Clone 所需的 `info/refs` 和 `git-upload-pack` 请求

项目不是通用网站代理，只处理代码中允许的 GitHub/Gist URL 类型。

## Cloudflare Workers 部署

1. 在 [Cloudflare Workers](https://workers.cloudflare.com/) 创建 Worker。
2. 将 [`index.js`](./index.js) 的内容复制到 Worker 编辑器并部署。
3. 根路径部署保持：

   ```javascript
   const PREFIX = '/'
   ```

   如果路由为 `example.com/gh/*`，改为：

   ```javascript
   const PREFIX = '/gh/'
   ```

部署在 `/gh/` 后的使用方式：

```text
https://example.com/gh/https://github.com/user/repo/archive/main.zip
```

`ASSET_URL` 用于指定首页静态资源地址。

> 当前 `codeload.github.com` 下载规则已接入 Python/Docker 服务；Cloudflare Worker 版本暂未同步该规则。需要代理 codeload 下载时，请使用 Python/Docker 入口。

## Docker Compose 部署

在项目根目录创建 `docker-compose.yml`：

```yaml
name: gh-proxy

services:
  gh-proxy:
    container_name: gh-proxy
    image: myp015/gh-proxy:latest
    ports:
      - "8090:80"
    restart: always
    environment:
      LISTEN_PORT: "80"
      GH_PROXY_SIZE_LIMIT: "53687091200"
      GH_PROXY_RATE: "10"
      GH_PROXY_RATE_BURST: "20"
      GH_PROXY_MAX_CONNECTIONS: "20"
      # 可选：反向代理网段，多个 IP/CIDR 用逗号分隔；直连部署可不设置
      # GH_PROXY_TRUSTED_PROXIES: "172.21.0.1/32"
      GH_PROXY_MAX_BODY_SIZE: "50g"
      GH_PROXY_CONNECT_TIMEOUT: "10"
      GH_PROXY_READ_TIMEOUT: "60"
      GH_PROXY_SEND_TIMEOUT: "60"
```

启动服务：

```bash
docker compose up -d
```

配置说明：

- `GH_PROXY_SIZE_LIMIT`：Python 转发层响应大小上限，示例为 50GB。
- `GH_PROXY_MAX_BODY_SIZE`：Nginx 请求体大小上限，示例为 50GB。
- `GH_PROXY_RATE`、`GH_PROXY_RATE_BURST`：单个客户端 IP 的请求速率和突发请求数。
- `GH_PROXY_MAX_CONNECTIONS`：单个客户端 IP 的最大并发连接数。
- `GH_PROXY_TRUSTED_PROXIES`：可选的可信前置代理 IP/CIDR 列表，多个值用逗号分隔，例如 `127.0.0.1,172.21.0.1/32,10.0.0.0/8`。配置后，Nginx 通过 realip 模块从前置代理传递的 `X-Real-IP` 恢复客户端 IP；未配置时也会直接使用 `X-Real-IP` 作为限流键，缺少该请求头时回退到实际连接 IP。
- 反向代理部署时，前置 Nginx/OpenResty 必须覆盖传递 `X-Real-IP`；配置可信代理列表更安全，未配置时不要将公网请求头视为可信身份。不要配置全网段。
- `GH_PROXY_CONNECT_TIMEOUT`、`GH_PROXY_READ_TIMEOUT`、`GH_PROXY_SEND_TIMEOUT`：上游连接、读取和发送超时，单位为秒。

Compose 直接使用 GitHub Actions 推送的 `myp015/gh-proxy:latest` 镜像，服务监听容器内的 80 端口。镜像基于 `guysoft/uwsgi-nginx:python3.8`。

## Docker Hub 自动构建

`.github/workflows/docker.yml` 会在推送到 `master` 时自动构建并推送镜像，也可以在 GitHub Actions 页面手动运行。

需要在仓库 Secrets 中配置：

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_PASSWORD`

工作流会推送 `latest`、`sha-<commit>` 以及手动填写的版本标签。

## 直接运行 Docker

```bash
docker run -d --name gh-proxy \
  -p 8090:80 \
  --restart=always \
  myp015/gh-proxy:latest
```

大规模使用时建议自行部署，并根据带宽和服务器资源调整上述限制参数。
