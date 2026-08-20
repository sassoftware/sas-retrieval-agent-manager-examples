FROM node:22-alpine AS builder

WORKDIR /app
COPY . .

RUN npm install && npm run build


FROM node:22-alpine AS runner
WORKDIR /app
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY server.js ./server.js

ENV NODE_TLS_REJECT_UNAUTHORIZED=0

EXPOSE 3000
CMD ["node", "server.js"]