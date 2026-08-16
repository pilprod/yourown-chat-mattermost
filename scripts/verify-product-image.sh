#!/bin/sh
set -eu

if [ "$#" -ne 8 ]; then
    echo "usage: $0 IMAGE VERSION SERVER_SHA SERVER_URL WEB_SHA WEB_URL ASSEMBLY_SHA ASSEMBLY_URL" >&2
    exit 2
fi

image=$1
version=$2
server_sha=$3
server_url=$4
web_sha=$5
web_url=$6
assembly_sha=$7
assembly_url=$8

for sha in "$server_sha" "$web_sha" "$assembly_sha"; do
    printf '%s\n' "$sha" | grep -Eq '^[0-9a-f]{40}$' || {
        echo "expected a full lowercase Git SHA, got: $sha" >&2
        exit 1
    }
done

label() {
    docker image inspect "$image" --format "{{ index .Config.Labels \"$1\" }}"
}

expect_label() {
    key=$1
    expected=$2
    actual=$(label "$key")
    [ "$actual" = "$expected" ] || {
        echo "label $key mismatch: expected '$expected', got '$actual'" >&2
        exit 1
    }
}

expect_label org.opencontainers.image.source "$server_url"
expect_label org.opencontainers.image.revision "$server_sha"
expect_label org.opencontainers.image.version "$version"
expect_label org.opencontainers.image.licenses AGPL-3.0-only
expect_label io.yourown.chat.server.source "$server_url"
expect_label io.yourown.chat.server.revision "$server_sha"
expect_label io.yourown.chat.web.source "$web_url"
expect_label io.yourown.chat.web.revision "$web_sha"
expect_label io.yourown.chat.assembly.source "$assembly_url"
expect_label io.yourown.chat.assembly.revision "$assembly_sha"

created=$(label org.opencontainers.image.created)
[ -n "$created" ] || { echo "image creation timestamp is missing" >&2; exit 1; }

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
container=$(docker create "$image")
trap 'docker rm -f "$container" >/dev/null 2>&1 || true; rm -rf "$tmp_dir"' EXIT HUP INT TERM
docker cp "$container:/mattermost/bin/mattermost" "$tmp_dir/mattermost"
docker cp "$container:/mattermost/licenses" "$tmp_dir/licenses"
# Copy to a tar stream: extracting with docker cp normalizes ownership to the
# invoking Cloud Build user, while the archive header retains image UID/GID.
docker cp "$container:/mattermost/client/plugins" - > "$tmp_dir/client-plugins.tar"
docker rm "$container" >/dev/null
container=

version_output=$($tmp_dir/mattermost version)
printf '%s\n' "$version_output" | grep -F "Build Number: $version" >/dev/null
printf '%s\n' "$version_output" | grep -F "Build Hash: $server_sha" >/dev/null
printf '%s\n' "$version_output" | grep -F "Build Enterprise Ready: false" >/dev/null

test -s "$tmp_dir/licenses/LICENSE.txt"
test -s "$tmp_dir/licenses/NOTICE.txt"
test -s "$tmp_dir/licenses/PRODUCT-NOTICE.md"
grep -F "GNU Affero General Public License" "$tmp_dir/licenses/LICENSE.txt" >/dev/null
grep -F "YourOwn.Chat Server modification notice" "$tmp_dir/licenses/PRODUCT-NOTICE.md" >/dev/null

plugin_dir_metadata=$(tar --numeric-owner -tvf "$tmp_dir/client-plugins.tar" | sed -n '1p')
printf '%s\n' "$plugin_dir_metadata" \
    | grep -Eq '^drwxr-xr-x[[:space:]]+2000/2000[[:space:]]' || {
    echo "plugin webapp directory metadata mismatch: expected mode 755 and owner 2000:2000, got: $plugin_dir_metadata" >&2
    exit 1
}

echo "verified $image: server=$server_sha web=$web_sha assembly=$assembly_sha"
