# Sing-box-yg Comprehensive Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a self-owned, transaction-safe sing-box installer that preserves unrelated VPS and Serv00 state, protects credentials, passes real compatibility tests, and is released from `reqingonline/sing-box-yg`.

**Architecture:** Keep the existing interactive entry scripts, but move dangerous system operations into focused Bash modules with explicit return values and mockable command boundaries. Every configuration or binary change becomes a locked transaction with preflight validation, post-start health checks, and automatic rollback; repository releases become the only production update source.

**Tech Stack:** Bash 4+, jq, curl, sha256sum, flock, systemd/OpenRC, iptables/ip6tables, BusyBox, Docker, GitHub Actions, ShellCheck.

---

## File map

- `lib/source.sh`: repository identity, channels, semantic version helpers, Release URLs.
- `lib/download.sh`: HTTPS download, checksum verification, candidate installation, global lock.
- `lib/secrets.sh`: secure defaults, file permissions, redaction, secret storage.
- `lib/transaction.sh`: config/binary snapshots, candidate validation, restart verification, rollback.
- `lib/firewall.sh`: project-owned IPv4/IPv6 NAT chains and exact cleanup.
- `lib/service.sh`: systemd/OpenRC definitions, health checks, service status abstraction.
- `lib/subscription.sh`: loopback subscription service and token management.
- `lib/cleanup.sh`: asset manifest, path boundary validation, exact uninstall.
- `scripts/install.sh`: verified stable/fixed-tag bootstrap installer.
- `scripts/release-checks.sh`: release preflight and artifact checksums.
- `scripts/sb-doctor.sh`: redacted operational diagnosis.
- `sb.sh`: existing VPS menu adapted to the modules.
- `serv00.sh`, `serv00keep.sh`, `kp.sh`: Serv00 flows adapted to safe cleanup, source, and secret APIs.
- `tests/unit/`: isolated module tests with command mocks.
- `tests/integration/`: container install and uninstall smoke tests.
- `tests/vps/`: destructive-test-VPS baseline, failure injection, and acceptance scripts.
- `.github/workflows/test.yml`: least-privilege CI and distribution matrix.
- `.github/workflows/release.yml`: tag-only source archive and checksum release.
- `README.md`: stable install, pinned install, migration, firewall, rollback, and security notes.

## Task 1: Establish repository identity and verified download primitives

**Files:**
- Create: `lib/source.sh`
- Create: `lib/download.sh`
- Create: `lib/secrets.sh`
- Create: `tests/unit/test_source_download.sh`
- Modify: `tests/run.sh`

- [ ] **Step 1: Write the failing source and download test**

Create `tests/unit/test_source_download.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
source "$repo_root/lib/source.sh"
source "$repo_root/lib/download.sh"
source "$repo_root/lib/secrets.sh"
test "$SBYG_REPOSITORY" = "reqingonline/sing-box-yg"
test "$(sbyg_raw_url main sb.sh)" = "https://raw.githubusercontent.com/reqingonline/sing-box-yg/main/sb.sh"
if sbyg_require_https 'http://example.invalid/file'; then exit 1; fi
printf old > "$tmpdir/current"
printf candidate > "$tmpdir/candidate"
printf '%064d  candidate\n' 0 > "$tmpdir/checksums.txt"
if sbyg_verify_checksum "$tmpdir/candidate" "$tmpdir/checksums.txt"; then exit 1; fi
grep -Fx old "$tmpdir/current"
digest=$(sha256sum "$tmpdir/candidate" | awk '{print $1}')
printf '%s  candidate\n' "$digest" > "$tmpdir/checksums.txt"
sbyg_verify_checksum "$tmpdir/candidate" "$tmpdir/checksums.txt"
sbyg_atomic_install "$tmpdir/candidate" "$tmpdir/current" 700
grep -Fx candidate "$tmpdir/current"
test "$(sbyg_redact 'abcdefghijklmnop')" = 'abcd…mnop'
```

- [ ] **Step 2: Run the new test and confirm it fails**

Run `bash tests/unit/test_source_download.sh`.

Expected: failure because the three library files do not exist.

- [ ] **Step 3: Implement repository and version helpers**

Create `lib/source.sh`:

```bash
#!/usr/bin/env bash
SBYG_REPOSITORY=${SBYG_REPOSITORY:-reqingonline/sing-box-yg}
SBYG_CHANNEL=${SBYG_CHANNEL:-stable}
SBYG_GITHUB_API=${SBYG_GITHUB_API:-https://api.github.com}
sbyg_raw_url() {
  local ref=$1 path=$2
  printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$SBYG_REPOSITORY" "$ref" "$path"
}
sbyg_release_api_url() {
  case ${1:-$SBYG_CHANNEL} in
    stable) printf '%s/repos/%s/releases/latest\n' "$SBYG_GITHUB_API" "$SBYG_REPOSITORY" ;;
    v[0-9]*) printf '%s/repos/%s/releases/tags/%s\n' "$SBYG_GITHUB_API" "$SBYG_REPOSITORY" "$1" ;;
    *) return 2 ;;
  esac
}
sbyg_semver_ge() {
  local current=${1#v} required=${2#v}
  test "$(printf '%s\n%s\n' "$required" "$current" | sort -V | tail -n1)" = "$current"
}
```

- [ ] **Step 4: Implement download and atomic install helpers**

Create `lib/download.sh`:

```bash
#!/usr/bin/env bash
sbyg_require_https() { case $1 in https://*) return 0 ;; *) return 1 ;; esac; }
sbyg_download() {
  local url=$1 destination=$2
  sbyg_require_https "$url" || return 2
  curl --fail --show-error --silent --location --retry 2 \
    --connect-timeout 10 --max-time 300 --proto '=https' \
    --output "$destination" "$url" || return 1
  test -s "$destination"
}
sbyg_verify_checksum() {
  local file=$1 manifest=$2 name expected actual
  name=$(basename "$file")
  expected=$(awk -v name="$name" '$2 == name || $2 == "*" name {print $1; exit}' "$manifest")
  test "$expected" || return 1
  actual=$(sha256sum "$file" | awk '{print $1}')
  test "$actual" = "$expected"
}
sbyg_atomic_install() {
  local source=$1 destination=$2 mode=${3:-755} candidate
  test -s "$source" || return 1
  candidate=$(mktemp "$(dirname "$destination")/.sbyg-install.XXXXXX") || return 1
  install -m "$mode" "$source" "$candidate" || { rm -f "$candidate"; return 1; }
  mv -f "$candidate" "$destination"
}
sbyg_with_lock() {
  local lock=${SBYG_LOCK_FILE:-/run/lock/sing-box-yg.lock}
  mkdir -p "$(dirname "$lock")" || return 1
  exec 9>"$lock" || return 1
  flock -n 9 || return 75
  "$@"
}
```

- [ ] **Step 5: Implement secret defaults and redaction**

Create `lib/secrets.sh`:

```bash
#!/usr/bin/env bash
sbyg_secure_defaults() { umask 077; }
sbyg_secure_dir() { install -d -m 700 "$1"; }
sbyg_secure_file() { test -e "$1" && chmod 600 "$1"; }
sbyg_redact() {
  local value=$1 length=${#1}
  if (( length <= 8 )); then printf '%*s\n' "$length" '' | tr ' ' '*';
  else printf '%s…%s\n' "${value:0:4}" "${value:length-4:4}"; fi
}
```

- [ ] **Step 6: Include unit tests in the runner and verify**

Change `tests/run.sh`:

```bash
for test_file in "$repo_root"/tests/test_*.sh "$repo_root"/tests/unit/test_*.sh; do
  test -e "$test_file" || continue
  bash "$test_file"
done
```

Run `bash -n lib/*.sh tests/unit/*.sh && bash tests/run.sh`.

Expected: all tests pass.

- [ ] **Step 7: Commit the primitives**

```bash
git add lib/source.sh lib/download.sh lib/secrets.sh tests/run.sh tests/unit/test_source_download.sh
git commit -m "feat: add owned verified download primitives"
```

## Task 2: Make service changes transactional and rollback-safe

**Files:**
- Create: `lib/transaction.sh`
- Create: `tests/unit/test_transaction.sh`
- Modify: `sb.sh:3944-3982`
- Modify: `tests/test_service_lifecycle.sh`

- [ ] **Step 1: Write failure-injection tests**

Create `tests/unit/test_transaction.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
source "$repo_root/lib/transaction.sh"
printf old-config > "$tmpdir/config"
printf old-core > "$tmpdir/core"
chmod +x "$tmpdir/core"
sbyg_transaction_begin "$tmpdir/state" "$tmpdir/config" "$tmpdir/core"
printf new-config > "$tmpdir/config"
printf new-core > "$tmpdir/core"
chmod +x "$tmpdir/core"
sbyg_validate_config() { return 0; }
sbyg_service_restart() { return 1; }
sbyg_service_active() { return 1; }
if sbyg_transaction_apply "$tmpdir/state" "$tmpdir/config" "$tmpdir/core"; then exit 1; fi
grep -Fx old-config "$tmpdir/config"
grep -Fx old-core "$tmpdir/core"
test ! -e "$tmpdir/state/committed"
```

- [ ] **Step 2: Confirm the transaction test fails**

Run `bash tests/unit/test_transaction.sh`.

Expected: failure because transaction functions do not exist.

- [ ] **Step 3: Implement snapshot, apply, and rollback**

Create `lib/transaction.sh`:

```bash
#!/usr/bin/env bash
sbyg_transaction_begin() {
  local state=$1 config=$2 core=$3
  install -d -m 700 "$state" || return 1
  install -m 600 "$config" "$state/config.previous" || return 1
  install -m 755 "$core" "$state/core.previous" || return 1
  rm -f "$state/committed"
}
sbyg_transaction_rollback() {
  local state=$1 config=$2 core=$3
  install -m 600 "$state/config.previous" "$config" || return 1
  install -m 755 "$state/core.previous" "$core" || return 1
  sbyg_service_restart && sbyg_service_active
}
sbyg_transaction_apply() {
  local state=$1 config=$2 core=$3
  if ! sbyg_validate_config "$core" "$config"; then
    sbyg_transaction_rollback "$state" "$config" "$core" >/dev/null 2>&1 || true
    return 1
  fi
  if ! sbyg_service_restart || ! sbyg_service_active || ! sbyg_expected_ports_listening "$config"; then
    sbyg_transaction_rollback "$state" "$config" "$core" || return 2
    return 1
  fi
  : > "$state/committed"
}
sbyg_validate_config() { "$1" check -c "$2"; }
sbyg_service_restart() { systemctl restart sing-box; }
sbyg_service_active() { systemctl is-active --quiet sing-box; }
sbyg_expected_ports_listening() {
  local config=$1 port
  while read -r port; do
    ss -H -lntup | grep -Eq "[:.]${port}[[:space:]]" || return 1
  done < <(jq -r '.inbounds[].listen_port' "$config")
}
```

- [ ] **Step 4: Replace `restartsb` with checked transaction calls**

Source `lib/transaction.sh` from `sb.sh`. Preserve OpenRC by overriding service adapters when `apk` exists. Check every return value and call `snapshot_config` only after validation, restart, active-state, and listener checks succeed.

- [ ] **Step 5: Extend the legacy lifecycle test**

Make the systemctl mock fail independently for `restart` and `is-active`; assert `restartsb` returns non-zero and never calls `snapshot_config` in either case.

- [ ] **Step 6: Run lifecycle and transaction tests**

Run `bash tests/unit/test_transaction.sh && bash tests/test_service_lifecycle.sh && bash tests/run.sh`.

Expected: all pass and both post-restart failure paths restore the prior files.

- [ ] **Step 7: Commit transactional service changes**

```bash
git add lib/transaction.sh sb.sh tests/unit/test_transaction.sh tests/test_service_lifecycle.sh
git commit -m "fix: rollback failed service and core changes"
```

## Task 3: Isolate all port-forwarding firewall rules

**Files:**
- Create: `lib/firewall.sh`
- Create: `tests/unit/test_firewall_chain.sh`
- Modify: `sb.sh:189-220`
- Modify: `sb.sh:2833-2901`
- Modify: `sb.sh:4103-4125`

- [ ] **Step 1: Write a command-log firewall test**

Mock `iptables` and `ip6tables`, then assert owned-chain creation and absence of global mutation:

```bash
grep -Fx -- '-t nat -N SBYG_PREROUTING' "$log"
grep -F -- '-t nat -A SBYG_PREROUTING -p udp --dport 20000:20100' "$log"
if grep -E -- '-F (PREROUTING|INPUT)|-P INPUT ACCEPT|-t mangle -F' "$log"; then exit 1; fi
```

- [ ] **Step 2: Confirm the firewall test fails**

Run `bash tests/unit/test_firewall_chain.sh`.

Expected: failure because the module does not exist and current uninstall flushes `PREROUTING`.

- [ ] **Step 3: Implement the owned chain API**

Create `lib/firewall.sh`:

```bash
#!/usr/bin/env bash
SBYG_NAT_CHAIN=SBYG_PREROUTING
sbyg_fw_ensure_chain_one() {
  local bin=$1
  "$bin" -w -t nat -N "$SBYG_NAT_CHAIN" 2>/dev/null || true
  "$bin" -w -t nat -C PREROUTING -m comment --comment sing-box-yg -j "$SBYG_NAT_CHAIN" 2>/dev/null ||
    "$bin" -w -t nat -A PREROUTING -m comment --comment sing-box-yg -j "$SBYG_NAT_CHAIN"
}
sbyg_fw_add_udp_dnat_one() {
  local bin=$1 source_ports=$2 target_port=$3
  "$bin" -w -t nat -C "$SBYG_NAT_CHAIN" -p udp --dport "$source_ports" \
    -m comment --comment sing-box-yg -j DNAT --to-destination ":$target_port" 2>/dev/null ||
  "$bin" -w -t nat -A "$SBYG_NAT_CHAIN" -p udp --dport "$source_ports" \
    -m comment --comment sing-box-yg -j DNAT --to-destination ":$target_port"
}
sbyg_fw_remove_all_one() {
  local bin=$1
  while "$bin" -w -t nat -C PREROUTING -m comment --comment sing-box-yg -j "$SBYG_NAT_CHAIN" 2>/dev/null; do
    "$bin" -w -t nat -D PREROUTING -m comment --comment sing-box-yg -j "$SBYG_NAT_CHAIN" || return 1
  done
  "$bin" -w -t nat -F "$SBYG_NAT_CHAIN" 2>/dev/null || true
  "$bin" -w -t nat -X "$SBYG_NAT_CHAIN" 2>/dev/null || true
}
```

Public wrappers call IPv4 and IPv6 binaries when installed.

- [ ] **Step 4: Remove global firewall mutation**

Delete the implementation that disables UFW/firewalld, changes policies, or flushes filter/mangle chains. Replace port-hop append/delete code with owned-chain functions.

- [ ] **Step 5: Make uninstall remove only the owned chain**

Replace `iptables -t nat -F PREROUTING` with `sbyg_fw_remove_all` and report any exact-cleanup failure.

- [ ] **Step 6: Run firewall tests**

Run `bash tests/unit/test_firewall_chain.sh && bash tests/test_firewall_prompt.sh && bash tests/run.sh`.

Expected: no global flush or policy-reset command appears.

- [ ] **Step 7: Commit firewall isolation**

```bash
git add lib/firewall.sh sb.sh tests/unit/test_firewall_chain.sh tests/test_firewall_prompt.sh
git commit -m "fix: isolate node forwarding firewall rules"
```

## Task 4: Protect credentials and subscription delivery

**Files:**
- Create: `lib/subscription.sh`
- Create: `tests/unit/test_secrets_subscription.sh`
- Modify: `sb.sh:2533-2588`
- Modify: `sb.sh:3111-3218`
- Modify: `sb.sh:3264-3342`
- Modify: `sb.sh:3385-3435`
- Modify: `sb.sh:4265-4274`

- [ ] **Step 1: Write permissions and binding tests**

Create temporary Argo, Telegram, GitLab, and subscription files. Assert mode `600`, redacted display, an independent random subscription token, and a BusyBox invocation containing `-p 127.0.0.1:18080`.

- [ ] **Step 2: Confirm the test fails**

Run `bash tests/unit/test_secrets_subscription.sh`.

Expected: current files use default modes, reuse UUID, and bind HTTP publicly.

- [ ] **Step 3: Implement subscription helpers**

Create `lib/subscription.sh`:

```bash
#!/usr/bin/env bash
sbyg_subscription_token() { openssl rand -hex 24; }
sbyg_subscription_start_loopback() {
  local root=$1 port=$2 log=${3:-/dev/null} httpd
  httpd=$(command -v busybox-extras || command -v busybox) || return 1
  "$httpd" httpd -f -p "127.0.0.1:$port" -h "$root" >"$log" 2>&1 &
  printf '%s\n' "$!"
}
sbyg_subscription_url_redacted() {
  local port=$1 token=$2
  printf 'http://127.0.0.1:%s/%s/\n' "$port" "$(sbyg_redact "$token")"
}
```

- [ ] **Step 4: Secure stored credentials**

Call `sbyg_secure_defaults` at each entry script. Store tokens in separate mode-600 files. Remove full-token menu output. Replace token-bearing Git remote URLs with a temporary mode-700 `GIT_ASKPASS` helper deleted immediately after push.

- [ ] **Step 5: Require HTTPS for public subscriptions**

Keep the local listener on loopback. Public menu output is produced only for an existing HTTPS tunnel or reverse proxy and uses an independent subscription token. Remove public `http://IP:port/token` output.

- [ ] **Step 6: Verify secrets and subscriptions**

Run `bash tests/unit/test_secrets_subscription.sh && bash tests/run.sh`.

Expected: credential files are `600`, output is redacted, and HTTP binds only to loopback.

- [ ] **Step 7: Commit credential and subscription hardening**

```bash
git add lib/subscription.sh lib/secrets.sh sb.sh tests/unit/test_secrets_subscription.sh
git commit -m "fix: protect credentials and subscription delivery"
```

## Task 5: Bound Serv00 and VPS cleanup to owned assets

**Files:**
- Create: `lib/cleanup.sh`
- Create: `tests/unit/test_cleanup_boundaries.sh`
- Modify: `serv00.sh:239-272`
- Modify: `serv00keep.sh:29-45`
- Modify: `sb.sh:4103-4125`

- [ ] **Step 1: Write destructive-boundary tests**

Create a fake home containing `.ssh/authorized_keys`, `personal.txt`, and SBYG paths recorded in `.sbyg/assets.v1`. Assert only recorded paths are removed. Assert empty, `/`, the home root, `..`, and escaping symlinks are rejected.

- [ ] **Step 2: Confirm current cleanup fails the contract**

Run `bash tests/unit/test_cleanup_boundaries.sh`.

Expected: static assertion finds `find ~ -exec rm -rf` and the library is absent.

- [ ] **Step 3: Implement asset manifest and path validation**

Create `lib/cleanup.sh`:

```bash
#!/usr/bin/env bash
sbyg_path_within() {
  local candidate=$1 root=$2 resolved_candidate resolved_root
  test "$candidate" && test "$root" || return 1
  resolved_candidate=$(realpath -m -- "$candidate") || return 1
  resolved_root=$(realpath -m -- "$root") || return 1
  test "$resolved_candidate" != "$resolved_root" || return 1
  case "$resolved_candidate/" in "$resolved_root"/*) return 0 ;; *) return 1 ;; esac
}
sbyg_manifest_add() {
  local manifest=$1 path=$2
  grep -Fx -- "$path" "$manifest" 2>/dev/null || printf '%s\n' "$path" >> "$manifest"
  chmod 600 "$manifest"
}
sbyg_cleanup_manifest() {
  local manifest=$1 root=$2 path
  test -f "$manifest" || return 0
  while IFS= read -r path; do
    sbyg_path_within "$path" "$root" || return 2
    if test -L "$path"; then rm -f -- "$path"; else rm -rf -- "$path"; fi || return 1
  done < "$manifest"
}
```

- [ ] **Step 4: Replace Serv00 home wipe and user-wide process kills**

Remove recursive home chmod/delete and `killall -9 -u`. Record project paths and PIDs during installation; clean only manifest paths and verified project PIDs. Legacy cleanup displays a fixed known-path list before deletion.

- [ ] **Step 5: Apply the manifest to VPS uninstall**

Record `/etc/s-box`, `/usr/bin/sb`, owned service/timer files, and the owned firewall chain. Move unknown `/etc/s-box` files into a timestamped recovery directory instead of deleting them.

- [ ] **Step 6: Run cleanup tests and static scan**

```bash
bash tests/unit/test_cleanup_boundaries.sh
! grep -R -nE 'find ~ .*rm -rf|killall -9 -u|iptables .* -F PREROUTING' sb.sh serv00.sh serv00keep.sh lib
bash tests/run.sh
```

Expected: pass with no broad deletion pattern.

- [ ] **Step 7: Commit bounded cleanup**

```bash
git add lib/cleanup.sh sb.sh serv00.sh serv00keep.sh tests/unit/test_cleanup_boundaries.sh
git commit -m "fix: bound uninstall to project-owned assets"
```

## Task 6: Harden service definitions and add redacted diagnostics

**Files:**
- Create: `lib/service.sh`
- Create: `scripts/sb-doctor.sh`
- Create: `tests/unit/test_service_definition.sh`
- Modify: `sb.sh:1026-1058`
- Modify: `sb.sh:4006-4025`
- Modify: `tests/vps/monitor-health.sh`
- Modify: `tests/vps/sing-box-yg-health.service`
- Modify: `tests/vps/sing-box-yg-health.timer`

- [ ] **Step 1: Write service-definition tests**

Generate a unit into a temporary path. Assert it contains `network-online.target`, `NoNewPrivileges=true`, `PrivateTmp=true`, `ProtectSystem=strict`, and `ReadWritePaths=/etc/s-box`; assert no unconditional daily restart cron remains.

- [ ] **Step 2: Confirm service tests fail**

Run `bash tests/unit/test_service_definition.sh`.

Expected: current unit lacks the hardening keys and `cronsb` writes a daily restart.

- [ ] **Step 3: Implement systemd/OpenRC rendering**

Create `lib/service.sh` with `sbyg_service_render_systemd`, `sbyg_service_render_openrc`, restart, active, and log adapters. The systemd renderer emits:

```ini
[Unit]
After=network-online.target nss-lookup.target
Wants=network-online.target
[Service]
User=root
WorkingDirectory=/etc/s-box
ExecStart=/etc/s-box/sing-box run -c /etc/s-box/sb.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/etc/s-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576
[Install]
WantedBy=multi-user.target
```

- [ ] **Step 4: Replace daily restart with health timer**

Install a 15-minute timer that runs `scripts/sb-doctor.sh --repair`. Repair restarts only when the config is valid and service inactive; invalid config triggers transaction rollback.

- [ ] **Step 5: Implement `sb doctor`**

Print OS, repository/core versions, config check, service state, listening ports, owned firewall chain, certificate expiration, and rollback status. Redact credential-shaped values and never print UUID, keys, tokens, or complete subscription URLs.

- [ ] **Step 6: Run service and doctor tests**

Run `bash tests/unit/test_service_definition.sh && bash -n scripts/sb-doctor.sh lib/service.sh && bash tests/run.sh`.

Expected: unit hardening passes and no daily restart cron remains.

- [ ] **Step 7: Commit service hardening**

```bash
git add lib/service.sh scripts/sb-doctor.sh sb.sh tests/unit/test_service_definition.sh tests/vps
git commit -m "feat: add hardened service health diagnostics"
```

## Task 7: Own every update path and add sing-box 1.14 compatibility

**Files:**
- Create: `tests/unit/test_owned_updates.sh`
- Create: `tests/unit/test_config_compatibility.sh`
- Modify: `sb.sh:1-4200`
- Modify: `serv00.sh:1-1300`
- Modify: `serv00keep.sh:1-900`
- Modify: `kp.sh`
- Delete: `SFW-(V1.13.0).zip`

- [ ] **Step 1: Write repository-ownership regression tests**

Create `tests/unit/test_owned_updates.sh` to fail when an executable script points at another owner's `raw.githubusercontent.com` URL, when `upsbyg` calls `lnsb` more than once, or when a tracked ZIP/binary lacks provenance:

```bash
#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
if grep -RInE 'raw\.githubusercontent\.com/yonggekkk/sing-box-yg' \
  "$repo_root"/{sb.sh,serv00.sh,serv00keep.sh,kp.sh,lib,scripts} 2>/dev/null; then
  echo 'upstream executable URL remains' >&2
  exit 1
fi
test "$(awk '/^upsbyg\(\)/,/^}/' "$repo_root/sb.sh" | grep -c 'lnsb')" -eq 1
if find "$repo_root" -maxdepth 2 -type f -name '*.zip' | grep -q .; then
  echo 'tracked ZIP artifacts are forbidden' >&2
  exit 1
fi
```

- [ ] **Step 2: Write configuration compatibility fixtures**

Create `tests/unit/test_config_compatibility.sh`. Render representative Reality, Hysteria2, Tuic, VMess-WS, and mixed configurations for sing-box `1.13.x` and `1.14.x`; validate them with the matching fake-core contract. For `1.14.x`, assert:

```bash
jq -e '.experimental.cache_file.enabled == true' "$config"
jq -e '.route.default_domain_resolver != null' "$config"
jq -e '.services[]? | select(.type == "resolved") | .servers | length >= 1' "$config"
! grep -q 'download_detour' "$config"
```

Where the upstream schema supports it, assert `http_clients.default_http_client` is present so the generated configuration remains forward-compatible with the 1.16 removal of legacy behavior.

- [ ] **Step 3: Confirm both regression tests fail**

Run:

```bash
bash tests/unit/test_owned_updates.sh
bash tests/unit/test_config_compatibility.sh
```

Expected: upstream URLs, duplicate `lnsb`, tracked ZIP, and missing 1.14 compatibility cause failures.

- [ ] **Step 4: Route self-update operations through `lib/source.sh`**

Source the shared libraries at each entry point. Replace hard-coded upstream fetches with `sbyg_raw_url`, `sbyg_release_asset_url`, or the verified installer. Add `--channel stable`, `--channel main`, and `--version <tag>` handling without changing existing interactive menu numbers. Stable is the default; main requires an explicit choice.

- [ ] **Step 5: Make configuration generation core-version aware**

Read the installed candidate's version before rendering. Keep one canonical JSON renderer, branch only where the schema differs, and run `sing-box check -c <candidate>` before every install. Add the 1.14 HTTP client/default resolver fields and remove fields deprecated by the selected core.

- [ ] **Step 6: Remove opaque tracked artifacts**

Delete `SFW-(V1.13.0).zip`. If `sbwpph` remains required, fetch it only from a tagged Release Asset with a checksum entry and provenance documented in `docs/SECURITY.md`; otherwise remove the feature cleanly from menus and cleanup manifests.

- [ ] **Step 7: Run ownership and compatibility tests**

Run:

```bash
bash tests/unit/test_owned_updates.sh
bash tests/unit/test_config_compatibility.sh
bash tests/run.sh
```

Expected: no executable update path references another owner, generated fixtures pass their selected schema contract, and the full suite passes.

- [ ] **Step 8: Commit owned updates**

```bash
git add sb.sh serv00.sh serv00keep.sh kp.sh lib tests
git add -u 'SFW-(V1.13.0).zip'
git commit -m "feat: own update paths and support sing-box 1.14"
```

## Task 8: Build a verified stable installer and release pipeline

**Files:**
- Create: `scripts/install.sh`
- Create: `scripts/release-checks.sh`
- Create: `tests/unit/test_installer.sh`
- Create: `.github/workflows/release.yml`
- Modify: `.github/workflows/test.yml`
- Modify: `.github/workflows/main.yml`

- [ ] **Step 1: Write installer failure-path tests**

Create a fixture Release API response, source archive, and `SHA256SUMS`. The test serves them from a local HTTP fixture overridden through `SBYG_GITHUB_API`, then checks:

1. a correct digest installs into an empty prefix;
2. a wrong digest exits non-zero;
3. a wrong digest leaves an existing installation byte-for-byte unchanged;
4. `--version vX.Y.Z` selects the named tag;
5. the default selects the latest non-prerelease Release;
6. unsupported architecture exits before any mutation.

- [ ] **Step 2: Confirm the installer test fails**

Run `bash tests/unit/test_installer.sh`.

Expected: failure because the installer and release workflow do not exist.

- [ ] **Step 3: Implement `scripts/install.sh`**

The installer must use `set -euo pipefail`, accept `--channel stable|main`, `--version`, `--prefix`, and `--dry-run`, require HTTPS outside tests, resolve a Release exactly once, download an archive plus `SHA256SUMS`, verify before extraction, run `bash -n` on every shipped shell file, and atomically replace only project-owned paths. Log the selected repository, tag, and artifact digest, but never log credentials.

- [ ] **Step 4: Implement release preflight checks**

`scripts/release-checks.sh` must:

```bash
bash -n sb.sh serv00.sh serv00keep.sh kp.sh lib/*.sh scripts/*.sh
shellcheck -x sb.sh serv00.sh serv00keep.sh kp.sh lib/*.sh scripts/*.sh
bash tests/run.sh
git diff --check
```

It also rejects untracked executables, archives without checksum entries, HTTP download URLs, curl `-k`, broad write permissions, and GitHub Actions permissions broader than `contents: read` except the tag-release job's scoped `contents: write`.

- [ ] **Step 5: Create the tag-only Release workflow**

Pin third-party Actions by full commit SHA. On `v*` tags, run preflight checks, create deterministic source archives, generate `SHA256SUMS`, verify the checksums in a fresh directory, and publish both. Do not execute repository scripts before checkout and checksum/static review.

- [ ] **Step 6: Harden existing workflows**

Give tests `contents: read`, add `timeout-minutes`, use a read-only checkout, remove `curl -sk`, and ensure generated config data is not uploaded as a public artifact. Preserve existing useful tests while moving distro execution into Task 9's real matrix.

- [ ] **Step 7: Run installer and release checks locally**

Run:

```bash
bash tests/unit/test_installer.sh
bash scripts/release-checks.sh
```

Expected: digest failures are non-destructive and the entire release preflight passes.

- [ ] **Step 8: Commit the release pipeline**

```bash
git add scripts/install.sh scripts/release-checks.sh tests/unit/test_installer.sh .github/workflows
git commit -m "feat: add verified installer and release pipeline"
```

## Task 9: Replace superficial CI with real distribution smoke tests

**Files:**
- Create: `tests/fixtures/fake-sing-box`
- Create: `tests/integration/install-smoke.sh`
- Create: `tests/integration/distro-matrix.sh`
- Modify: `tests/run.sh`
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Create a deterministic fake core**

The executable fixture implements `version`, `check -c`, and `run -c`. `check` parses JSON and fails when `.test_invalid == true`; `run` stays alive and exposes its PID until terminated. Its SHA-256 is generated during the test, never trusted from the working tree.

- [ ] **Step 2: Write an end-to-end install smoke test**

Run the installer into a temporary prefix with the fake core, render a minimal configuration, start it using the service adapter, assert health, exercise a candidate update, inject a failed candidate, verify rollback, uninstall, and assert an unrelated sentinel file remains.

- [ ] **Step 3: Confirm the smoke test exposes current mocks**

Run `bash tests/integration/install-smoke.sh`.

Expected: failure until installer, transaction, service, and cleanup adapters are wired together.

- [ ] **Step 4: Build the distro matrix**

Run the same smoke script in fresh `ubuntu:22.04`, `ubuntu:24.04`, `debian:12`, and `alpine:3.20` containers. Mount the repository read-only, give each container a separate writable temporary directory, install only declared dependencies, and fail if a distribution path only detects its package manager without completing install/check/rollback/uninstall.

- [ ] **Step 5: Add matrix jobs to CI**

Run unit tests and ShellCheck once, then the four container jobs. Upload only redacted logs after failure. Cache no generated configuration or secret file.

- [ ] **Step 6: Run all local integration checks**

Run:

```bash
bash tests/integration/install-smoke.sh
bash tests/integration/distro-matrix.sh
bash tests/run.sh
```

Expected: four distributions complete the real lifecycle and failure injection restores the previous healthy version.

- [ ] **Step 7: Commit the real matrix**

```bash
git add tests .github/workflows/test.yml
git commit -m "test: exercise real install lifecycle across distros"
```

## Task 10: Document the owned install and migration contract

**Files:**
- Create: `docs/SECURITY.md`
- Create: `docs/MIGRATION.md`
- Create: `docs/RELEASE.md`
- Modify: `README.md`

- [ ] **Step 1: Replace the primary install documentation**

Document stable and pinned installation from `reqingonline/sing-box-yg`, including the checksum-verifying bootstrap form. Mark `main` as development-only. Explain supported systems, default paths, ports, subscription exposure modes, and how to run `sb doctor`.

- [ ] **Step 2: Document security boundaries**

List project-owned files and firewall chains, permissions for secret/config files, safe token rotation, loopback-by-default subscriptions, optional authenticated public exposure, certificate assumptions, redacted logs, and the promise that uninstall does not disable the host firewall or delete unrelated home-directory content.

- [ ] **Step 3: Document migration and rollback**

Give exact commands to back up `/etc/s-box`, inspect legacy global NAT rules, migrate from upstream/self-hosted raw URLs, rotate credentials, validate configuration, perform a stable upgrade, roll back to a pinned tag, and remove only the legacy rules confirmed to belong to this project.

- [ ] **Step 4: Document contributor release synchronization**

Describe how to fetch upstream, review changes, cherry-pick or reimplement them, update compatibility fixtures, run release checks, create a signed/annotated tag, verify the draft artifacts and checksums, then publish. Do not suggest blindly merging upstream executable download URLs.

- [ ] **Step 5: Validate documentation references**

Run a link/path checker that verifies every repository-relative command and file in the four documents exists. Run the install examples with `--dry-run` against the local fixture.

- [ ] **Step 6: Commit documentation**

```bash
git add README.md docs/SECURITY.md docs/MIGRATION.md docs/RELEASE.md
git commit -m "docs: describe stable install security and migration"
```

## Task 11: Validate destructive paths on the disposable VPS

**Files:**
- Create: `tests/vps/capture-baseline.sh`
- Create: `tests/vps/release-acceptance.sh`
- Create: `tests/vps/failure-injection.sh`
- Create: `tests/vps/cleanup-verify.sh`
- Create: `tests/vps/README.md`
- Create: `tests/vps/acceptance-report.md`

- [ ] **Step 1: Capture and redact the baseline**

Record OS/kernel, architecture, free disk/RAM, service state, listening port numbers, UFW/firewalld status, and hashes of relevant configuration files. Replace public addresses, usernames, keys, UUIDs, tokens, and complete URLs with stable redaction labels before saving any report. Never commit raw command output from the host.

- [ ] **Step 2: Establish unrelated-state sentinels**

Create a harmless sentinel file under a temporary acceptance directory and a uniquely named, no-op firewall chain that is not referenced by the project. Record current SSH rule/state. These are the preservation assertions; do not flush or reset the firewall.

- [ ] **Step 3: Install the exact candidate commit**

Archive the current Git commit, calculate its digest locally, transfer it to the VPS, verify the digest remotely, and run the installer from that verified archive. Do not install from mutable `main`. Record the commit, archive digest, selected core version, and redacted configuration hash.

- [ ] **Step 4: Exercise the healthy lifecycle**

Install at least Reality and Hysteria2 test inbounds on non-SSH ports, run the real core config check, confirm the service remains active for at least 60 seconds, inspect logs for restart loops, check IPv4/IPv6 listeners, exercise one owned port-forward rule, and run `sb doctor`. Do not expose a plaintext subscription to the public interfaces.

- [ ] **Step 5: Inject transaction failures**

In separate locked transactions, try invalid JSON, a schema-valid configuration whose listener cannot bind, a bad core digest, and a truncated script download. After each failure assert the previous config/binary hashes, process PID or healthy replacement PID, service state, and subscription data are restored; no failed candidate may become the snapshot.

- [ ] **Step 6: Verify firewall and uninstall preservation**

Remove the owned forwarding rule and uninstall. Assert UFW remains enabled, the SSH rule remains, the unrelated chain and sentinel file remain, project-owned chains are gone, no project service/timer/process/listener remains, and only manifest-listed project paths were removed.

- [ ] **Step 7: Write the redacted acceptance report**

Include each command category, expected result, actual result, relevant exit code, before/after hashes, rollback evidence, preservation evidence, and any skipped test with its reason. The report must contain no public IP, password, private key, credential field, UUID, subscription URL, or node URI.

- [ ] **Step 8: Commit the VPS harness and report**

```bash
git add tests/vps
git commit -m "test: add VPS failure-injection acceptance evidence"
```

## Task 12: Perform final review, publish the branch, and open the pull request

**Files:**
- Modify as required by review findings only

- [ ] **Step 1: Run the complete verification suite from a clean checkout**

Run:

```bash
bash scripts/release-checks.sh
bash tests/integration/distro-matrix.sh
git diff --check main...HEAD
git status --short
```

Expected: all checks exit zero and only intentional artifacts are tracked.

- [ ] **Step 2: Audit the final diff against the design**

Confirm all update origins are owned, all downloads are HTTPS and verified, mutation paths are transactional, broad firewall/home cleanup is absent, secrets are not logged, subscriptions default to loopback, Serv00 cleanup is bounded, release permissions are minimal, 1.14 compatibility fixtures pass, and the VPS preservation evidence is complete.

- [ ] **Step 3: Scan for accidental secrets**

Scan the full branch and generated logs for the VPS address/password, private key material, UUID/node URI patterns, GitHub tokens, Telegram/GitLab/Cloudflare credentials, and complete subscription URLs. Remove the artifact—not merely the displayed line—if any match is found, then rerun the suite.

- [ ] **Step 4: Push the reviewed branch**

```bash
git push -u origin agent/comprehensive-hardening
```

- [ ] **Step 5: Open the pull request**

Create a PR to `reqingonline/sing-box-yg:main` with a concise risk-oriented summary, the exact verification commands, the four-distribution matrix result, the redacted VPS acceptance result, migration notes, and remaining limitations. Do not include credentials or complete connection data.

- [ ] **Step 6: Wait for and resolve required checks**

Inspect every required GitHub check and review comment. Fix root causes on the same branch, rerun the affected local tests, push the fix, and stop only when all required checks pass or a documented external blocker requires the repository owner's action.

---

## Completion evidence

The work is complete only when all twelve task sections are checked, every listed verification command has current output, a tagged Release candidate is reproducible and checksum-verified, the VPS acceptance report proves rollback and unrelated-state preservation, the branch is pushed, and the pull request's required checks are green. Release publication or merge remains an explicit repository-owner decision unless separately authorized.
