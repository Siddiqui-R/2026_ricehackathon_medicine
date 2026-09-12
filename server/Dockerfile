# syntax=docker/dockerfile:1
# Purpose: Build the RevaAPI Vapor executable and ship it with its SwiftPM resource bundles in a slim image.
# Inputs: The server/ directory as the build context (Package.swift, Package.resolved, Sources/, Tests/) and
#         build-time network access for Swift Package Manager dependency resolution.
# Outputs: A runtime image that starts `./RevaAPI serve` as a non-root user on 0.0.0.0:8080. Storage, token,
#          account, and CORS settings come from the environment at run time; see docs/tiger-setup.md.
# Side effects: None beyond the image layers. No credential is baked in. This file follows the Vapor template
#               but was NOT built locally: Docker is not installed on the authoring machine.

# MARK: - Build stage: release binary with the Swift runtime linked statically
FROM swift:6.1-noble AS build
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /build

# Resolve dependencies from the checked-in lockfile first so source edits reuse this cached layer.
COPY ./Package.* ./
RUN swift package resolve --force-resolved-versions

COPY . .
RUN swift build -c release --product RevaAPI --static-swift-stdlib

# Stage the executable plus every *.resources bundle. RevaServer_RevaServer.resources carries the
# Migrations/*.sql files that PostgresStore loads through Bundle.module at start-up.
WORKDIR /staging
RUN BIN="$(swift build --package-path /build -c release --show-bin-path)" \
 && cp "$BIN/RevaAPI" ./ \
 && find -L "$BIN/" -regex '.*\.resources$' -exec cp -Ra {} ./ \; \
 && ls -la /staging

# MARK: - Runtime stage: slim image, CA trust for Tiger TLS, non-root user, writable data directory
FROM swift:6.1-noble-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get -q update \
 && apt-get -q install -y --no-install-recommends ca-certificates tzdata \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app reva
WORKDIR /app
COPY --from=build --chown=reva:reva /staging /app

# Call receipts live under REVA_DATA_DIRECTORY even in PostgreSQL mode; mount a persistent volume here.
RUN mkdir -p /app/data && chown reva:reva /app/data
VOLUME ["/app/data"]

USER reva:reva
ENV REVA_HOST=0.0.0.0 \
    REVA_PORT=8080 \
    REVA_DATA_DIRECTORY=/app/data
EXPOSE 8080

# The server rejects Vapor CLI binding overrides; the listener is configured through REVA_HOST/REVA_PORT.
CMD ["./RevaAPI", "serve"]
