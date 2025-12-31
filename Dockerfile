FROM debian:trixie-slim AS base
LABEL org.opencontainers.image.source="https://github.com/C4illin/ConvertX"
WORKDIR /app

# install bun
RUN apt-get update && apt-get install -y \
  curl \
  unzip \
  && rm -rf /var/lib/apt/lists/*

# if architecture is arm64, use the arm64 version of bun
RUN ARCH=$(uname -m) && \
  if [ "$ARCH" = "aarch64" ]; then \
    curl -fsSL -o bun-linux-aarch64.zip https://github.com/oven-sh/bun/releases/download/bun-v1.2.2/bun-linux-aarch64.zip; \
  else \
    curl -fsSL -o bun-linux-x64-baseline.zip https://github.com/oven-sh/bun/releases/download/bun-v1.2.2/bun-linux-x64-baseline.zip; \
  fi

RUN unzip -j bun-linux-*.zip -d /usr/local/bin && \
  rm bun-linux-*.zip && \
  chmod +x /usr/local/bin/bun

# install dependencies into temp directory
# this will cache them and speed up future builds
FROM base AS install
RUN mkdir -p /temp/dev
COPY package.json bun.lock /temp/dev/
RUN cd /temp/dev && bun install --frozen-lockfile

# install with --production (exclude devDependencies)
RUN mkdir -p /temp/prod
COPY package.json bun.lock /temp/prod/
RUN cd /temp/prod && bun install --frozen-lockfile --production

FROM base AS prerelease
WORKDIR /app
COPY --from=install /temp/dev/node_modules node_modules
COPY . .

# ENV NODE_ENV=production
RUN bun run build

# copy production dependencies and source code into final image
FROM base AS release

# Install dependencies in batches to reduce peak memory usage during build
# Batch 1: Core media tools
RUN apt-get update && apt-get install -y --no-install-recommends \
  ffmpeg \
  ghostscript \
  graphicsmagick \
  imagemagick-7.q16 \
  libva2 \
  libvips-tools \
  && rm -rf /var/lib/apt/lists/*

# Batch 2: Document converters (excluding LibreOffice)
RUN apt-get update && apt-get install -y --no-install-recommends \
  calibre \
  pandoc \
  poppler-utils \
  mupdf-tools \
  libemail-outlook-message-perl \
  && rm -rf /var/lib/apt/lists/*

# Batch 3: LibreOffice (largest package - installed separately)
RUN apt-get update && apt-get install -y --no-install-recommends \
  libreoffice \
  && rm -rf /var/lib/apt/lists/*

# Batch 4: Image tools
RUN apt-get update && apt-get install -y --no-install-recommends \
  dcraw \
  inkscape \
  libheif-examples \
  libjxl-tools \
  potrace \
  resvg \
  && rm -rf /var/lib/apt/lists/*

# Batch 5: Other utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
  assimp-utils \
  dasel \
  dvisvgm \
  latexmk \
  python3-numpy \
  && rm -rf /var/lib/apt/lists/*

# Batch 6: TeX packages (large, install last)
RUN apt-get update && apt-get install -y --no-install-recommends \
  lmodern \
  texlive \
  texlive-fonts-recommended \
  texlive-latex-extra \
  texlive-latex-recommended \
  texlive-xetex \
  && rm -rf /var/lib/apt/lists/*

# Install VTracer binary
RUN ARCH=$(uname -m) && \
  if [ "$ARCH" = "aarch64" ]; then \
    VTRACER_ASSET="vtracer-aarch64-unknown-linux-musl.tar.gz"; \
  else \
    VTRACER_ASSET="vtracer-x86_64-unknown-linux-musl.tar.gz"; \
  fi && \
  curl -L -o /tmp/vtracer.tar.gz "https://github.com/visioncortex/vtracer/releases/download/0.6.4/${VTRACER_ASSET}" && \
  tar -xzf /tmp/vtracer.tar.gz -C /tmp/ && \
  mv /tmp/vtracer /usr/local/bin/vtracer && \
  chmod +x /usr/local/bin/vtracer && \
  rm /tmp/vtracer.tar.gz

COPY --from=install /temp/prod/node_modules node_modules
COPY --from=prerelease /app/public/ /app/public/
COPY --from=prerelease /app/dist /app/dist

# COPY . .
RUN mkdir data

EXPOSE 3000/tcp
# used for calibre
ENV QTWEBENGINE_CHROMIUM_FLAGS="--no-sandbox"
ENV NODE_ENV=production
ENTRYPOINT [ "bun", "run", "dist/src/index.js" ]