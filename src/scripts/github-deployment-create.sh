#!/bin/bash
set -e

ENVIRONMENT="$(echo "${ENVIRONMENT}" | circleci env subst)"
ORGANISATION="$(echo "${ORGANISATION}" | circleci env subst)"
REPOSITORY="$(echo "${REPOSITORY}" | circleci env subst)"
REFERENCE="$(echo "${REFERENCE}" | circleci env subst)"
CLIENT_ID="$(echo "${CLIENT_ID}" | circleci env subst)"

AUTO_MERGE=false;
[[ $AUTO_MERGE_ENABLED = "true" ]] && AUTO_MERGE=true

PROD_ENV=false;
prd_envs=( "prd" "prod" "production" )
for value in "${prd_envs[@]}"
do
  [[ $ENVIRONMENT = "$value" ]] && PROD_ENV=true
done
response=$(curl -X POST -s \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  -u "$CLIENT_ID:$GITHUB_APP_INSTALLATION_TOKEN" \
  -d "{\"ref\":\"$REFERENCE\",\"environment\":\"$ENVIRONMENT\",\"required_contexts\":$REQUIRED_CONTEXTS,\"auto_merge\":$AUTO_MERGE,\"production_environment\":$PROD_ENV}" \
  "https://api.github.com/repos/$ORGANISATION/$REPOSITORY/deployments")
echo "$response"
id=$(echo "$response" | jq '.id')
echo "Github deployment id $id created"
echo "export DEPLOYMENT_ID=$id" >> "$BASH_ENV"
