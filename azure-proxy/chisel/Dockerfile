FROM jpillora/chisel:1.11 AS chisel

FROM alpine:3.20

RUN apk add --no-cache ca-certificates busybox-extras

COPY --from=chisel /app/bin /usr/local/bin/chisel
COPY --chmod=0755 start-chisel.sh /usr/local/bin/start-chisel.sh
COPY healthz.json /var/www/healthz

EXPOSE 80

# Health check using the /healthz endpoint (served via chisel --backend)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:80/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/start-chisel.sh"]