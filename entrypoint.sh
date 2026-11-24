#! /usr/bin/env bash
set -e

/uwsgi-nginx-entrypoint.sh

# Get the listen port for Nginx, default to 80
USE_LISTEN_PORT=${LISTEN_PORT:-80}

if [ -f /app/nginx.conf ]; then
    cp /app/nginx.conf /etc/nginx/nginx.conf
else
    # 默认限制按客户端 IP 生效，适合个人自用部署。
    USE_RATE=${GH_PROXY_RATE:-10}
    USE_RATE_BURST=${GH_PROXY_RATE_BURST:-20}
    USE_MAX_CONNECTIONS=${GH_PROXY_MAX_CONNECTIONS:-20}
    USE_MAX_BODY_SIZE=${GH_PROXY_MAX_BODY_SIZE:-50g}
    USE_CONNECT_TIMEOUT=${GH_PROXY_CONNECT_TIMEOUT:-10}
    USE_READ_TIMEOUT=${GH_PROXY_READ_TIMEOUT:-60}
    USE_SEND_TIMEOUT=${GH_PROXY_SEND_TIMEOUT:-60}
    USE_TRUSTED_PROXIES=${GH_PROXY_TRUSTED_PROXIES:-}

    trusted_proxy_config=''
    if [ -n "${USE_TRUSTED_PROXIES}" ]; then
        trusted_proxy_config=$(python3 - "${USE_TRUSTED_PROXIES}" <<'PY'
import ipaddress
import sys

trusted_proxies = [item.strip() for item in sys.argv[1].split(',')]
if not trusted_proxies or any(not item for item in trusted_proxies):
    raise SystemExit('GH_PROXY_TRUSTED_PROXIES 不能包含空项')

networks = []
for item in trusted_proxies:
    if any(char in item for char in ('%', '\\r', '\\n', ';', '{', '}', '$')):
        raise SystemExit(f'GH_PROXY_TRUSTED_PROXIES 包含非法字符: {item}')
    try:
        network = ipaddress.ip_network(item, strict=False)
    except ValueError as error:
        raise SystemExit(f'GH_PROXY_TRUSTED_PROXIES 包含无效 IP/CIDR: {item}') from error
    if network.prefixlen == 0:
        raise SystemExit('GH_PROXY_TRUSTED_PROXIES 不允许全网段')
    networks.append(network.with_prefixlen)

for network in networks:
    print(f'    set_real_ip_from {network};')
PY
)
        trusted_proxy_config="${trusted_proxy_config}\n    real_ip_header X-Real-IP;\n    real_ip_recursive off;"
    fi

    if [ -n "${trusted_proxy_config}" ]; then
        rate_limit_key='$binary_remote_addr'
    else
        rate_limit_key='$gh_proxy_client_ip'
        content_server='map $http_x_real_ip $gh_proxy_client_ip {\n'
        content_server=$content_server'    "" $binary_remote_addr;\n'
        content_server=$content_server'    default $http_x_real_ip;\n'
        content_server=$content_server'}\n'
    fi

    content_server=$content_server'limit_req_zone '"${rate_limit_key}"' zone=gh_proxy_req:10m rate='"${USE_RATE}"'r/s;\n'
    content_server=$content_server'limit_conn_zone '"${rate_limit_key}"' zone=gh_proxy_conn:10m;\n'
    content_server=$content_server'server {\n'
    if [ -n "${trusted_proxy_config}" ]; then
        content_server=$content_server"${trusted_proxy_config}\n"
    fi
    content_server=$content_server"    listen ${USE_LISTEN_PORT};\n"
    content_server=$content_server"    client_max_body_size ${USE_MAX_BODY_SIZE};\n"
    content_server=$content_server"    limit_req zone=gh_proxy_req burst=${USE_RATE_BURST} nodelay;\n"
    content_server=$content_server"    limit_conn gh_proxy_conn ${USE_MAX_CONNECTIONS};\n"
    content_server=$content_server"    uwsgi_connect_timeout ${USE_CONNECT_TIMEOUT}s;\n"
    content_server=$content_server"    uwsgi_read_timeout ${USE_READ_TIMEOUT}s;\n"
    content_server=$content_server"    uwsgi_send_timeout ${USE_SEND_TIMEOUT}s;\n"
    content_server=$content_server'    location / {\n'
    content_server=$content_server'        try_files $uri @app;\n'
    content_server=$content_server'    }\n'
    content_server=$content_server'    location @app {\n'
    content_server=$content_server'        include uwsgi_params;\n'
    content_server=$content_server'        uwsgi_pass unix:///tmp/uwsgi.sock;\n'
    content_server=$content_server'        uwsgi_buffer_size 256k;\n'
    content_server=$content_server'        uwsgi_buffers 32 512k;\n'
    content_server=$content_server'        uwsgi_busy_buffers_size 512k;\n'
    content_server=$content_server'    }\n'
    content_server=$content_server'}\n'
    # Save generated server /etc/nginx/conf.d/nginx.conf
    printf '%b' "$content_server" > /etc/nginx/conf.d/nginx.conf
fi

exec "$@"
