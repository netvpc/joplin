FROM node:lts-bookworm AS gitclone

ARG VERSION

RUN git clone --recurse-submodules -j8 --depth 1 --branch ${VERSION} https://github.com/laurent22/joplin.git

FROM node:lts-bookworm AS builder

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    # Required for both armv7 and armv8
        python3 \
        rsync \
        libssl-dev \
    # Required for compiling canvas package, refer to https://www.npmjs.com/package/canvas#compiling
        build-essential \
        libcairo2-dev \
        libpango1.0-dev \
        libjpeg-dev \
        libgif-dev \
        librsvg2-dev \
    # Additional dependencies for canvas and other graphic-related libraries
        libfreetype6-dev \
        libfontconfig1-dev \
    # Required for sqlite3 package
        libsqlite3-dev \
        pkg-config \
    # Change memory allocator to avoid leaks
        libjemalloc2

# COPY --from=gitclone /joplin/ /build/

# Copy yarn-related files and configurations
COPY --from=gitclone /joplin/.yarn/plugins /build/.yarn/plugins/
COPY --from=gitclone /joplin/.yarn/patches /build/.yarn/patches/
COPY --from=gitclone /joplin/.yarn/releases /build/.yarn/releases/
COPY --from=gitclone /joplin/.yarnrc.yml /build/
# COPY --from=gitclone /joplin/yarn.lock /build/

# Copy build configuration and main project files
COPY --from=gitclone /joplin/gulpfile.js /build/
COPY --from=gitclone /joplin/package.json /build/
COPY --from=gitclone /joplin/tsconfig.json /build/

# Copy package folders (each related to specific functionalities)
COPY --from=gitclone /joplin/packages/fork-htmlparser2 /build/packages/fork-htmlparser2/
COPY --from=gitclone /joplin/packages/fork-sax /build/packages/fork-sax/
COPY --from=gitclone /joplin/packages/fork-uslug /build/packages/fork-uslug/
COPY --from=gitclone /joplin/packages/htmlpack /build/packages/htmlpack/
COPY --from=gitclone /joplin/packages/lib /build/packages/lib/
COPY --from=gitclone /joplin/packages/renderer /build/packages/renderer/
COPY --from=gitclone /joplin/packages/server /build/packages/server/
COPY --from=gitclone /joplin/packages/server/package*.json /build/packages/server/
COPY --from=gitclone /joplin/packages/tools /build/packages/tools/
COPY --from=gitclone /joplin/packages/turndown /build/packages/turndown/
COPY --from=gitclone /joplin/packages/turndown-plugin-gfm /build/packages/turndown-plugin-gfm/
COPY --from=gitclone /joplin/packages/utils /build/packages/utils/

WORKDIR /build/

RUN corepack enable && corepack prepare yarn@stable --activate

RUN dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" && \
    case "$dpkgArch" in \
        armhf) \
            export LD_PRELOAD=/usr/lib/arm-linux-gnueabihf/libjemalloc.so.2 && \
            export NODE_OPTIONS=--max-old-space-size=3072 \
            ;; \
        arm64) \
            export LD_PRELOAD=/usr/lib/aarch64-linux-gnu/libjemalloc.so.2 \
            ;; \
        amd64) \
            export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2 \
            ;; \
        *) \
            echo "Unsupported architecture: $dpkgArch"; exit 1 \
            ;; \
    esac && \
    echo "Using LD_PRELOAD=$LD_PRELOAD" && \
    \
    ATTEMPT=0; \
    until [ $ATTEMPT -ge 3 ]; do \
        GENERATE_SOURCEMAP=false BUILD_SEQUENCIAL=1 yarn install --inline-builds && break; \
        ATTEMPT=$((ATTEMPT+1)); \
        echo "Yarn install failed... retrying ($ATTEMPT/3)"; \
        sleep 5; \
    done && \
    yarn cache clean && \
    rm -rf .yarn/berry && \
    rm -rf .yarn/cache

FROM node:lts-bookworm-slim AS final

ENV NODE_ENV=production \
    GOSU_VERSION=1.17 \
    TINI_VERSION=v0.19.0 \
    UID=1000 \
    GID=1000

RUN set -eux; \
    # Save list of currently installed packages for later cleanup
        savedAptMark="$(apt-mark showmanual)"; \
        apt-get update; \
        DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-install-recommends ca-certificates gnupg wget; \
        rm -rf /var/lib/apt/lists/*; \
        \
    # Install gosu
        dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
        wget -q -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
        wget -q -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
        export GNUPGHOME="$(mktemp -d)"; \
        gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
        gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
        gpgconf --kill all; \
        rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
        chmod +x /usr/local/bin/gosu; \
        gosu --version; \
        gosu nobody true; \
        \
    # Install Tini
        : "${TINI_VERSION:?TINI_VERSION is not set}"; \
        dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
        echo "Downloading Tini version ${TINI_VERSION} for architecture ${dpkgArch}"; \
        wget -q -O /usr/bin/tini "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-$dpkgArch"; \
        wget -q -O /usr/bin/tini.asc "https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini-$dpkgArch.asc"; \
        export GNUPGHOME="$(mktemp -d)"; \
        gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7; \
        gpg --batch --verify /usr/bin/tini.asc /usr/bin/tini; \
        gpgconf --kill all; \
        rm -rf "$GNUPGHOME" /usr/bin/tini.asc; \
        chmod +x /usr/bin/tini; \
        echo "Tini version: $(/usr/bin/tini --version)"; \
        \
    # Clean up
        apt-mark auto '.*' > /dev/null; \
        [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
        apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false
        
COPY --from=builder --chown=1000:1000 /build/packages /home/node/packages
COPY prepare.sh /usr/bin/prepare

VOLUME [ "/mnt/files" ]
ENTRYPOINT ["tini", "--", "prepare"]
CMD ["yarn", "start-prod"]
