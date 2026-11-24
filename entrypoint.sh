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

    content_server='limit_req_zone $binary_remote_addr zone=gh_proxy_req:10m rate='"${USE_RATE}"'r/s;\n'
    content_server=$content_server'limit_conn_zone $binary_remote_addr zone=gh_proxy_conn:10m;\n'
    content_server=$content_server'server {\n'
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
    printf "$content_server" > /etc/nginx/conf.d/nginx.conf
fi

exec "$@"
