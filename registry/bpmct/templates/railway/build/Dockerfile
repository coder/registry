FROM codercom/enterprise-base:ubuntu

USER root

COPY entrypoint.sh /coder-entrypoint.sh
RUN chmod +x /coder-entrypoint.sh

ENTRYPOINT ["/coder-entrypoint.sh"]
