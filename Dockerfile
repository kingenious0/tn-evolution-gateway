FROM evoapicloud/evolution-api:latest

EXPOSE 8080

RUN apt-get update && apt-get install -y python3 netcat-openbsd && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
