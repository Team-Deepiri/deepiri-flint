# Bedd runtime image — Bun-style toolkit (not a long-running microservice).
# Ships glibc + musl binaries for COPY --from into worker images.
#
#   docker build -t ghcr.io/team-deepiri/bedd:0.7 .
#
# Alpine / musl worker:
#   COPY --from=ghcr.io/team-deepiri/bedd:0.7 /opt/bedd/bedd-musl /usr/local/bin/bedd
# Debian / glibc worker:
#   COPY --from=ghcr.io/team-deepiri/bedd:0.7 /usr/local/bin/bedd /usr/local/bin/bedd
# Both:
#   COPY --from=ghcr.io/team-deepiri/bedd:0.7 /opt/bedd/skills /opt/bedd/skills

ARG ZIG_VERSION=0.13.0

FROM debian:bookworm-slim AS build
ARG ZIG_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends curl xz-utils ca-certificates \
  && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
  | tar -xJ -C /opt \
  && ln -s /opt/zig-linux-x86_64-${ZIG_VERSION}/zig /usr/local/bin/zig
WORKDIR /src
COPY . .
RUN zig build -Doptimize=ReleaseSafe -Dcpu=baseline \
  && cp zig-out/bin/bedd /tmp/bedd-gnu \
  && zig build -Doptimize=ReleaseSafe -Dcpu=baseline -Dtarget=x86_64-linux-musl \
  && cp zig-out/bin/bedd /tmp/bedd-musl \
  && mkdir -p /tmp/skills \
  && if [ -d zig-out/skills ]; then cp -a zig-out/skills/. /tmp/skills/; fi

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /tmp/bedd-gnu /usr/local/bin/bedd
COPY --from=build /tmp/bedd-musl /opt/bedd/bedd-musl
COPY --from=build /tmp/skills /opt/bedd/skills
COPY tinder.example.json /opt/bedd/tinder.example.json
ENV BEDD_SKILLS_DIR=/opt/bedd/skills
ENV PATH="/usr/local/bin:${PATH}"
ENTRYPOINT ["bedd"]
CMD ["help"]
