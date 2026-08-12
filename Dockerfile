# zt-ui Docker image.
#
# Multi-stage build: stage 1 fetches Zig 0.16.0, builds the WASM artifact and
# the dev server. Stage 2 is a slim runtime image that serves web/ on
# 0.0.0.0:8080 with the in-tree Zig HTTP server.
#
# Multi-arch: works for linux/amd64 and linux/arm64 via TARGETARCH (set
# automatically by `docker buildx`).

ARG ZIG_VERSION=0.16.0
ARG DEBIAN_VERSION=bookworm-slim

# ---------- builder ----------
FROM debian:${DEBIAN_VERSION} AS builder

ARG ZIG_VERSION
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Map Docker's TARGETARCH to Zig's release naming and pin sha256 per arch.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) ZIG_ARCH="x86_64";  ZIG_SHA256="70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00" ;; \
        arm64) ZIG_ARCH="aarch64"; ZIG_SHA256="ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    ZIG_DIR="zig-${ZIG_ARCH}-linux-${ZIG_VERSION}"; \
    curl -fsSL -o /tmp/zig.tar.xz \
        "https://ziglang.org/download/${ZIG_VERSION}/${ZIG_DIR}.tar.xz"; \
    echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/zig; \
    tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; \
    rm /tmp/zig.tar.xz; \
    ln -s /opt/zig/zig /usr/local/bin/zig; \
    zig version

WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src ./src
COPY web ./web

RUN zig build -Doptimize=ReleaseSafe

# ---------- runtime ----------
FROM debian:${DEBIAN_VERSION} AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 zt \
    && useradd  --system --uid 10001 --gid zt --home-dir /app --shell /usr/sbin/nologin zt

WORKDIR /app

COPY --from=builder /src/zig-out/bin/zt-ui-serve /usr/local/bin/zt-ui-serve
COPY --from=builder --chown=zt:zt /src/web ./web

ENV ZT_UI_HOST=0.0.0.0 \
    ZT_UI_PORT=8080

USER zt
EXPOSE 8080

# The server resolves `ZT_UI_PORT` itself, so the image can use an exec-form
# entrypoint with no shell in the startup path.
ENTRYPOINT ["/usr/local/bin/zt-ui-serve"]
