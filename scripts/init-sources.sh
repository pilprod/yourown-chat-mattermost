#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

git submodule sync --recursive
git -c submodule.fetchJobs=4 submodule update --init --depth 1 --filter=blob:none sources/mattermost sources/web

# Materialize only the source trees consumed by the image assembly.
git -C sources/mattermost sparse-checkout init --no-cone
git -C sources/mattermost sparse-checkout set --no-cone \
    /server/ \
    /LICENSE.txt \
    /NOTICE.txt \
    /PRODUCT-NOTICE.md

git -C sources/web sparse-checkout init --no-cone
git -C sources/web sparse-checkout set --no-cone /web/

printf 'Mattermost server: %s\n' "$(git -C sources/mattermost rev-parse HEAD)"
printf 'YourOwn.Chat web:  %s\n' "$(git -C sources/web rev-parse HEAD)"
