#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

source_set=${1:-all}

case "$source_set" in
    all|server|web) ;;
    *)
        printf 'usage: %s [all|server|web]\n' "$0" >&2
        exit 2
        ;;
esac

git submodule sync --recursive
mkdir -p sources

assert_release_tag() {
    repository=$1
    release_tag=$2

    [ -n "${SOURCE_VERSION:-}" ] || return 0

    git -C "$repository" fetch --depth 1 origin \
        "refs/tags/$release_tag:refs/tags/$release_tag"
    source_head=$(git -C "$repository" rev-parse HEAD)
    tag_head=$(git -C "$repository" rev-list -n 1 "$release_tag")
    [ "$source_head" = "$tag_head" ] || {
        echo "Pinned source $source_head does not match $release_tag ($tag_head)" >&2
        exit 1
    }
}

replace_export() {
    export_dir=$1
    staging_dir=$2

    case "$export_dir" in
        "$repo_root/sources/server"|"$repo_root/sources/web") ;;
        *)
            echo "Refusing to replace unexpected export directory: $export_dir" >&2
            exit 1
            ;;
    esac

    rm -rf -- "$export_dir"
    mv "$staging_dir" "$export_dir"
}

if [ "$source_set" = all ] || [ "$source_set" = server ]; then
    git submodule update --init --depth 1 --filter=blob:none .sources/mattermost
    assert_release_tag .sources/mattermost "v${SOURCE_VERSION:-}-patched"

    git -C .sources/mattermost sparse-checkout init --no-cone
    git -C .sources/mattermost sparse-checkout set --no-cone \
        /server/ \
        /LICENSE.txt \
        /NOTICE.txt \
        /PRODUCT-NOTICE.md

    server_export=$(mktemp -d "$repo_root/.source-export.server.XXXXXX")
    git -C .sources/mattermost archive HEAD:server | tar -xf - -C "$server_export"
    git -C .sources/mattermost archive HEAD LICENSE.txt NOTICE.txt PRODUCT-NOTICE.md | \
        tar -xf - -C "$server_export"
    replace_export "$repo_root/sources/server" "$server_export"

    printf 'Mattermost server: %s\n' "$(git -C .sources/mattermost rev-parse HEAD)"
fi

if [ "$source_set" = all ] || [ "$source_set" = web ]; then
    git submodule update --init --depth 1 --filter=blob:none .sources/web
    assert_release_tag .sources/web "${SOURCE_VERSION:-}"

    git -C .sources/web sparse-checkout init --no-cone
    git -C .sources/web sparse-checkout set --no-cone /web/

    web_export=$(mktemp -d "$repo_root/.source-export.web.XXXXXX")
    git -C .sources/web archive HEAD:web | tar -xf - -C "$web_export"
    replace_export "$repo_root/sources/web" "$web_export"

    printf 'YourOwn.Chat web:  %s\n' "$(git -C .sources/web rev-parse HEAD)"
fi
