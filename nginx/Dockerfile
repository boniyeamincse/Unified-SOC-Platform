FROM nginx:1.24-alpine

# Install security updates
RUN apk update && apk upgrade

# Create nginx user
RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create directories for SSL certificates
RUN mkdir -p /etc/ssl/certs && chmod 700 /etc/ssl/certs

# Set up log files with proper permissions
RUN touch /var/log/nginx/access.log /var/log/nginx/error.log && \
    chown nginx:nginx /var/log/nginx/access.log /var/log/nginx/error.log

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:80/health || exit 1

# Run nginx as non-root user
USER nginx

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]
