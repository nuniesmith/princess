# princess edge nginx — config baked into the image (freddy's pattern).
FROM nginx:alpine

RUN apk add --no-cache curl openssl

# Bake in configuration + dashboard
COPY services/nginx/nginx.conf /etc/nginx/nginx.conf
COPY services/nginx/conf.d/ /etc/nginx/conf.d/
COPY services/nginx/dashboard/index.html /dashboard/index.html
RUN rm -f /etc/nginx/conf.d/default.conf

# Baked-in self-signed fallback cert so nginx can always start, even before
# the real Let's Encrypt certs arrive in the ssl-certs volume.
RUN mkdir -p /etc/nginx/ssl/fallback /var/www/certbot && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/fallback/privkey.pem \
        -out /etc/nginx/ssl/fallback/fullchain.pem \
        -subj "/C=CA/ST=Ontario/L=Toronto/O=Princess/CN=7gram.xyz" \
        -addext "subjectAltName=DNS:7gram.xyz,DNS:*.7gram.xyz,DNS:*.sullivan.7gram.xyz"

# Startup hook: substitutes backend tailnet IPs from env, installs certs from
# the ssl-certs volume (or the fallback), validates config.
COPY docker/nginx/entrypoint.sh /docker-entrypoint.d/99-init.sh
RUN chmod +x /docker-entrypoint.d/99-init.sh

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost/health || exit 1

EXPOSE 80 443
