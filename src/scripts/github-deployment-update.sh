#!/bin/bash
set -e

ENVIRONMENT="$(echo "${ENVIRONMENT}" | circleci env subst)"
ORGANISATION="$(echo "${ORGANISATION}" | circleci env subst)"
REPOSITORY="$(echo "${REPOSITORY}" | circleci env subst)"
DESCRIPTION="$(echo "${DESCRIPTION}" | circleci env subst)"
LOG_URL="$(echo "${LOG_URL}" | circleci env subst)"
DEPLOYMENT_ID="$(echo "${DEPLOYMENT_ID}" | circleci env subst)"
CLIENT_ID="$(echo "${CLIENT_ID}" | circleci env subst)"

curl -X POST -s \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  -u "$CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d "{\"environment\":\"$ENVIRONMENT\",\"state\":\"$DEPLOY_STATUS\",\"environment_url\":\"$ENVIRONMENT_URL\",\"log_url\":\"$LOG_URL\",\"description\":\"$DESCRIPTION\",\"auto_inactive\":$AUTO_INACTIVE}" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/deployments/$DEPLOYMENT_ID/statuses"