#!/bin/bash
set -xe

APP_NAME="$(echo "${APP_NAME}" | circleci env subst)"
BOOTSTRAP_APP_NAME="$(echo "${BOOTSTRAP_APP_NAME}" | circleci env subst)"
SERVER="$(echo "${SERVER}" | circleci env subst)"
SERVER="$(echo "${SERVER}" | circleci env subst)"
REGIONS="$(echo "${REGIONS}" | circleci env subst)"
TOKEN="$(echo "${TOKEN}" | circleci env subst)"

applicationCRDType="Application"
read -r -a regions <<< "$REGIONS"
if [ "${#regions[@]}" -gt 1 ]; then
  applicationCRDType="ApplicationSet"
  for region in "${regions[@]}"
  do
    applications+="$APP_NAME-$region "
  done
else
   applications="$APP_NAME"
fi

argocd --server "$SERVER" --grpc-web --auth-token "$TOKEN" app wait "$BOOTSTRAP_APP_NAME" --operation
argocd --server "$SERVER" --grpc-web --auth-token "$TOKEN" app sync "$BOOTSTRAP_APP_NAME" --prune || \
argocd --server "$SERVER" --grpc-web --auth-token "$TOKEN" app sync "$BOOTSTRAP_APP_NAME" --resource "argoproj.io:$applicationCRDType:$APP_NAME" --prune || echo "$BOOTSTRAP_APP_NAME already synced"

# shellcheck disable=SC2086
argocd --server "$SERVER" --grpc-web --auth-token "$TOKEN" app wait $applications --operation
# shellcheck disable=SC2086
argocd --server "$SERVER" --grpc-web --auth-token "$TOKEN" app sync $applications --async --prune
# shellcheck disable=SC2086
argocd --server "$SERVER" --grpc-web --auth-token "$TOKEN" app wait $applications