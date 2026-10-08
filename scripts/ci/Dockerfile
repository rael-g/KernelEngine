FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ENV DEBIAN_FRONTEND=noninteractive \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1

ARG APT_SNAPSHOT=20261001T000000Z
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && apt-get update --snapshot "${APT_SNAPSHOT}" \
    && apt-get install -y --no-install-recommends --snapshot "${APT_SNAPSHOT}" \
        ca-certificates curl git unzip zip tar xz-utils build-essential cmake ninja-build \
        pkg-config xorg-dev libgl1-mesa-dev libglu1-mesa-dev libicu74 mesa-vulkan-drivers \
    && rm -rf /var/lib/apt/lists/*

ARG ZIG_VERSION=0.16.0
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" | tar -xJ -C /opt \
    && ln -s "/opt/zig-x86_64-linux-${ZIG_VERSION}/zig" /usr/local/bin/zig

ARG DOTNET_CHANNEL=10.0
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && bash /tmp/dotnet-install.sh --channel "${DOTNET_CHANNEL}" --install-dir /usr/share/dotnet \
    && ln -s /usr/share/dotnet/dotnet /usr/local/bin/dotnet \
    && rm /tmp/dotnet-install.sh

WORKDIR /work
