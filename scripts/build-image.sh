#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

test -f sources/server/go.mod || {
    echo "Sources are not initialized. Run ./scripts/init-sources.sh first." >&2
    exit 1
}
test -f sources/web/package.json || {
    echo "Web source is not initialized. Run ./scripts/init-sources.sh first." >&2
    exit 1
}

server_sha=$(git -C .sources/mattermost rev-parse HEAD)
web_sha=$(git -C .sources/web rev-parse HEAD)
assembly_sha=$(git rev-parse HEAD)
build_date=${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}
build_number=${BUILD_NUMBER:-$(git describe --tags --always --dirty 2>/dev/null || printf 'dev')}
image=${IMAGE:-yourown-chat-mattermost:latest}

printf '%s\n' "$server_sha" | grep -Eq '^[0-9a-f]{40}$' || {
    echo "Mattermost submodule is not pinned to a full commit SHA." >&2
    exit 1
}
printf '%s\n' "$web_sha" | grep -Eq '^[0-9a-f]{40}$' || {
    echo "Web submodule is not pinned to a full commit SHA." >&2
    exit 1
}
printf '%s\n' "$assembly_sha" | grep -Eq '^[0-9a-f]{40}$' || {
    echo "Assembly source is not pinned to a full commit SHA." >&2
    exit 1
}

docker build \
    --build-arg "BUILD_NUMBER=$build_number" \
    --build-arg "BUILD_HASH=$server_sha" \
    --build-arg "BUILD_DATE=$build_date" \
    --build-arg "SOURCE_URL=https://github.com/pilprod/mattermost/tree/$server_sha" \
    --build-arg "WEB_BUILD_HASH=$web_sha" \
    --build-arg "WEB_SOURCE_URL=https://github.com/pilprod/yourown-chat-web/tree/$web_sha" \
    --build-arg "ASSEMBLY_BUILD_HASH=$assembly_sha" \
    --build-arg "ASSEMBLY_SOURCE_URL=https://github.com/pilprod/yourown-chat-mattermost/tree/$assembly_sha" \
    --tag "$image" \
    "$@" \
    .
