#!/usr/bin/env bash
# sync-greentech-cert.sh - Sync the *.greentech.consulting wildcard cert from
# gtc-portainer (where it's renewed via manual certbot DNS-01) to aspaDB-dev
# (which never runs certbot itself, only serves the cert nginx-side).
#
# **Project**: aspaDB-workbench | **Path**: docker/iotstack/dev/nginx/scripts/sync-greentech-cert.sh
# **Version**: v1.0.0 | **Last Updated**: 2026-08-19 | **Author**: Manfred Koroschetz/AI
# **License**: SPDX-License-Identifier: MIT
#
# ## Changelog
# - v1.0.0 (2026-08-19): Initial script, written after finding the previous manual
#   process (download tar.gz to workstation, re-upload) meant the cert on aspaDB-dev
#   had gone 8+ months unrenewed while gtc-portainer's own copy stayed current. This
#   pipes the four PEM files directly host-to-host over SSH (no intermediate copy on
#   the machine running this script, no key material ever touches this repo or a
#   git-tracked directory) into the flattened path aspa-443.conf/aspa-678.conf expect
#   as of their v1.1.0 (see those files' changelogs for why the certbot archive/liveN
#   layout was dropped in favor of a fixed path here).
#
# Run this from a machine with SSH key access to BOTH hosts (your workstation, or
# wherever ~/.ssh/config defines the two aliases below - see aspaDB-workbench's own
# ~/.ssh/config for the working entries: gtc-portainer is 45.86.163.71 port 1986,
# user root; aspaDB-dev is 192.168.100.32, user root).
#
# What this does NOT do: reload nginx. The first time you run this after a conf
# path change, apply the aspa-443.conf/aspa-678.conf update to aspaDB-dev's live
# services/nginx/sites-enabled/ first (so the reload has somewhere valid to point),
# THEN run this script. On every renewal after that, the conf is already correct,
# so this script's own `nginx -t && nginx -s reload` at the end is the real cutover.

set -euo pipefail

GTC_HOST="${GTC_HOST:-gtc-portainer}"
DEV_HOST="${DEV_HOST:-aspaDB-dev}"
GTC_CERT_DIR="/etc/letsencrypt/live/greentech.consulting"
DEV_CERT_DIR="/root/IOTstack/services/nginx/letsencrypt/greentech.consulting"

echo "==> Verifying source cert on ${GTC_HOST} (public info only)"
ssh "${GTC_HOST}" "openssl x509 -in ${GTC_CERT_DIR}/fullchain.pem -noout -subject -dates"

echo "==> Streaming cert.pem/chain.pem/fullchain.pem/privkey.pem to ${DEV_HOST}:${DEV_CERT_DIR}"
ssh "${DEV_HOST}" "mkdir -p ${DEV_CERT_DIR}"
ssh "${GTC_HOST}" "tar czf - -C ${GTC_CERT_DIR} -h cert.pem chain.pem fullchain.pem privkey.pem" \
  | ssh "${DEV_HOST}" "tar xzf - -C ${DEV_CERT_DIR} && chmod 600 ${DEV_CERT_DIR}/privkey.pem && chmod 644 ${DEV_CERT_DIR}/cert.pem ${DEV_CERT_DIR}/chain.pem ${DEV_CERT_DIR}/fullchain.pem"

echo "==> Verifying synced cert on ${DEV_HOST} (public info only)"
ssh "${DEV_HOST}" "openssl x509 -in ${DEV_CERT_DIR}/fullchain.pem -noout -subject -dates"

echo "==> Validating nginx config and reloading on ${DEV_HOST}"
ssh "${DEV_HOST}" "docker exec nginx nginx -t && docker exec nginx nginx -s reload"

echo "==> Done. Confirm live with:"
echo "    echo | openssl s_client -connect 192.168.100.32:443 -servername aspa.dev.greentech.consulting 2>/dev/null | openssl x509 -noout -dates"
