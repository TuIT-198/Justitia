FROM postgres:15-alpine

ARG PGVECTOR_VERSION=0.8.1

RUN apk add --no-cache --virtual .pgvector-build-deps build-base ca-certificates \
    && wget -qO- "https://github.com/pgvector/pgvector/archive/refs/tags/v${PGVECTOR_VERSION}.tar.gz" \
       | tar -xz -C /tmp \
    && make -C "/tmp/pgvector-${PGVECTOR_VERSION}" OPTFLAGS="" with_llvm=no \
    && make -C "/tmp/pgvector-${PGVECTOR_VERSION}" install with_llvm=no \
    && rm -rf "/tmp/pgvector-${PGVECTOR_VERSION}" \
    && apk del .pgvector-build-deps
