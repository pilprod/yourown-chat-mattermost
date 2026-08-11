#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

source_set=${1:-all}

case "$source_set" in
    all|mattermost|web) ;;
    *)
        printf 'usage: %s [all|mattermost|web]\n' "$0" >&2
        exit 2
        ;;
esac

git submodule sync --recursive

if [ "$source_set" = all ] || [ "$source_set" = mattermost ]; then
    git submodule update --init --depth 1 --filter=blob:none sources/mattermost

    # Materialize only the server files consumed by the image assembly.
    git -C sources/mattermost sparse-checkout init --no-cone
    git -C sources/mattermost sparse-checkout set --no-cone \
        /server/ \
        /LICENSE.txt \
        /NOTICE.txt \
        /PRODUCT-NOTICE.md

    printf 'Mattermost server: %s\n' "$(git -C sources/mattermost rev-parse HEAD)"
fi

if [ "$source_set" = all ] || [ "$source_set" = web ]; then
    git submodule update --init --depth 1 --filter=blob:none sources/web

    # Materialize only the web tree consumed by the image assembly.
    git -C sources/web sparse-checkout init --no-cone
    git -C sources/web sparse-checkout set --no-cone /web/

    printf 'YourOwn.Chat web:  %s\n' "$(git -C sources/web rev-parse HEAD)"
fi
