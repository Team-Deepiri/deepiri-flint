# Install Bedd

Bedd is a Bun-style **runtime/CLI**. Install it onto PATH or `COPY` it into a worker image.
Do **not** run it as a Compose microservice.

## Host (`install.sh`)

```bash
curl -fsSL https://raw.githubusercontent.com/Team-Deepiri/deepiri-bedd/main/install.sh | bash
# or from a checkout:
./install.sh
export PATH="$HOME/.bedd/bin:$PATH"
bedd version
```

Env: `BEDD_VERSION`, `BEDD_INSTALL`, `BEDD_FORCE=1`, `BEDD_REPO`.

## From source

```bash
# Zig 0.13
zig build -Doptimize=ReleaseSafe -Dcpu=baseline
export PATH="$PWD/zig-out/bin:$PATH"
```

## Docker image (gnu + musl)

```bash
docker build -t ghcr.io/team-deepiri/bedd:0.7 .
```

Layout:

| Path | Use |
|------|-----|
| `/usr/local/bin/bedd` | glibc (Debian/Ubuntu/python:slim) |
| `/opt/bedd/bedd-musl` | musl (Alpine) |
| `/opt/bedd/skills` | default skills dir |

### Embed in a worker Dockerfile

**Alpine / musl:**

```dockerfile
ARG BEDD_IMAGE=ghcr.io/team-deepiri/bedd:0.7
COPY --from=${BEDD_IMAGE} /opt/bedd/bedd-musl /usr/local/bin/bedd
COPY --from=${BEDD_IMAGE} /opt/bedd/skills /opt/bedd/skills
ENV BEDD_SKILLS_DIR=/opt/bedd/skills
```

**Debian / glibc:**

```dockerfile
ARG BEDD_IMAGE=ghcr.io/team-deepiri/bedd:0.7
COPY --from=${BEDD_IMAGE} /usr/local/bin/bedd /usr/local/bin/bedd
COPY --from=${BEDD_IMAGE} /opt/bedd/skills /opt/bedd/skills
ENV BEDD_SKILLS_DIR=/opt/bedd/skills
```

**Suite base (alpine + slim):** copy both and `ln -sf` by detecting `apk`.

## Runtime env

| Var | Meaning |
|-----|---------|
| `BEDD_BUS_URL` | Redis / bus URL |
| `BEDD_DLQ_STREAM` | DLQ stream name |
| `BEDD_TINDER` | Route table JSON |
| `BEDD_SKILLS_DIR` | Skills directory |
