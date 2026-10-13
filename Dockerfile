# Mailcheap for Railway.
# Builds Mailcheap from upstream source pinned to a commit, so every deploy is
# reproducible. The update workflow (.github/workflows/update.yml) bumps
# MAILCHEAP_REF after a smoke test.
#
# One small patch (patches/) stores editor image uploads on the service volume
# instead of Vercel Blob. Everything else runs unmodified.
FROM node:22-bookworm-slim AS build

ARG MAILCHEAP_REF=67d13b028a6ecae9ec56d49c4b2db58019217eba

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN curl -fsSL "https://codeload.github.com/marclou/mailcheap/tar.gz/${MAILCHEAP_REF}" \
      | tar -xz --strip-components=1 \
    && echo "$MAILCHEAP_REF" > .mailcheap-ref

# Fails the build if upstream changed the code the patch relies on.
COPY patches /tmp/patches
RUN sh /tmp/patches/apply.sh /app

ENV NEXT_TELEMETRY_DISABLED=1
RUN npm ci --no-audit --no-fund \
    && npm run build \
    && npm prune --omit=dev --no-audit --no-fund \
    && npm cache clean --force \
    && rm -rf .next/cache

FROM node:22-bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build --chown=node:node /app /app

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# BLOB_READ_WRITE_TOKEN only switches on Mailcheap's upload endpoint. The
# patched lib/blob.js writes to UPLOADS_DIR and never calls Vercel.
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=8080 \
    DATA_DIR=/data \
    UPLOADS_DIR=/data/uploads \
    BLOB_READ_WRITE_TOKEN=railway-volume

EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh"]
