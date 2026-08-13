# A4 core upgrade acceptance (redacted)

Date: 2026-08-13 (Asia/Shanghai)

This report contains only versions, exit codes, hashes and service states. It
does not contain the VPS address, password, UUIDs, private keys, WARP data,
subscription links or generated node configurations.

## Official upstream resolution

The sing-box Releases API was queried from the disposable Ubuntu 24.04 VPS.
The selection excluded draft and prerelease releases. At test time:

- latest stable: `v1.13.18` (published 2026-08-09);
- newest prerelease observed: `v1.14.0-beta.14` (published 2026-08-11);
- amd64 archive digest for `sing-box-1.13.18-linux-amd64.tar.gz`:
  `sha256:d34d987ed6ae39ca3760269264fb502b867e5477db45518c829b07776245c495`.

The production/default path therefore remains stable `1.13.18`; the 1.14 beta
is visible as a testing channel but is not selected by the default install or
upgrade action.

## Fresh install and A3 regression

The release commit was installed onto a clean Ubuntu 24.04 x86_64 host before
the A4 code changes. The initial run exposed a real packaging defect: the
health timer pointed to `/usr/local/lib/sing-box-yg/sb-doctor.sh`, while the
release package stored the executable under `scripts/sb-doctor.sh`. The timer
was active but failed with `203/EXEC`.

After correcting the path in both the install and maintenance paths, the full
regression returned:

| Check | Result |
| --- | --- |
| health unit render | exit 0 |
| manual health service | exit 0, `Result=success` |
| A3 baseline/check | exit 0 |
| explicit backup and manifest | exit 0 |
| invalid JSON + port-conflict injection | exit 0; helper reported PASS |
| explicit backup rollback | exit 0; helper reported PASS |
| doctor `--repair` | exit 0 |
| sing-box config check | exit 0 |
| sing-box service / health timer | active / active |

## Core upgrade matrix

The menu's explicit-version path first installed the known older stable
`1.13.16`, then the new API-backed stable action upgraded to `1.13.18`.
Both versions passed config validation, service activation, timer activation
and doctor repair. The transaction marker was committed and a previous core
was retained for recovery.

For the rollback proof, the running core was replaced atomically with an
invalid executable. `sb-doctor.sh --repair` restored the previous `1.13.16`
core, restarted the service, and returned exit 0. The final stable upgrade
returned the host to `1.13.18`; config check, service, timer and doctor all
returned 0 again.

## Scope and remaining validation

The VPS-side acceptance covers configuration parsing, all five generated
inbound listeners, service lifecycle, health repair, transaction rollback and
the official core asset digest path. A real external client handshake was not
run in this disposable test because no client device or user subscription
credential was placed in scope. Listener readiness is therefore reported as a
server-side result, not as proof of end-to-end client traffic.
