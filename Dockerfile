FROM node:20-alpine AS backend-builder

WORKDIR /app/backend

COPY backend/package*.json ./
RUN npm ci

COPY backend ./
RUN npm run build

FROM node:20-alpine AS backend

ENV NODE_ENV=production
ENV PORT=3300

WORKDIR /app/backend

RUN apk add --no-cache dumb-init

COPY backend/package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=backend-builder /app/backend/dist ./dist
COPY --from=backend-builder /app/backend/node_modules/.prisma ./node_modules/.prisma
COPY --from=backend-builder /app/backend/prisma ./prisma

RUN addgroup -g 1001 -S nodejs \
  && adduser -S nestjs -u 1001 -G nodejs
USER nestjs

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:' + (process.env.PORT || 3300) + '/', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

EXPOSE 3300

ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/src/main.js"]

FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

ARG VITE_API_URL=/api
ENV VITE_API_URL=${VITE_API_URL}

COPY frontend/package*.json ./
RUN npm ci

COPY frontend ./
RUN npm run build

FROM nginx:alpine AS frontend

COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]

FROM python:3.11-slim AS tryon-service

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8000

WORKDIR /app/tryon-service

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

COPY tryon-service/requirements.txt ./
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

COPY tryon-service/app ./app

RUN useradd -m -u 1001 tryonuser
USER tryonuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD python -c "import http.client, os, sys; c=http.client.HTTPConnection('127.0.0.1', int(os.getenv('PORT', '8000')), timeout=5); c.request('GET', '/docs'); sys.exit(0 if c.getresponse().status == 200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
