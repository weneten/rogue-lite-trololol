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
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /project
COPY . .

COPY --from=web-template-builder \
    /opt/godot-src/bin/godot.web.template_release.wasm32.nothreads.zip \
    /root/.local/share/godot/export_templates/4.7.stable/web_nothreads_release.zip
COPY --from=web-template-builder \
    /opt/godot-src/bin/godot.web.template_debug.wasm32.nothreads.zip \
    /root/.local/share/godot/export_templates/4.7.stable/web_nothreads_debug.zip

# Headless export requires a named preset; write it here so the build does not
# depend on export_presets.cfg being present in the build context.
RUN printf '%s\n' \
    '[preset.0]' \
    '' \
    'name="Web"' \
    'platform="Web"' \
    'runnable=true' \
    'advanced_options=false' \
    'dedicated_server=false' \
    'custom_features=""' \
    'export_filter="all_resources"' \
    'include_filter=""' \
    'exclude_filter=""' \
    'export_path="build/web/index.html"' \
    'patches=PackedStringArray()' \
    'encryption_include_filters=""' \
    'encryption_exclude_filters=""' \
    'seed=0' \
    'encrypt_pck=false' \
    'encrypt_directory=false' \
    'script_export_mode=2' \
    '' \
    '[preset.0.options]' \
    '' \
    'custom_template/debug=""' \
    'custom_template/release=""' \
    'variant/extensions_support=false' \
    'variant/thread_support=false' \
    'vram_texture_compression/for_desktop=true' \
    'vram_texture_compression/for_mobile=false' \
    'html/export_icon=true' \
    'html/custom_html_shell=""' \
    'html/canvas_resize_policy=2' \
    'html/head_include="<style>html,body,#canvas{margin:0;padding:0;width:100%;height:100%;overflow:hidden;background:#000}#canvas{display:block;object-fit:contain}</style>"' \
    'html/focus_canvas_on_start=true' \
    'html/experimental_virtual_keyboard=false' \
    'progressive_web_app/enabled=false' \
    'progressive_web_app/ensure_cross_origin_isolation_headers=false' \
    'progressive_web_app/offline_page=""' \
    'progressive_web_app/display=1' \
    'progressive_web_app/orientation=0' \
    'progressive_web_app/icon_144x144=""' \
    'progressive_web_app/icon_180x180=""' \
    'progressive_web_app/icon_512x512=""' \
    'progressive_web_app/background_color=Color(0, 0, 0, 1)' \
    'threads/emscripten_pool_size=8' \
    'threads/godot_pool_size=4' \
    > export_presets.cfg

RUN mkdir -p build/web \
    && godot --headless --import --quit \
    && godot --headless --export-release "Web" build/web/index.html

FROM nginx:alpine AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /project/build/web /usr/share/nginx/html
EXPOSE 80
