# syntax=docker/dockerfile:1

FROM node:20-alpine

WORKDIR /app

# Install only production deps
COPY package*.json ./
RUN npm ci --omit=dev

# Copy app source
COPY . .

ENV NODE_ENV=production
EXPOSE 3000

# Healthcheck for EasyPanel / orchestrators.
# Alpine includes busybox wget, so we can avoid adding curl.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
	CMD wget -q -O - http://127.0.0.1:${PORT:-3000}/api/health > /dev/null 2>&1 || exit 1

CMD ["npm", "start"]
