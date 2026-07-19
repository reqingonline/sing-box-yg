#!/usr/bin/env bash
set -euo pipefail

release_tag=${1:?release tag is required}
release_sha=${2:?release commit SHA is required}
archive=${3:?release archive is required}
sums=${4:?checksum file is required}

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

api_url=${GITHUB_API_URL:-https://api.github.com}
upload_url=${GITHUB_UPLOAD_URL:-https://uploads.github.com}

[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$release_sha" =~ ^[0-9a-f]{40}$ ]]
test -f "$archive"
test -f "$sums"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
umask 077
API_STATUS=

api_call() {
  local output=$1 expected=$2 status
  shift 2
  if ! status=$(
    curl --config - --output "$output" --write-out '%{http_code}' "$@" <<EOF
silent
show-error
header = "Accept: application/vnd.github+json"
header = "Authorization: Bearer $GH_TOKEN"
header = "X-GitHub-Api-Version: 2022-11-28"
EOF
  ); then
    echo 'GitHub API transport failure' >&2
    return 1
  fi
  API_STATUS=$status
  case ",$expected," in
    *,"$status",*) return 0 ;;
  esac
  echo "GitHub API request failed (HTTP $status)" >&2
  jq -c '{message,errors,documentation_url}' "$output" >&2 || \
    echo 'GitHub API returned a non-JSON error body' >&2
  return 1
}

resolve_tag_commit() {
  local ref_sha
  api_call "$workdir/tag-ref.json" '200,404' \
    "$api_url/repos/$GITHUB_REPOSITORY/git/ref/tags/$release_tag"
  test "$API_STATUS" = 200 || return 1
  ref_sha=$(jq -er '.object.sha' "$workdir/tag-ref.json")
  api_call "$workdir/tag-object.json" '200,404' \
    "$api_url/repos/$GITHUB_REPOSITORY/git/tags/$ref_sha"
  if [ "$API_STATUS" = 200 ]; then
    jq -er '.object.sha' "$workdir/tag-object.json"
  else
    printf '%s\n' "$ref_sha"
  fi
}

api_call "$workdir/releases.json" 200 \
  "$api_url/repos/$GITHUB_REPOSITORY/releases?per_page=100"
release_id=$(jq -r --arg tag "$release_tag" \
  '[.[] | select(.tag_name == $tag)][0].id // empty' "$workdir/releases.json")
release_draft=$(jq -r --arg tag "$release_tag" \
  '[.[] | select(.tag_name == $tag)][0].draft // empty' "$workdir/releases.json")

existing_commit=
if existing_commit=$(resolve_tag_commit); then
  :
fi

if [ -n "$release_id" ] && [ "$release_draft" = false ]; then
  test -n "$existing_commit"
  test "$(git show "$existing_commit:RELEASE_VERSION" | tr -d '\r\n[:space:]')" = "$release_tag"
  for asset in "${archive##*/}" "${sums##*/}"; do
    jq -e --arg asset "$asset" --arg tag "$release_tag" \
      '[.[] | select(.tag_name == $tag)][0].assets | any(.name == $asset)' \
      "$workdir/releases.json" >/dev/null
  done
  echo "Release $release_tag is already published with verified asset names"
  exit 0
fi

if [ -n "$release_id" ]; then
  test "$release_draft" = true
  test -n "$existing_commit"
  test "$existing_commit" = "$release_sha"
elif [ -n "$existing_commit" ]; then
  test "$existing_commit" = "$release_sha"
fi

archive_name=${archive##*/}
sums_name=${sums##*/}

if [ -n "$release_id" ]; then
  jq -e --arg archive "$archive_name" --arg sums "$sums_name" --arg tag "$release_tag" \
    'all(.[] | select(.tag_name == $tag) | .assets[]; .name == $archive or .name == $sums)' \
    "$workdir/releases.json" >/dev/null
  while IFS= read -r asset_id; do
    [ -n "$asset_id" ] || continue
    api_call "$workdir/delete-$asset_id.json" 204 --request DELETE \
      "$api_url/repos/$GITHUB_REPOSITORY/releases/assets/$asset_id"
  done < <(jq -r --arg tag "$release_tag" --arg archive "$archive_name" --arg sums "$sums_name" \
    '.[] | select(.tag_name == $tag) | .assets[] | select(.name == $archive or .name == $sums) | .id' \
    "$workdir/releases.json")
else
  jq -n --arg tag "$release_tag" --arg sha "$release_sha" \
    '{tag_name:$tag,target_commitish:$sha,name:$tag,draft:true,prerelease:false,generate_release_notes:true}' \
    > "$workdir/create.json"
  api_call "$workdir/release.json" 201 --request POST \
    --header 'Content-Type: application/json' --data-binary "@$workdir/create.json" \
    "$api_url/repos/$GITHUB_REPOSITORY/releases"
  release_id=$(jq -er '.id' "$workdir/release.json")
  existing_commit=$(resolve_tag_commit)
  test "$existing_commit" = "$release_sha"
fi

upload_asset() {
  local file=$1 media_type=$2 name digest
  name=${file##*/}
  api_call "$workdir/upload-$name.json" 201 --request POST \
    --header "Content-Type: $media_type" --data-binary "@$file" \
    "$upload_url/repos/$GITHUB_REPOSITORY/releases/$release_id/assets?name=$name"
  digest=$(jq -r '.digest // empty' "$workdir/upload-$name.json")
  if [ -n "$digest" ]; then
    test "$digest" = "sha256:$(sha256sum "$file" | awk '{print $1}')"
  fi
}

upload_asset "$archive" application/gzip
upload_asset "$sums" text/plain

printf '{"draft":false}\n' > "$workdir/publish.json"
api_call "$workdir/published.json" 200 --request PATCH \
  --header 'Content-Type: application/json' --data-binary "@$workdir/publish.json" \
  "$api_url/repos/$GITHUB_REPOSITORY/releases/$release_id"
test "$(jq -r '.draft' "$workdir/published.json")" = false
jq -r '.html_url' "$workdir/published.json"
