# SPDX-License-Identifier: MIT
# Omarchy Mobile build environment: Ubuntu LTS with the LineageOS build packages.
# Pinned by digest (docs/RELEASES.md §9): ubuntu:24.04's multi-arch index on
# Docker Hub, resolved 2026-11-01. Bump it on purpose, never by a rebuild.
# The apt packages below still come from the archive of the day the image is
# built; the kernel build takes make, perl, flex, bison and host libraries
# from them, and its compiler, linker and host compiler are the pinned
# Android clang (tools/fetch-toolchain), mounted from the host.
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8

# The multilib and lib32 packages exist only for x86 (they serve the
# LineageOS reference build). An arm64 builder can't run the pinned
# linux-x86 Android clang, so it gets Ubuntu's LLVM in the image instead,
# at the path where bin/omamobile mounts the clang on x86 (CONTAINER_CLANG);
# on an arm64 host bin/omamobile mounts nothing over it. The architecture is
# the image's own, so every builder (BuildKit or the legacy one) agrees.
RUN case "$(dpkg --print-architecture)" in \
      amd64) arch_pkgs="g++-multilib gcc-multilib lib32readline-dev lib32z1-dev" ;; \
      arm64) arch_pkgs="clang-20 lld-20 llvm-20" ;; \
      *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac \
    && apt-get update && apt-get install -y --no-install-recommends \
      bc bison build-essential ca-certificates ccache curl erofs-utils flex \
      git git-lfs gnupg gperf imagemagick \
      protobuf-compiler python3-protobuf $arch_pkgs \
      libdw-dev libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev \
      libxml2 libxml2-utils lzop pngcrush python-is-python3 rsync schedtool \
      squashfs-tools xsltproc xxd zip unzip zlib1g-dev openssh-client zstd \
    && if [ "$(dpkg --print-architecture)" = arm64 ]; then \
      mkdir -p /opt/omamobile && ln -s /usr/lib/llvm-20 /opt/omamobile/clang; \
    fi \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo \
    && chmod 755 /usr/local/bin/repo

# Build as an unprivileged user matching the host user, so files stay owned by them.
RUN (id -u $UID >/dev/null 2>&1 && userdel -r $(id -nu $UID) || true) \
    && (getent group $GID || groupadd -g $GID builder) \
    && useradd -m -u $UID -g $GID -s /bin/bash builder

USER builder
WORKDIR /home/builder

ENV USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache CCACHE_DIR=/ccache
