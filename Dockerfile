# syntax=docker/dockerfile:1
# What Atlas builds. Nothing is compiled here: the Julia side comes from the
# release named below, so that release must already have its asset attached.

FROM debian:bookworm-slim AS bundle

# Bump with each release
ARG SID_VERSION=v1.0.0-alpha.4
# The trimmed build (build/Dockerfile with TRIM=1). Or a local path, to try a
# bundle built on this machine
ARG BUNDLE=https://github.com/dpaa-gov/SID/releases/download/${SID_VERSION}/sid-trim-linux-x86_64.tar.gz

# A URL arrives as the archive; a local archive arrives already unpacked
ADD ${BUNDLE} /tmp/bundle/
RUN mkdir -p /opt && \
    if [ -d /tmp/bundle/sid ]; then mv /tmp/bundle/sid /opt/sid; \
    else tar -xzf /tmp/bundle/*.tar.gz -C /opt; fi

FROM debian:bookworm-slim

RUN useradd --uid 10001 --create-home sid
COPY --from=bundle /opt/sid /opt/sid

# Read at run time, at the paths the program was compiled with
WORKDIR /app
COPY server/config /app/server/config
COPY web /app/web
COPY VERSION /app/VERSION

# Two worker threads for analyses, one interactive thread for requests
ENV JULIA_NUM_THREADS=2,1 \
    PORT=3838

USER sid
EXPOSE 3838
# Atlas reads the probe path from this line when it first inspects the
# repository; after that it is a setting on the environment. The image has no
# curl, so plain Docker reports the container unhealthy; it still runs.
HEALTHCHECK CMD curl -f http://localhost:3838/healthz
CMD ["/opt/sid/bin/sid"]
