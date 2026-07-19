#!/usr/bin/env bash
set -euo pipefail

release_tag=${1:?release tag is required}
release_sha=${2:?release commit SHA is required}
archive=${3:?release archive is required}
sums=${4:?checksum file is required}
archive_name=${archive##*/}
sums_name=${sums##*/}

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

ensure_tag_ref() {
  local expected_commit=$1 current_commit
  if current_commit=$(resolve_tag_commit); then
    test "$current_commit" = "$expected_commit"
    return 0
  fi
  jq -n --arg ref "refs/tags/$release_tag" --arg sha "$expected_commit" \
    '{ref:$ref,sha:$sha}' > "$workdir/create-ref.json"
  api_call "$workdir/created-ref.json" 201 --request POST \
    --header 'Content-Type: application/json' --data-binary "@$workdir/create-ref.json" \
    "$api_url/repos/$GITHUB_REPOSITORY/git/refs"
  current_commit=$(resolve_tag_commit)
  test "$current_commit" = "$expected_commit"
}

api_call "$workdir/releases.json" 200 \
  "$api_url/repos/$GITHUB_REPOSITORY/releases?per_page=100"
release_id=$(jq -r --arg tag "$release_tag" \
  '[.[] | select(.tag_name == $tag)][0].id // empty' "$workdir/releases.json")
release_draft=$(jq -r --arg tag "$release_tag" \
  '[.[] | select(.tag_name == $tag)][0].draft // empty' "$workdir/releases.json")
release_target=$(jq -r --arg tag "$release_tag" \
  '[.[] | select(.tag_name == $tag)][0].target_commitish // empty' "$workdir/releases.json")

# GitHub names a published draft "untagged-*" when no tag ref existed. Recover
# only a uniquely reproducible Release whose version, target and both asset
# digests match the deterministic files for that historical main commit.
recovery_id=
recovery_target=
untagged_seen=0
while IFS=$'\t' read -r candidate_id candidate_tag candidate_target archive_digest sums_digest; do
  [ -n "$candidate_id" ] || continue
  ((untagged_seen += 1))
  [[ "$candidate_tag" == untagged-* ]] || continue
  [[ "$candidate_target" =~ ^[0-9a-f]{40}$ ]] || continue
  [ -n "$archive_digest" ] && [ -n "$sums_digest" ] || continue
  git merge-base --is-ancestor "$candidate_target" refs/remotes/origin/main || continue
  test "$(git show "${candidate_target}:RELEASE_VERSION" | tr -d '\r\n[:space:]')" = "$release_tag" || continue
  candidate_dir="$workdir/recovery-$candidate_id"
  mkdir "$candidate_dir"
  git archive --format=tar --prefix="sing-box-yg-${release_tag}/" "$candidate_target" | \
    gzip -n > "$candidate_dir/$archive_name"
  (cd "$candidate_dir" && sha256sum "$archive_name" > "$sums_name")
  test "$archive_digest" = "sha256:$(sha256sum "$candidate_dir/$archive_name" | awk '{print $1}')" || continue
  test "$sums_digest" = "sha256:$(sha256sum "$candidate_dir/$sums_name" | awk '{print $1}')" || continue
  if [ -n "$recovery_id" ]; then
    echo "multiple reproducible untagged Releases match $release_tag" >&2
    exit 1
  fi
  recovery_id=$candidate_id
  recovery_target=$candidate_target
done < <(jq -r --arg archive "$archive_name" --arg sums "$sums_name" '
  .[] | select(.draft == false and (.tag_name | startswith("untagged-"))) |
  [(.id | tostring), .tag_name, .target_commitish,
   ([.assets[] | select(.name == $archive) | .digest][0] // ""),
   ([.assets[] | select(.name == $sums) | .digest][0] // "")] | @tsv
' "$workdir/releases.json")

if [ -z "$release_id" ] && [ -n "$recovery_id" ]; then
  ensure_tag_ref "$recovery_target"
  jq -n --arg tag "$release_tag" --arg sha "$recovery_target" \
    '{tag_name:$tag,target_commitish:$sha}' > "$workdir/recover-release.json"
  api_call "$workdir/recovered-release.json" 200 --request PATCH \
    --header 'Content-Type: application/json' --data-binary "@$workdir/recover-release.json" \
    "$api_url/repos/$GITHUB_REPOSITORY/releases/$recovery_id"
  test "$(jq -r '.tag_name' "$workdir/recovered-release.json")" = "$release_tag"
  test "$(jq -r '.draft' "$workdir/recovered-release.json")" = false
  test "$(resolve_tag_commit)" = "$recovery_target"
  echo "Recovered reproducible Release $release_tag at $recovery_target"
  exit 0
fi
if [ -z "$release_id" ] && ((untagged_seen > 0)); then
  echo "unverified untagged Release exists; refusing to create a duplicate" >&2
  exit 1
fi

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
  if [ -n "$existing_commit" ]; then
    test "$existing_commit" = "$release_sha"
  elif [ "$release_target" != "$release_sha" ]; then
    jq -n --arg sha "$release_sha" '{target_commitish:$sha}' > "$workdir/retarget.json"
    api_call "$workdir/retargeted.json" 200 --request PATCH \
      --header 'Content-Type: application/json' --data-binary "@$workdir/retarget.json" \
      "$api_url/repos/$GITHUB_REPOSITORY/releases/$release_id"
  fi
elif [ -n "$existing_commit" ]; then
  test "$existing_commit" = "$release_sha"
fi

if [ -n "$release_id" ]; then
  echo "Resuming draft Release $release_tag"
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
  echo "Creating draft Release $release_tag at $release_sha"
  jq -n --arg tag "$release_tag" --arg sha "$release_sha" \
    '{tag_name:$tag,target_commitish:$sha,name:$tag,draft:true,prerelease:false,generate_release_notes:true}' \
    > "$workdir/create.json"
  api_call "$workdir/release.json" 201 --request POST \
    --header 'Content-Type: application/json' --data-binary "@$workdir/create.json" \
    "$api_url/repos/$GITHUB_REPOSITORY/releases"
  release_id=$(jq -er '.id' "$workdir/release.json")
fi

ensure_tag_ref "$release_sha"

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

echo "Publishing Release $release_tag"
printf '{"draft":false}\n' > "$workdir/publish.json"
api_call "$workdir/published.json" 200 --request PATCH \
  --header 'Content-Type: application/json' --data-binary "@$workdir/publish.json" \
  "$api_url/repos/$GITHUB_REPOSITORY/releases/$release_id"
test "$(jq -r '.draft' "$workdir/published.json")" = false
existing_commit=$(resolve_tag_commit)
test "$existing_commit" = "$release_sha"
jq -r '.html_url' "$workdir/published.json"
