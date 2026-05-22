FROM evoapicloud/evolution-api:latest

EXPOSE 8080

ENV PORT=8080
ENV ENV=production

CMD ["node", "src/index.js", "--port", "8080"]
