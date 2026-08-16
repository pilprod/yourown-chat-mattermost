# YourOwn.Chat Mattermost image

This repository contains only the reproducible Docker assembly for the
YourOwn.Chat Mattermost distribution. Product source is supplied by pinned Git
submodules kept under `.sources/` and exported into a flat build layout:

- `.sources/mattermost` -> `sources/server` — the patched public server fork at
  `pilprod/mattermost`;
- `.sources/web` -> `sources/web` — the standalone client at
  `pilprod/yourown-chat-web`.

Server changes stay in the server fork. Web changes stay in the web repository.
This repository combines their immutable revisions into one runtime image.

## Clone and initialize

```sh
git clone https://github.com/pilprod/yourown-chat-mattermost.git
cd yourown-chat-mattermost
./scripts/init-sources.sh
```

The initialization script uses sparse checkouts and exports only the consumed
trees. The Docker context therefore has no duplicated directory levels:
`sources/server/go.mod` and `sources/web/package.json` are the source roots.

CI initializes the sources separately:

```sh
./scripts/init-sources.sh server
# Provide the short-lived, repository-scoped credential only to this command.
./scripts/init-sources.sh web
```

This keeps the private web credential out of the public Mattermost submodule
process. Calling the script without an argument remains the authenticated local
development shortcut that initializes both pinned sources.

## Build

```sh
IMAGE=ghcr.io/pilprod/yourown-chat-mattermost:dev \
BUILD_NUMBER=11.10.0-dev.1 \
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

Submodules never follow a moving branch during a build. Their optional branch
is only a maintainer hint; the committed gitlink is the release input. Update
`.sources/mattermost` from the reviewed `release-X.Y-patched` line and
`.sources/web` from reviewed `release-X.Y`, commit both gitlink changes to the
matching assembly release line, and only then create the assembly tag.

Every release has one product version across all three repositories. An
assembly tag `X.Y.Z[-suffix]` requires the web gitlink to carry the exact same
`X.Y.Z[-suffix]` tag and the server gitlink to carry
`vX.Y.Z[-suffix]-patched`. Cloud Build resolves those tags and rejects a build
when either tag points at a different commit.

- `release-X.Y` branches build commit-addressed preview images and may deploy
  only to dev.
- `X.Y.Z-suffix` tags (for example `11.10.0-rc.1`) build immutable prerelease
  images and may deploy only to dev.
- Stable `X.Y.Z` tags (for example `11.10.0`) build immutable release images and
  enter the normal dev-to-production promotion pipeline.
- The server SHA is the image's Corresponding Source revision. Separate labels
  retain the exact web and assembly revisions.

`scripts/verify-product-image.sh` verifies the pushed image's labels, public
Team Edition build metadata, and mandatory license notices before deployment.
