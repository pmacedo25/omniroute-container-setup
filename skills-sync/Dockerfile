FROM alpine:3.22

# Corporate Netskope SSL inspection chain injection.
# Generated at setup time by Invoke-CorporateCAInjection; no-op when empty.
# Step 1: seed /usr/local/share/ca-certificates/ so update-ca-certificates picks it up after apk.
# Step 2: also append directly to the Alpine base bundle so apk HTTPS connections work
#         before the ca-certificates package is installed (apk itself uses this bundle).
COPY netskope-ca.pem /usr/local/share/ca-certificates/corporate-ca.crt
RUN if [ -s /usr/local/share/ca-certificates/corporate-ca.crt ]; then \
        cat /usr/local/share/ca-certificates/corporate-ca.crt >> /etc/ssl/certs/ca-certificates.crt; \
    fi

RUN apk add --no-cache ca-certificates git jq openssh-client \
    && addgroup -S skills \
    && adduser -S -G skills -h /home/skills skills \
    && mkdir -p /skills /state \
    && chown -R skills:skills /skills /state

COPY --chmod=755 sync-lib.sh /usr/local/lib/skills-sync.sh
COPY --chmod=755 entrypoint.sh /usr/local/bin/sync-skills

USER skills
ENTRYPOINT ["/usr/local/bin/sync-skills"]
