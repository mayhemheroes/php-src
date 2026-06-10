# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for php-src — re-bases PHP's OSS-Fuzz fuzzer integration onto the org
# C/C++ base (ghcr.io/mayhemheroes/base), which provides debian + clang/llvm + libFuzzer/ASan/UBSan
# + the build contract ENV. PHP's autotools build needs a few extra packages (bison/re2c/autoconf/…),
# installed as root before dropping back to the non-root mayhem user for the build.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t php-src-commit:test .

FROM ghcr.io/mayhemheroes/base:2026-06

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf automake libtool bison re2c pkg-config make zip ca-certificates \
    && rm -rf /var/lib/apt/lists/*
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run the known-answer oracle at build time — a failing suite fails the image build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
