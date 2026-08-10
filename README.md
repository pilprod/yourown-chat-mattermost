# YourOwn.Chat Mattermost image

This repository contains only the reproducible Docker assembly for the
YourOwn.Chat Mattermost distribution. Product source is supplied by pinned Git
submodules:

- `sources/mattermost` — the patched public server fork at
  `pilprod/mattermost`;
- `sources/web` — the standalone client at `pilprod/yourown-chat-web`.

Server changes stay in the server fork. Web changes stay in the web repository.
This repository combines their immutable revisions into one runtime image.

## Clone and initialize

```sh
git clone https://github.com/pilprod/yourown-chat-mattermost.git
cd yourown-chat-mattermost
./scripts/init-sources.sh
```

The initialization script uses sparse checkouts: only `server/` and license
files are materialized from Mattermost, and only `web/` is materialized from the
web repository.

## Build

```sh
IMAGE=ghcr.io/pilprod/yourown-chat-mattermost:dev \
BUILD_NUMBER=11.9.0-dev.1 \
./scripts/build-image.sh
```

The script derives both source revisions from the submodules and records them
as OCI image labels, together with the assembly repository revision.
`BUILD_DATE`, `BUILD_NUMBER`, and `IMAGE` can be overridden by CI. Additional
arguments are forwarded to `docker build`.

The final image uses the official Mattermost Team Edition runtime, replaces its
public server binaries with the patched build, and replaces `/mattermost/client`
with the standalone YourOwn.Chat web build.

## Release contract

The assembly repository is the release entrypoint. Before a release, update and
review both submodule pointers; CI refuses to build unless the assembly, server,
and web sources are all represented by exact 40-character commit SHAs.

- `release-X.Y` branches build commit-addressed preview images and may deploy
  only to dev.
- `X.Y.Z-suffix` tags (for example `11.9.0-rc.1`) build immutable prerelease
  images and may deploy only to dev.
- Stable `X.Y.Z` tags (for example `11.9.0`) build immutable release images and
  enter the normal dev-to-production promotion pipeline.
- The server SHA is the image's Corresponding Source revision. Separate labels
  retain the exact web and assembly revisions.

`scripts/verify-product-image.sh` verifies the pushed image's labels, public
Team Edition build metadata, and mandatory license notices before deployment.
