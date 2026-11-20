FROM alpine:3.23@sha256:85fe1e81d6758c208f3e1eed4338a1997e19d4be002d4dd32d3100c9a8c010a0

# Squid 7. The template mounts squid.conf from a ConfigMap at
# /etc/squid-conf.
RUN apk add --no-cache squid=7.6-r0

# Runs as the squid user. The config logs to stdout and stderr and keeps no
# pid file and no disk cache, so it needs no writable paths.
USER squid
ENTRYPOINT ["squid", "-N", "-f", "/etc/squid-conf/squid.conf"]
