#!/bin/bash

set -euo pipefail

if [[ -z "${BUILDKITE_API_ACCESS_TOKEN:-}" ]]; then
  echo "You must set the BUILDKITE_API_ACCESS_TOKEN environment variable (e.g. BUILDKITE_API_ACCESS_TOKEN = \"xyz\")"
  exit 1
fi

if [[ -z "${PIPELINE:-}" ]]; then
  echo "You must set the PIPELINE environment variable (e.g. PIPELINE = \"my-org/my-pipeline\")"
  exit 1
fi

ORG_SLUG=$(echo "${PIPELINE}" | cut -d'/' -f1)
PIPELINE_SLUG=$(echo "${PIPELINE}" | cut -d'/' -f2)

COMMIT="${COMMIT:-${GITHUB_SHA}}"
BRANCH="${BRANCH:-${GITHUB_REF#"refs/heads/"}}"
MESSAGE="${MESSAGE:-}"

PUSHER_NAME=$(jq -r ".pusher.name //empty" "$GITHUB_EVENT_PATH")
PUSHER_EMAIL=$(jq -r ".pusher.email //empty" "$GITHUB_EVENT_PATH")
NAME="${NAME:-${PUSHER_NAME}}"
EMAIL="${EMAIL:-${PUSHER_EMAIL}}"

# if [[ -z "${NAME}" ]]; then
#   echo "You must set the NAME environment variable if the github event doesn't have a \"pusher\" key"
#   exit 1
# fi

# if [[ -z "${EMAIL}" ]]; then
#   echo "You must set the EMAIL environment variable if the github event doesn't have a \"pusher\" key"
#   exit 1
# fi

# Use jq’s --arg properly escapes string values for us
JSON=$(
  jq -c -n \
    --arg COMMIT  "$COMMIT" \
    --arg BRANCH  "$BRANCH" \
    --arg MESSAGE "$MESSAGE" \
    --arg PULL_REQUEST_ID "$PULL_REQUEST_ID" \
    --arg PULL_REQUEST_REPOSITORY "$PULL_REQUEST_REPOSITORY" \
    --arg PULL_REQUEST_BASE_BRANCH "$PULL_REQUEST_BASE_BRANCH" \
    '{
      "commit": $COMMIT,
      "branch": $BRANCH,
      "message": $MESSAGE,
      "pull_request_id": $PULL_REQUEST_ID,
      "pull_request_repository": $PULL_REQUEST_REPOSITORY,
      "pull_request_base_branch": $PULL_REQUEST_BASE_BRANCH,
      "ignore_pipeline_branch_filters": true
    }'
)

# Merge in the build environment variables, if they specified any
if [[ "${BUILD_ENV_VARS:-}" ]]; then
  if ! JSON=$(echo "$JSON" | jq -c --argjson BUILD_ENV_VARS "$BUILD_ENV_VARS" '. + {env: $BUILD_ENV_VARS}'); then
    echo ""
    echo "Error: BUILD_ENV_VARS provided invalid JSON: $BUILD_ENV_VARS"
    exit 1
  fi
fi

RESPONSE=$(
  curl \
    --fail \
    --silent \
    -X POST \
    -H "Authorization: Bearer ${BUILDKITE_API_ACCESS_TOKEN}" \
    "https://api.buildkite.com/v2/organizations/${ORG_SLUG}/pipelines/${PIPELINE_SLUG}/builds" \
    -d "$JSON"
)

echo ""
echo "Build created:"
echo "$RESPONSE" | jq --raw-output ".web_url"

# Save output for downstream actions
echo "${RESPONSE}" > "${HOME}/${GITHUB_ACTION}.json"

echo ""
echo "Saved build JSON to:"
echo "${HOME}/${GITHUB_ACTION}.json"
