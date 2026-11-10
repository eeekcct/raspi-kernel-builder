# syntax=docker/dockerfile:1
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash bc bison build-essential ca-certificates cpio flex git \
      gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
      libelf-dev libssl-dev libncurses-dev kmod pahole \
      python3 rsync xz-utils zstd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/builder
COPY kernel.commit ./kernel.commit
COPY scripts/ ./scripts/
COPY tests/ ./tests/
RUN bash -n scripts/build.sh && python3 -m unittest discover -s tests -v

ENV WORK_DIR=/work OUTPUT_DIR=/out JOBS=2 DEFCONFIG=bcm2711_defconfig
ENTRYPOINT ["bash", "/opt/builder/scripts/build.sh"]
CMD ["build"]
