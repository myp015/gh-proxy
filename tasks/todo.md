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
- 待完成：提交并推送到 `origin/master`。
