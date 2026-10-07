# Inselfahrt als Web-Export, ausgeliefert per nginx (docker-compose.yml im Repo-Root, #21).
# Stufe 1: Godot headless importiert das Projekt und exportiert das Preset "Web"
# (export_presets.cfg, ohne Threads → keine COOP/COEP-Header nötig).
FROM debian:bookworm-slim AS export

# Godot und Export-Templates fest gepinnt (SHA512 aus SHA512-SUMS.txt des Releases).
ARG GODOT_VERSION=4.4.1
ARG GODOT_SHA512=ef4e76880a514257175544952c61191106fdef3095b909bafed9fcbeb230c3e5533920a0f3012882dd4bbde83028a67549825794e2d2c3cf76eba7918b71370e
ARG TEMPLATES_SHA512=8f461c7d6e91a0fbabfc95b1e4ca70ff1732c6f2920956a16b086ec2a85b5f7e238baf4dbce60dcc5630fae3bcb9a1fa2ae2027b92cb495c02d082705715e441
ARG RELEASE_URL=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/godot
RUN curl -fsSL -o godot.zip "${RELEASE_URL}/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    && echo "${GODOT_SHA512}  godot.zip" | sha512sum -c - \
    && unzip -q godot.zip \
    && mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
    && rm godot.zip
# Aus dem Template-Paket (~1 GB) nur das Web-Template ohne Threads behalten.
RUN curl -fsSL -o templates.tpz "${RELEASE_URL}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    && echo "${TEMPLATES_SHA512}  templates.tpz" | sha512sum -c - \
    && dest="/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
    && mkdir -p "$dest" \
    && unzip -q -j templates.tpz templates/web_nothreads_release.zip templates/version.txt -d "$dest" \
    && rm templates.tpz

WORKDIR /src
COPY . .
# *.import ist nicht im Git: erst importieren, dann exportieren.
RUN godot --headless --path /src --import \
    && mkdir -p /out \
    && godot --headless --path /src --export-release "Web" /out/index.html \
    && test -s /out/index.wasm && test -s /out/index.pck

# Stufe 2: nur die exportierten Dateien hinter nginx (application/wasm kennt nginx bereits).
FROM nginx:1.27-alpine
COPY --from=export /out /usr/share/nginx/html
EXPOSE 80
