FROM alpine:3.20

RUN apk add --no-cache privoxy ca-certificates \
  && mkdir -p /etc/privoxy /var/log/privoxy

COPY --chmod=0755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 8118

ENV PRIVOXY_LISTEN_ADDRESS=0.0.0.0:8118 \
    PRIVOXY_LOG_LEVEL=0 \
    PRIVOXY_LOG_FILE=/var/log/privoxy/logfile \
    SOCKS_HOST=host.docker.internal \
    SOCKS_PORT=18080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
