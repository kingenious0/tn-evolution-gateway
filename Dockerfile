FROM evoapicloud/evolution-api:latest

EXPOSE 8080

RUN apk add --no-cache python3
RUN npm install pg

COPY entrypoint.sh /entrypoint.sh
COPY migrate-via-pooler.mjs /evolution/migrate-via-pooler.mjs
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
