FROM alpine:3.22

# Corporate SSL inspection CA injection (Netskope, Zscaler, Fortinet, etc.)
# Generated at setup time by Invoke-CorporateCAInjection; no-op when empty.
COPY netskope-ca.pem /tmp/corporate-ca.pem
RUN if [ -s /tmp/corporate-ca.pem ]; then \
        cat /tmp/corporate-ca.pem >> /etc/ssl/certs/ca-certificates.crt; \
    fi && rm /tmp/corporate-ca.pem

RUN apk add --no-cache ca-certificates git openssh-client \
    && addgroup -S skills \
    && adduser -S -G skills -h /home/skills skills

COPY --chmod=755 entrypoint.sh /usr/local/bin/sync-skills

USER skills
ENTRYPOINT ["/usr/local/bin/sync-skills"]
