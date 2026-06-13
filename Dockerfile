FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gnupg \
        lsb-release \
        software-properties-common \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        bc \
        bison \
        build-essential \
        ccache \
        cpio \
        curl \
        device-tree-compiler \
        dialog \
        flex \
        gawk \
        gcc-arm-linux-gnueabihf \
        gcc-arm-linux-gnueabi \
        gettext \
        git \
        jq \
        kmod \
        lib32gcc-s1 \
        libc6-dev-armhf-cross \
        libfdt-dev \
        libfile-fcntllock-perl \
        libfl-dev \
        libgmp-dev \
        libmpc-dev \
        libncurses-dev \
        libpython3-dev \
        libssl-dev \
        libtool \
        libudev-dev \
        linux-headers-generic \
        locales \
        make \
        mtools \
        parted \
        patchutils \
        pkg-config \
        python3 \
        python3-dev \
        python3-distutils \
        python3-pkg-resources \
        python3-venv \
        rsync \
        swig \
        u-boot-tools \
        unzip \
        uuid-dev \
        wget \
        xxd \
        zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 \
        -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN groupadd -g 1000 builder && \
    useradd -m -u 1000 -g 1000 -s /bin/bash builder

RUN mv /bin/sync /bin/sync.real && ln -s /bin/true /bin/sync

WORKDIR /armbian

COPY docker-entrypoint.sh /usr/local/bin/entrypoint-build.sh
RUN chmod +x /usr/local/bin/entrypoint-build.sh

ENTRYPOINT ["/usr/local/bin/entrypoint-build.sh"]
