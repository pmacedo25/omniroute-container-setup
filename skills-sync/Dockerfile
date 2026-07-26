FROM alpine:3.22

RUN apk add --no-cache ca-certificates git openssh-client \
    && addgroup -S skills \
    && adduser -S -G skills -h /home/skills skills

COPY --chmod=755 entrypoint.sh /usr/local/bin/sync-skills

USER skills
ENTRYPOINT ["/usr/local/bin/sync-skills"]
