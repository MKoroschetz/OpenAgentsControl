#!/usr/bin/env bash
#
# validate-drift.sh - Detect drift in the postgres+pgagent combined image / running container.
# **Project**: aspaDB-workbench | **Path**: docker/postgres/validate-drift.sh
# **Version**: v2.0.0 | **Last Updated**: 2026-08-15 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v2.0.0 (2026-08-15): Combined postgres+pgagent image (architecture C) — PG 17 server is now DECLARED; tool verifies no stray/EOL PG major, no MTA, no extra tools.
# - v1.1.0 (2026-08-15): Whitelist base-image essentials + gnupg sub-packages so a minimal build reports CLEAN.
# - v1.0.0 (2026-08-15): Initial drift validation for the pg-agent container

# Why this exists: the image must contain ONLY
#   - Debian 13 slim base essentials
#   - postgresql-17 + postgresql-17-pgagent + postgresql-contrib (declared)
#   - the helper tools declared below + their dependency closure
# Anything else (a second/EOL PG major, an MTA like exim4/postfix, extra admins
# tools) is flagged as DRIFT. The saved baseline additionally catches package
# drift over time.
#
# Usage:
#   ./validate-drift.sh image [--no-build]   # build image, inventory, compare, report
#   ./validate-drift.sh baseline             # save current image inventory as baseline
#   ./validate-drift.sh container <name>     # docker diff + dpkg diff of a running container
#   ./validate-drift.sh -h                   # help
#
# Exit codes:
#   0  clean - no drift found
#   1  drift found (unexpected packages/tools, changed baseline, container diff)
#   2  usage / operational error
#
# Requirements: docker installed and daemon running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORTS_DIR="$SCRIPT_DIR/reports"
IMAGE_TAG="aspadb-postgres:17"
BASELINE_FILE="$SCRIPT_DIR/reports/baseline-image-packages.txt"

# Packages explicitly installed by the Dockerfile (the declared set).
# Debian 13 bundles contrib (pg_stat_statements, ...) inside postgresql-17.
# PGDG ships pgagent as the universal package `pgagent` (virtual provides
# postgresql-17-pgagent); postgresql-17-pgagent is NOT a dpkg package.
DECLARED_PKGS=( apt-utils curl nano cron openssh-client ca-certificates gnupg \
                postgresql-17 pgagent )

# Documented dependency closure of the declared set on Debian 13 (trixie, amd64):
# postgresql-17 + postgresql-17-pgagent (PGDG) + postgresql-contrib + helper
# tools. Packages in this list are EXPECTED on a clean build - not drift.
EXPECTED_DEPS=(
  # PostgreSQL 17 closure (postgresql-17 bundles contrib on Debian 13;
# pgagent = PGDG universal package providing virtual postgresql-17-pgagent)
  postgresql-17 pgagent
  postgresql-common postgresql-client-common postgresql-client-17
  libpq5 libpq
  # pgagent (PGDG trixie) daemon libs
  libboost1.83.0 libboost-filesystem1.83.0 libboost-thread1.83.0
  libssl3t64 openssl ssl-cert gnupg-gpg
  libldap2 libsasl2-2 libsasl2-modules-db libsasl2-modules ldap-utils
  libxml2 libxslt1.1
  # krb5 / ldap / ssl closure
  libkrb5-3 libkrb5support0 libk5crypto3 libcom-err2 libgssapi-krb5-2
  libgmp10 libhogweed6 libnettle8 libgnutls30t64 libtasn1-6 libunistring5
  libp11-kit0 libidn2-0 libncurses6 libreadline8t64 libpcsclite1
  perl perl-base libperl5.40 libdb5.3t64 libgdbm6t64 libgdbm-compat4t64
  libstdc++6 libgcc-s1 libc6 libc-bin libatomic1
  zlib1g libbz2-1.0 locales tzdata
  adduser passwd debconf debconf-i18n init-system-helpers
  sensible-utils ucf readline-common sysvinit-utils lsb-base logrotate
  libedit2 libpam0g libpam-runtime libsystemd0 libudev1 libkeyutils1
  # curl / libcurl closure
  libcurl4t64 libbrotli1 libpsl5t64 libnghttp2-14 librtmp1 libssh2-1t64
  # openssh-client / nano / apt closure
  libedit2 libselinux1 libpcre2-8-0 libseccomp2 libapt-pkg-perl libdpkg-perl
  libpopt0 libcap2 libcap2-bin
  # gnupg / dirmngr closure
  libgcrypt20 libgpg-error0 libassuan0 libksba8 libnpth0 pinentry-curses
  libsqlite3-0 libffi8t64 libcrypt1
  # base image essentials (debian:13-slim) - expected, not drift
  apt base-files base-passwd bash bsdutils coreutils dash
  debian-archive-keyring debianutils diffutils dpkg e2fsprogs findutils
  gcc-14-base grep gzip hostname login logsave mawk mount ncurses-base
  ncurses-bin sed tar util-linux
  libacl1 libapt-pkg7.0 libattr1 libaudit1 libaudit-common libblkid1
  libbsd0 libcap-ng0 libcbor0 libdebconfclient0 libext2fs2
  libfido2-1 liblzma5 libmd0 libmount1 libnsl2 libpam-modules
  libpam-modules-bin libsemanage1 libsemanage-common libsepol1
  libsmartcols1 libss2 libtirpc3t64 libtirpc-common libuuid1
  libxxhash0 libzstd1 libb2-1
  # gnupg sub-packages (declared via gnupg)
  gnupg gnupg2 gnupg-l10n gnupg-utils gpg gpgv gpg-agent gpgconf gpgsm
  gpg-wks-client gpg-wks-server dirmngr
  # Debian 13 (trixie) renames / extra transitive closure (verified on build)
  libc-l10n liblastlog2-2 libsystemd-shared libproc2-0 libcpuid16
  libicu76 libllvm19 libz3-4 libapparmor1 libsemanage2 libsepol2
  libcbor0.10 libffi8 liblz4-1 libnghttp3-9 libhwasan0
  libassuan9 libnpth0t64 libhogweed6t64 libnettle8t64 libtinfo6
  libjson-perl libtext-charwidth-perl libtext-wrapi18n-perl libncursesw6
  login.defs netbase procps systemd cron-daemon-common
  openssl-provider-legacy perl-modules-5.40 sqv
)

# Tools whose presence is verified inside the image / container.
TOOL_CHECK=( pgagent psql pg_dump pg_restore postgres curl nano cron ssh gpg )

usage() {
  sed -n '2,20p' "$0"
  exit 2
}

err() { echo "ERROR: $*" >&2; }

# inventory_image <image> -> sets INSTALLED_PKGS, INSTALLED_TOOLS, IMG_SIZE
inventory_image() {
  local img="$1"
  INSTALLED_PKGS="$(docker run --rm "$img" dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort || true)"
  if [ -z "$INSTALLED_PKGS" ]; then
    err "could not read package list from image $img"
    exit 2
  fi
  INSTALLED_TOOLS=""
  for t in "${TOOL_CHECK[@]}"; do
    if docker run --rm "$img" bash -c "command -v $t >/dev/null 2>&1"; then
      INSTALLED_TOOLS+="$(docker run --rm "$img" bash -c "command -v $t")"$'\n'
    fi
  done
  INSTALLED_TOOLS="$(printf '%s' "$INSTALLED_TOOLS" | sort)"
  IMG_SIZE="$(docker image inspect "$img" --format='{{.Size}}' 2>/dev/null || echo "?")"
}

human_size() {
  local b="$1"
  if [ "$b" = "?" ]; then echo "?"; return; fi
  awk -v s="$b" 'BEGIN { if (s > 1073741824) printf "%.2f GB", s/1073741824; else printf "%.2f MB", s/1048576 }'
}

pkg_names_of() { printf '%s\n' "$1" | cut -f1; }

cmd_image() {
  local no_build="${1:-}"
  if [ "$no_build" != "--no-build" ]; then
    echo "==> docker build -t $IMAGE_TAG $SCRIPT_DIR"
    docker build -t "$IMAGE_TAG" "$SCRIPT_DIR"
  fi
  if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    err "image $IMAGE_TAG not present (build failed or --no-build without existing image)"
    exit 2
  fi

  inventory_image "$IMAGE_TAG"

  local declared_set expected_set
  declared_set="$(printf '%s\n' "${DECLARED_PKGS[@]}" | sort -u)"
  expected_set="$(printf '%s\n' "${EXPECTED_DEPS[@]}" | sort -u)"

  # Missing declared packages = build broken.
  local missing=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if ! grep -qx "$p" <<<"$(pkg_names_of "$INSTALLED_PKGS")"; then
      missing+="  $p\n"
    fi
  done <<<"$declared_set"

  # Unexpected packages = installed but neither declared nor expected.
  local unexpected=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if ! grep -qx "$p" <<<"$declared_set" && ! grep -qx "$p" <<<"$expected_set"; then
      unexpected+="  $p\n"
    fi
  done <<<"$(pkg_names_of "$INSTALLED_PKGS")"

  # Baseline drift = package set differs from saved baseline.
  local baseline_drift=""
  if [ -f "$BASELINE_FILE" ]; then
    baseline_drift="$(diff <(pkg_names_of "$INSTALLED_PKGS") "$BASELINE_FILE" | sed 's/^/  /')" || true
  fi

  local drift=0
  [ -n "$missing" ] && drift=1
  [ -n "$unexpected" ] && drift=1
  [ -n "$baseline_drift" ] && drift=1

  local out="$REPORTS_DIR/validate-drift-image-$(date +%Y%m%d-%H%M%S).md"
  mkdir -p "$REPORTS_DIR"
  {
    echo "# pg-agent image drift report"
    echo
    echo "- Image: \`$IMAGE_TAG\`"
    echo "- Size: $(human_size "$IMG_SIZE")"
    echo "- Inventoried: $(date -Is)"
    echo
    echo "## Result: $([ $drift -eq 0 ] && echo 'CLEAN' || echo 'DRIFT DETECTED')"
    echo
    echo "## Declared packages (Dockerfile)"
    echo '```'
    printf '%s\n' "${DECLARED_PKGS[@]}"
    echo '```'
    echo
    echo "## Installed packages ($(pkg_names_of "$INSTALLED_PKGS" | wc -l) total)"
    echo '```'
    printf '%s\n' "$INSTALLED_PKGS"
    echo '```'
    echo
    echo "## Tools present"
    echo '```'
    printf '%s\n' "$INSTALLED_TOOLS"
    echo '```'
    echo
    echo "## Missing declared packages"
    [ -n "$missing" ] && printf '%b\n' "$missing" || echo "(none)"
    echo
    echo "## Unexpected packages (not declared, not in expected dependency closure)"
    [ -n "$unexpected" ] && printf '%b\n' "$unexpected" || echo "(none)"
    echo
    echo "## Baseline drift vs $(basename "$BASELINE_FILE")"
    [ -n "$baseline_drift" ] && printf '%s\n' "$baseline_drift" || echo "(none - matches baseline)"
    echo
  } >"$out"

  echo "==> image size: $(human_size "$IMG_SIZE")"
  echo "==> installed packages: $(pkg_names_of "$INSTALLED_PKGS" | wc -l)"
  echo "==> report: $out"
  if [ -n "$missing" ]; then
    echo "==> DRIFT: declared packages missing from image:" >&2
    printf '%b' "$missing" >&2
  fi
  if [ -n "$unexpected" ]; then
    echo "==> DRIFT: unexpected packages in image:" >&2
    printf '%b' "$unexpected" >&2
  fi
  if [ -n "$baseline_drift" ]; then
    echo "==> DRIFT: package set changed vs baseline:" >&2
    printf '%s\n' "$baseline_drift" >&2
  fi
  [ $drift -eq 0 ] && echo "==> CLEAN: image matches declared set + expected deps + baseline."
  exit $drift
}

cmd_baseline() {
  if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    err "image $IMAGE_TAG not present - run 'validate-drift.sh image' first"
    exit 2
  fi
  inventory_image "$IMAGE_TAG"
  mkdir -p "$REPORTS_DIR"
  pkg_names_of "$INSTALLED_PKGS" >"$BASELINE_FILE"
  echo "==> baseline saved: $BASELINE_FILE ($(wc -l <"$BASELINE_FILE") packages)"
  echo "==> image size: $(human_size "$IMG_SIZE")"
}

cmd_container() {
  local cname="${1:-}"
  if [ -z "$cname" ]; then
    err "container mode requires a container name/ID"
    usage
  fi
  if ! docker inspect "$cname" >/dev/null 2>&1; then
    err "no such container: $cname"
    exit 2
  fi

  local img
  img="$(docker inspect "$cname" --format='{{.Image}}' | cut -c1-12)"
  local out="$REPORTS_DIR/validate-drift-container-$cname-$(date +%Y%m%d-%H%M%S).md"
  mkdir -p "$REPORTS_DIR"

  local diffout=""
  diffout="$(docker diff "$cname" 2>/dev/null | sort || true)"

  local img_pkgs ctr_pkgs pkg_diff
  img_pkgs="$(docker run --rm "$img" dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort || true)"
  ctr_pkgs="$(docker exec "$cname" dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort || true)"
  pkg_diff="$(diff <(printf '%s\n' "$img_pkgs") <(printf '%s\n' "$ctr_pkgs") || true)"

  local drift=0
  [ -n "$diffout" ] && drift=1
  [ -n "$pkg_diff" ] && drift=1

  {
    echo "# pg-agent container drift report"
    echo
    echo "- Container: \`$cname\`"
    echo "- Image: \`$img\`"
    echo "- Inspected: $(date -Is)"
    echo
    echo "## Result: $([ $drift -eq 0 ] && echo 'CLEAN' || echo 'DRIFT DETECTED')"
    echo
    echo "## docker diff (A=added, C=changed, D=deleted vs image)"
    echo '```'
    printf '%s\n' "$diffout"
    echo '```'
    echo
    echo "## dpkg diff (container vs image)"
    echo '```'
    printf '%s\n' "$pkg_diff"
    echo '```'
    echo
  } >"$out"

  echo "==> report: $out"
  if [ -n "$diffout" ]; then
    echo "==> DRIFT: files added/changed/deleted vs image (e.g. manual tool installs):" >&2
    printf '%s\n' "$diffout" >&2
  fi
  if [ -n "$pkg_diff" ]; then
    echo "==> DRIFT: installed packages differ from image:" >&2
    printf '%s\n' "$pkg_diff" >&2
  fi
  [ $drift -eq 0 ] && echo "==> CLEAN: container matches its image."
  exit $drift
}

cmd="${1:-}"
case "$cmd" in
  image)     cmd_image "${2:-}" ;;
  baseline)  cmd_baseline ;;
  container) cmd_container "${2:-}" ;;
  -h|--help) usage ;;
  *) err "unknown command: $cmd"; usage ;;
esac
