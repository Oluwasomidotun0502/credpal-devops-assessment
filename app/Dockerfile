FROM node:18-alpine AS builder
WORKDIR /app

COPY app/package*.json ./
RUN npm install --production

COPY app .

FROM node:18-alpine

# Install curl for healthcheck
RUN apk add --no-cache curl

WORKDIR /app
COPY --from=builder /app .

RUN addgroup -S nodegroup && adduser -S nodeuser -G nodegroup
USER nodeuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "server.js"]
