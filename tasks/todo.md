# 工作项

- [x] 新增 GitHub Actions Docker 构建与推送工作流
- [x] 升级 Docker 基础镜像
- [x] 为 Python 上游请求增加超时与可配置大小限制
- [x] 为 Nginx 增加限流、并发、请求大小和超时限制
- [x] 更新部署文档
- [x] 完成本地检查、构建验证并检查差异
- [x] 提交并推送到 origin/master

## Review

- `python3 -I -m py_compile app/main.py`：通过。
- `bash -n entrypoint.sh`：通过。
- `yq -e '.' .github/workflows/docker.yml`：通过。
- `docker build --tag gh-proxy:local .`：通过，基础镜像 `guysoft/uwsgi-nginx:python3.8` 可用。
- 容器启动及 `nginx -t`：通过，默认 `client_max_body_size 50g`。
- 限制参数环境变量覆盖及 `nginx -t`：通过。
- 容器 Raw 文件代理请求：通过，HTTP 200，返回 5255 字节。
- 历史记录：初始版本曾待提交并推送到 `origin/master`；本次工作树改动尚未提交。

## MoviePilot GitHub 检测与限流调整

- [x] 将本地 Compose 限流调整为 `1000/3000/1000`。
- [x] 重新创建 `gh-proxy` 容器。
- [x] 验证 MoviePilot GitHub 页面检查链路和 Nginx 配置。

### Review

- 已确认 MoviePilot v3 的 `github_proxy_web` 检查目标为 GitHub README Blob，要求最终 HTTP 200 且正文包含 `MoviePilot`。
- 修复前历史记录：当时仅验证了最终响应，未覆盖 MoviePilot 的严格首跳校验；该结论已被后续无跳转修复取代。
- Compose 参数已生效：`GH_PROXY_RATE=1000`、`GH_PROXY_RATE_BURST=3000`、`GH_PROXY_MAX_CONNECTIONS=1000`。
- `gh-proxy` 状态为 `running`，端口映射保持 `8090:80`；容器内 `nginx -t` 通过。
- 首页返回 `200`；`/jxxghp/MoviePilot` 返回 `200`、HTML 正文包含 `MoviePilot`。
- 修复前历史观察：MoviePilot 检测路径会先返回代理化 Raw 地址 `302`，最终 `200`；该行为已由后续入口规范化修复。
- MoviePilot 插件索引请求返回 `200`，下载 43066 字节。
- 重建后最近 2 分钟未发现 `503`、`429`、`499`、`500` 或 Nginx 限流日志。
- 该历史阶段未修改仓库源码；外部 Compose 文件不属于当前 Git 仓库。

## 公网 OpenResty 响应头修复

- [x] 定位公网 502 根因：OpenResty `upstream sent too big header`。
- [x] 增加上游响应头缓冲区并平滑重载 OpenResty。
- [x] 验证公网 MoviePilot 首页、仓库页、README 和插件索引。

### Review

- 修改 `/www/1panel/www/sites/gh.iynas.cn/proxy/root.conf`：增加 `proxy_buffer_size 128k`、`proxy_buffers 8 128k`、`proxy_busy_buffers_size 256k` 和 `proxy_read_timeout 120s`。
- 已备份原配置：`root.conf.bak-20261124`。
- OpenResty `nginx -t` 通过并已平滑重载。
- 公网首页返回 HTTP 200；MoviePilot 仓库页返回 HTTP 200，正文包含 `MoviePilot`。
- 公网 README Blob 首跳为代理路径 HTTP 302，最终返回 HTTP 200，正文包含 `MoviePilot`。
- 公网 MoviePilot 插件索引返回 HTTP 200，下载 43066 字节。
- 重载后容器请求均返回 200；错误日志中新增请求未再出现 `upstream sent too big header`。

## MoviePilot 未授权跳转修复

- [x] 将 GitHub `blob/raw` 入口直接规范化为 `raw.githubusercontent.com`。
- [x] 构建并重建本地 `gh-proxy` 容器。
- [x] 验证首响应、MoviePilot 检测链路和原有下载功能。

### Review

- 已确认 MoviePilot 的网页检测只允许代理前缀下的 `github.com` 跳转，不允许代理前缀下的 `raw.githubusercontent.com` 跳转。
- 已确认现有 gh-proxy 会暴露 GitHub Blob 到 Raw 的 302，导致严格跳转校验失败。
- `normalize_github_file_url()` 仅转换严格匹配的 GitHub `blob/raw` 文件路径，保留查询参数和片段，并拒绝用户信息、端口及非 GitHub 主机。
- 本地和公网 README Blob 请求首响应均为 HTTP 200、无 `Location`、正文包含 `MoviePilot`，正文大小均为 4787 字节。
- URL 规范化边界测试通过；容器状态为 `running`，容器内 `nginx -t` 通过。
- 公网 Archive 请求返回 HTTP 200，下载 3256232 字节；限流配置保持 `1000r/s`、突发 `3000`、并发 `1000`。
- 该历史阶段未修改 Cloudflare Worker、外部 Compose 和 OpenResty 配置；后续真实 IP 限流部署已更新外部 Compose，外部部署配置不属于当前 Git 仓库。

## codeload 代理支持

- [x] 增加仅限 `codeload.github.com` 主机的宽松匹配规则。
- [x] 增加 Blob/Raw、codeload 和非法主机的自动化回归测试。
- [x] 更新 README，重新构建并验证本地及公网代理。

### Review

- 已确认直连 `codeload.github.com` 返回 HTTP 200，而原代理因 `check_url()` 不匹配返回 HTTP 403。
- codeload 路径采用宽松匹配，仅固定主机并要求 owner/repo 后存在下载路径，不限制下载格式和路径层级；不扩展为通用网站代理。
- MoviePilot 实际 codeload 地址 `/owner/repo/zip/refs/heads/{branch}` 已验证本地和公网均返回 HTTP 200、3256232 字节，且无 `Location`。
- 新增 `tests/test_main.py`，在镜像环境执行 7 项测试全部通过；Python 语法检查和 `git diff --check` 通过。
- README 已补充 codeload 使用示例和支持类型；Cloudflare Worker 本次未修改，仍不支持 codeload。

## 按真实客户端 IP 限流

- [x] 增加多可信 IP/CIDR 的 realip 配置并验证限流分桶。
- [x] 使用当前 OpenResty/Docker 链路重建容器并验证真实 IP 头配置。

### Review

- 用户已明确选择按 IP 限流，不按目标域名限流。
- 当前 Nginx 使用 `$binary_remote_addr`；无可信代理列表时，若请求带 `X-Real-IP` 则使用该值限流，否则回退到实际连接 IP；配置可信代理列表时则由 realip 模块恢复地址后再限流。
- 已增加 `GH_PROXY_TRUSTED_PROXIES` 逗号分隔配置，逐项校验 IPv4/IPv6/CIDR，拒绝空项、非法字符和全网段，并生成多条 `set_real_ip_from`。
- 配置非空时使用 `real_ip_header X-Real-IP` 和 `real_ip_recursive off`，安全地限制哪些前置代理可以提供真实 IP；未配置时通过 `map $http_x_real_ip` 直接使用前置代理提供的 IP，缺少该头时回退实际连接 IP。
- 当前 OpenResty 使用 host network，容器 Docker 网关为 `172.21.0.1`；外部 Compose 已配置 `GH_PROXY_TRUSTED_PROXIES=172.21.0.1/32` 并已强制重建容器。
- 容器内 `nginx -t` 通过，实际限流保持 `1000r/s`、突发 `3000`、并发 `1000`；多 IP/CIDR 生成测试和非法输入快速失败测试通过。
- `.github/workflows/docker.yml` 已加入镜像内单元测试及可信代理配置校验步骤；当前仓库未执行远程 Actions。
