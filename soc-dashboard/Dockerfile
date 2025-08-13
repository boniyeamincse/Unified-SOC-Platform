FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S dashboard -u 1001 -G nodejs && \
    chown -R dashboard:nodejs /app

USER dashboard

EXPOSE 3000

CMD ["node", "server.js"]
