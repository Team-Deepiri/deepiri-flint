# Dockerfile for deepiri-bedd

FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends curl xz-utils ca-certificates \
  && rm -rf /var/lib/apt/lists/*
ARG ZIG_VERSION=0.13.0
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
  | tar -xJ -C /opt \
  && ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig
WORKDIR /src
COPY . .
RUN zig build -Doptimize=ReleaseSafe

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/zig-out/bin/bedd /usr/local/bin/bedd
COPY --from=build /src/zig-out/skills /opt/bedd/skills
COPY tinder.example.json /opt/bedd/tinder.example.json
ENV BEDD_SKILLS_DIR=/opt/bedd/skills
ENV BEDD_TINDER=/opt/bedd/tinder.example.json
ENTRYPOINT ["bedd"]
CMD ["serve"]
