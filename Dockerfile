FROM evoapicloud/evolution-api:latest

EXPOSE 8080

RUN apk add --no-cache python3

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
