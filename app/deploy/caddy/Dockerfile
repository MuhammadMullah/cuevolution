# Stock caddy:2-alpine has no DNS provider modules built in. The
# caddy-dns/cloudflare plugin lets the Caddyfile prove domain ownership via a
# DNS-01 challenge (a TXT record created through the Cloudflare API) instead
# of HTTP-01 — so a cert for the domain can be issued before DNS ever points
# at this server, which is what makes a zero-downtime cutover possible (see
# deploy/README.md's "Zero-downtime DNS cutover" section).
FROM caddy:2-builder-alpine AS builder

RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:2-alpine

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
