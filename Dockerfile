# syntax=docker/dockerfile:1.6
# Assembles the AGPL-covered YourOwn.Chat image from two immutable sources:
#   sources/server — exported patched Mattermost server tree
#   sources/web    — exported standalone YourOwn.Chat web tree
# This product build must never use the `enterprise` or `sourceavailable` tags.
# Context: the root of yourown-chat-mattermost.
# Usage:
#   ./scripts/build-image.sh

# ─────────────────────────────────────────────────────────────────────────────
# Stage 1 — webapp (JS/CSS assets)
# ─────────────────────────────────────────────────────────────────────────────
FROM node:24-bookworm-slim AS webapp-builder

ARG WEB_BUILD_HASH=dev
ARG WEB_SOURCE_URL

WORKDIR /src/webapp

# Copy all sources first — postinstall needs workspace dirs (platform/*) to exist.
COPY sources/web/ .
RUN test -n "$WEB_SOURCE_URL" || \
        (echo "FATAL: WEB_SOURCE_URL must identify the immutable web source" && exit 1); \
    printf '%s\n' "$WEB_BUILD_HASH" | grep -Eq '^[0-9a-f]{40}$' || \
        (echo "FATAL: WEB_BUILD_HASH must be a full lowercase Git commit SHA" && exit 1); \
    test "$WEB_SOURCE_URL" = "https://github.com/pilprod/yourown-chat-web/tree/$WEB_BUILD_HASH" || \
        (echo "FATAL: WEB_SOURCE_URL must identify the exact WEB_BUILD_HASH" && exit 1)
RUN --mount=type=cache,target=/root/.npm \
    npm ci --include=dev
# Outputs to channels/dist/
RUN npm run build


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2 — server binary (Go)
# ─────────────────────────────────────────────────────────────────────────────
# Pinned to 1.26.6: ships the fixes required by the release vulnerability
# gate, including CVE-2026-39821 and the 2026-5685x/5686x stdlib advisories.
FROM golang:1.26.6-alpine AS server-builder

WORKDIR /src/server
COPY sources/server/ .

# Build metadata injected from CI.
# BUILD_NUMBER  = assembly tag name (e.g. 11.10.0-rc.1)
# BUILD_HASH    = full 40-char git commit SHA
# BUILD_DATE    = UTC ISO-8601 build timestamp
ARG BUILD_NUMBER=0
ARG BUILD_HASH=dev
ARG BUILD_DATE=
ARG SOURCE_URL
ARG WEB_BUILD_HASH=dev
ARG WEB_SOURCE_URL
ARG ASSEMBLY_BUILD_HASH=dev
ARG ASSEMBLY_SOURCE_URL

# go.work wires the main module (.) to the embedded public sub-module (./public).
# This mirrors what `make setup-go-work` does for Team Edition (no enterprise).
RUN go work init && go work use . && go work use ./public

RUN --mount=type=cache,target=/root/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    test -n "$SOURCE_URL" || \
        (echo "FATAL: SOURCE_URL must identify the immutable Corresponding Source" && exit 1); \
    printf '%s\n' "$BUILD_HASH" | grep -Eq '^[0-9a-f]{40}$' || \
        (echo "FATAL: BUILD_HASH must be a full lowercase Git commit SHA" && exit 1); \
    test "$SOURCE_URL" = "https://github.com/pilprod/mattermost/tree/$BUILD_HASH" || \
        (echo "FATAL: SOURCE_URL must identify the exact BUILD_HASH" && exit 1); \
    printf '%s\n' "$ASSEMBLY_BUILD_HASH" | grep -Eq '^[0-9a-f]{40}$' || \
        (echo "FATAL: ASSEMBLY_BUILD_HASH must be a full lowercase Git commit SHA" && exit 1); \
    test "$ASSEMBLY_SOURCE_URL" = "https://github.com/pilprod/yourown-chat-mattermost/tree/$ASSEMBLY_BUILD_HASH" || \
        (echo "FATAL: ASSEMBLY_SOURCE_URL must identify the exact ASSEMBLY_BUILD_HASH" && exit 1); \
    MODEL=github.com/mattermost/mattermost/server/public/model; \
    LDFLAGS="-s -w"; \
    LDFLAGS="$LDFLAGS -X $MODEL.BuildNumber=$BUILD_NUMBER"; \
    LDFLAGS="$LDFLAGS -X $MODEL.BuildHash=$BUILD_HASH"; \
    LDFLAGS="$LDFLAGS -X $MODEL.BuildHashEnterprise=none"; \
    LDFLAGS="$LDFLAGS -X $MODEL.BuildEnterpriseReady=false"; \
    LDFLAGS="$LDFLAGS -X $MODEL.BuildSourceURL=$SOURCE_URL"; \
    LDFLAGS="$LDFLAGS -X $MODEL.BuildDate=$BUILD_DATE"; \
    CGO_ENABLED=0 GOOS=linux \
    go build -buildvcs=false -ldflags="$LDFLAGS" \
        -o /out/mattermost ./cmd/mattermost && \
    CGO_ENABLED=0 GOOS=linux \
    go build -buildvcs=false -ldflags="$LDFLAGS" \
        -o /out/mmctl ./cmd/mmctl

# Fail the build if either binary was not compiled with the patched toolchain.
RUN go version /out/mattermost | grep -q 'go1\.26\.6' \
    || (echo "FATAL: mattermost not built with Go 1.26.6" && exit 1)
RUN go version /out/mmctl | grep -q 'go1\.26\.6' \
    || (echo "FATAL: mmctl not built with Go 1.26.6" && exit 1)

# The upstream runtime is distroless and intentionally has no /bin/sh. Build a
# single-purpose static helper for the one filesystem mutation needed before
# the standalone web client is copied into the final image.
COPY tools/clean-client/main.go /tmp/clean-client.go
RUN CGO_ENABLED=0 GOOS=linux \
    go build -buildvcs=false -trimpath -ldflags="-s -w" \
    -o /out/clean-client /tmp/clean-client.go


# ─────────────────────────────────────────────────────────────────────────────
# Stage 3 — final image
# The official image already has the correct directory layout, plugins,
# i18n files, etc.  We only replace the binary and the webapp assets.
# ─────────────────────────────────────────────────────────────────────────────
FROM mattermost/mattermost-team-edition:11.10 AS runtime

ARG SOURCE_URL
ARG BUILD_NUMBER
ARG BUILD_HASH
ARG BUILD_DATE
ARG WEB_BUILD_HASH
ARG WEB_SOURCE_URL
ARG ASSEMBLY_BUILD_HASH
ARG ASSEMBLY_SOURCE_URL

LABEL org.opencontainers.image.title="YourOwn.Chat Server" \
      org.opencontainers.image.description="AGPL collaboration server based on Mattermost Team Edition" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.url="https://github.com/pilprod/yourown-chat-mattermost" \
      org.opencontainers.image.documentation="https://github.com/pilprod/mattermost/blob/${BUILD_HASH}/docs/product-compliance.md" \
      org.opencontainers.image.revision="${BUILD_HASH}" \
      org.opencontainers.image.version="${BUILD_NUMBER}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      io.yourown.chat.server.source="${SOURCE_URL}" \
      io.yourown.chat.server.revision="${BUILD_HASH}" \
      io.yourown.chat.web.source="${WEB_SOURCE_URL}" \
      io.yourown.chat.web.revision="${WEB_BUILD_HASH}" \
      io.yourown.chat.assembly.source="${ASSEMBLY_SOURCE_URL}" \
      io.yourown.chat.assembly.revision="${ASSEMBLY_BUILD_HASH}"

USER root

# COPY merges directories. Empty the upstream client first so stale hashed
# assets from the base image cannot survive beside the standalone web build.
# The helper removes itself while running, so the distroless runtime remains
# shell-free.
COPY --from=server-builder /out/clean-client /tmp/clean-client
RUN ["/tmp/clean-client", "/mattermost/client", "clean"]

# The upstream Team image used for the patched 11.10 build does not contain the
# Calls bundle. Keep the test-only delivery deterministic by prepackaging the
# official, signed linux/amd64 bundle instead of enabling plugin uploads or
# downloading code at runtime. Mattermost verifies the adjacent signature when
# its signature policy is enabled and honours its own edition/license behaviour;
# this image does not modify, suppress, or bypass those checks.
#
# Mattermost 11.10 pins Calls v1.12.2 in its server Makefile.
# The checksum pins the release asset independently of mutable GitHub URLs.
ARG CALLS_PLUGIN_VERSION=v1.12.2
ARG CALLS_PLUGIN_SHA256=f9e2f566467b11dd982c9d0efa971fe061f2d4ae018d169db2f794ae54348eea
ARG CALLS_PLUGIN_SIGNATURE_SHA256=ebf4cf243c9f9ee2631a4d68f9e2bdd8f73ec808252627b5cd73525b7aead9b6
ADD --checksum=sha256:${CALLS_PLUGIN_SHA256} --chown=2000:2000 \
  https://github.com/mattermost/mattermost-plugin-calls/releases/download/${CALLS_PLUGIN_VERSION}/mattermost-plugin-calls-${CALLS_PLUGIN_VERSION}-linux-amd64.tar.gz \
  /mattermost/prepackaged_plugins/mattermost-plugin-calls-${CALLS_PLUGIN_VERSION}-linux-amd64.tar.gz
ADD --checksum=sha256:${CALLS_PLUGIN_SIGNATURE_SHA256} --chown=2000:2000 \
  https://github.com/mattermost/mattermost-plugin-calls/releases/download/${CALLS_PLUGIN_VERSION}/mattermost-plugin-calls-${CALLS_PLUGIN_VERSION}-linux-amd64.tar.gz.sig \
  /mattermost/prepackaged_plugins/mattermost-plugin-calls-${CALLS_PLUGIN_VERSION}-linux-amd64.tar.gz.sig

# Replace both public binaries.
COPY --from=server-builder --chown=2000:2000 \
    /out/mattermost /mattermost/bin/mattermost
COPY --from=server-builder --chown=2000:2000 \
    /out/mmctl /mattermost/bin/mmctl

# Replace the compiled webapp.
# The official image serves static files from /mattermost/client/.
COPY --from=webapp-builder --chown=2000:2000 \
    /src/webapp/channels/dist/ /mattermost/client/

# The web output contains the plugins directory and can replace its metadata
# while Docker merges the client tree. Normalize it after every client copy so
# Mattermost (UID/GID 2000) can install signed plugin webapp bundles at runtime.
COPY --from=server-builder /out/clean-client /tmp/clean-client
RUN ["/tmp/clean-client", "/mattermost/client", "finalize"]

# Keep upstream attribution and the fork modification notice in every image.
COPY --chown=2000:2000 \
    sources/server/LICENSE.txt \
    sources/server/NOTICE.txt \
    sources/server/PRODUCT-NOTICE.md \
    /mattermost/licenses/

USER 2000
