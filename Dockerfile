# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build custom Web export templates with a current Emscripten SDK.
#
# The official Godot 4.7 web export templates are compiled with the
# Emscripten version that was current when 4.7 was released, which still
# emits the legacy WebAssembly exception-handling opcodes ('try'/'catch').
# Browsers now warn that these are deprecated in favor of the standardized
# 'try_table' encoding. Godot itself doesn't use C++ exceptions (they're
# compiled out), but it forces `-sSUPPORT_LONGJMP=wasm`, which relies on
# Wasm EH under the hood for setjmp/longjmp unwinding - that's what emits
# the 'try' instructions.
#
# We rebuild just the Web export templates from the matching Godot source
# tag using the latest Emscripten SDK, with WASM_LEGACY_EXCEPTIONS=0 so the
# compiler emits 'try_table' instead. threads=no dlink_enabled=no matches
# the project's existing "Web" export preset (single-threaded, no
# GDExtension support).
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS web-template-builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    python3 \
    scons \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Matches the editor/template version baked into barichello/godot-ci:4.7.
ARG GODOT_VERSION=4.7-stable

RUN git clone --branch "${GODOT_VERSION}" --depth 1 \
    https://github.com/godotengine/godot.git /opt/godot-src

RUN git clone https://github.com/emscripten-core/emsdk.git /opt/emsdk \
    && cd /opt/emsdk \
    && ./emsdk install latest \
    && ./emsdk activate latest

WORKDIR /opt/godot-src
RUN bash -lc " \
    source /opt/emsdk/emsdk_env.sh && \
    export EMCC_CFLAGS='-sWASM_LEGACY_EXCEPTIONS=0' && \
    scons platform=web target=template_release threads=no dlink_enabled=no production=yes -j\"\$(nproc)\" && \
    scons platform=web target=template_debug threads=no dlink_enabled=no production=yes -j\"\$(nproc)\" \
    "

# ---------------------------------------------------------------------------
# Stage 2: import/export the game, using our custom templates instead of the
# stock ones that ship in the godot-ci image.
# ---------------------------------------------------------------------------
FROM barichello/godot-ci:4.7 AS builder
WORKDIR /project
COPY . .

COPY --from=web-template-builder \
    /opt/godot-src/bin/godot.web.template_release.wasm32.zip \
    /root/.local/share/godot/export_templates/4.7.stable/web_nothreads_release.zip
COPY --from=web-template-builder \
    /opt/godot-src/bin/godot.web.template_debug.wasm32.zip \
    /root/.local/share/godot/export_templates/4.7.stable/web_nothreads_debug.zip

RUN mkdir -p build/web \
    && godot --headless --import --quit \
    && godot --headless --export-release "Web" build/web/index.html

FROM nginx:alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /project/build/web /usr/share/nginx/html
EXPOSE 80
