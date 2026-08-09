#!/usr/bin/env bash
# (c) JFrog Ltd. (2026)
#
# Wait until Secret Manager versions/latest is no longer the bootstrap placeholder.
# Used by terraform-example when create_cloud_run_example=true so the Artifact
# Registry connector is created only after a real rotated token exists.
#
# Required env: PROJECT_ID, SECRET_NAME
# Optional env:
#   PLACEHOLDER (default dummy-token)
#   WAIT_SEC (default 360) - countdown before first SECRET_ROTATE (~6 minutes)
#   POLL_INTERVAL_SEC (default 15)
#   POLL_TIMEOUT_SEC (default 300) - extra time to poll after WAIT_SEC

set -euo pipefail

PLACEHOLDER="${PLACEHOLDER:-dummy-token}"
WAIT_SEC="${WAIT_SEC:-360}"
POLL_INTERVAL_SEC="${POLL_INTERVAL_SEC:-15}"
POLL_TIMEOUT_SEC="${POLL_TIMEOUT_SEC:-300}"

reason="waiting for Secret Manager SECRET_ROTATE to replace bootstrap placeholder in ${SECRET_NAME}"

token_is_rotated() {
  local tok
  tok="$(gcloud secrets versions access latest \
    --secret="${SECRET_NAME}" \
    --project="${PROJECT_ID}" 2>/dev/null || true)"
  if [[ -z "${tok}" || "${tok}" == "${PLACEHOLDER}" || ${#tok} -lt 32 ]]; then
    return 1
  fi
  return 0
}

echo "wait_for_first_rotation: ${reason}"

if token_is_rotated; then
  echo "wait_for_first_rotation: secret already has a non-placeholder latest version; continuing"
  exit 0
fi

start_epoch="$(date -u +%s)"
deadline_epoch=$((start_epoch + WAIT_SEC))

while true; do
  now_epoch="$(date -u +%s)"
  remaining=$((deadline_epoch - now_epoch))
  if token_is_rotated; then
    echo "wait_for_first_rotation: first rotation complete; connector may proceed"
    exit 0
  fi
  if ((remaining <= 0)); then
    break
  fi
  echo "wait_for_first_rotation: ${reason}; time left ${remaining}s"
  sleep_for="${POLL_INTERVAL_SEC}"
  if ((remaining < sleep_for)); then
    sleep_for="${remaining}"
  fi
  sleep "${sleep_for}"
done

echo "wait_for_first_rotation: ${WAIT_SEC}s countdown done; polling for rotated secret (timeout ${POLL_TIMEOUT_SEC}s)"

poll_deadline=$(($(date -u +%s) + POLL_TIMEOUT_SEC))
while true; do
  now_epoch="$(date -u +%s)"
  remaining=$((poll_deadline - now_epoch))
  if token_is_rotated; then
    echo "wait_for_first_rotation: first rotation complete; connector may proceed"
    exit 0
  fi
  if ((remaining <= 0)); then
    echo "wait_for_first_rotation: timed out waiting for ${SECRET_NAME} to leave placeholder '${PLACEHOLDER}'" >&2
    echo "wait_for_first_rotation: check Cloud Function logs and Pub/Sub/Eventarc IAM, then re-run terraform apply" >&2
    exit 1
  fi
  echo "wait_for_first_rotation: ${reason}; polling; time left ${remaining}s"
  sleep_for="${POLL_INTERVAL_SEC}"
  if ((remaining < sleep_for)); then
    sleep_for="${remaining}"
  fi
  sleep "${sleep_for}"
done
