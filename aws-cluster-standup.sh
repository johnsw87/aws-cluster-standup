#!/bin/bash
# Script to quickly stand up GKE clusters in AWS.
#
# There is some config you can make early in this file. Most things you can leave as default.
#
# You will also need the following utilities:
# - Terraform (the one in cloud shell is out of date as of 2020-01-30)
# - jq (built in to cloud shell)
# - aws CLI (to generate ~/.aws/credentials)
# - anthos-gke (you can get this from here: gs://gke-multi-cloud-release/bin/aws-0.1.0-gke.8/anthos-for-gke.tgz)

# - define project name var
if [ -z "$PROJECT" ]; then
    echo Please enther the GCP Project Name:
    read PROJECT
fi

# Service account name (can ignore if you supply `anthos-gke-gcr.json`)
# This must be whitelisted here: https://docs.google.com/forms/d/e/1FAIpQLSfEUuzy_RHaArKi1nE9gWUJlqanWLFzpTJDlsiTi0fnUmewrw/viewform
if [ -z "$service_account" ]; then
    service_account="anthos-gke-gcr@${PROJECT}.iam.gserviceaccount.com"
fi

# AWS Zone
if [ -z "$aws_region" ]; then
    aws_region=eu-west-1a
fi

# Clusters to configure - they must be 18 chars or less (else you'll get errors later)
if [ -z "${clusters[@]}" ]; then
clusters=(
    aws-cluster-1
)
fi

# Set a default version to deploy
if [ -z "$BUNDLE_VERSION" ]; then
    export BUNDLE_VERSION=aws-0.1.0-gke.8
fi

fail() {
    >&2 echo '[Failure]' "$@"
    warn Tail of error log:
    >&2 tail anthos-gke.err.log
    exit 1
}

warn() {
    >&2 echo '[Warning]' "$@"
}

info() {
    echo '[Info]' "$@"
}

_anthos-gke() {
    if ! anthos-gke "${@}" >>anthos-gke.log 2>>anthos-gke.err.log; then
        fail "Error (exit code $?) - see anthos-gke.err.log"
    fi
}

_kubectl() {
    if ! kubectl "${@}" >>anthos-gke.log 2>>anthos-gke.err.log; then
        fail "Error (exit code $?) - see anthos-gke.err.log"
    fi
}

check_cmd() {
    if ! command -v "$@" >/dev/null 2>&1; then fail "Command '${*}' missing - do you need to install it?"; fi
}

check_cmd jq
check_cmd terraform
check_cmd anthos-gke

if [ ! -f "id_rsa" ]; then
    info Generating ssh key
    if ! ssh-keygen -t rsa -b 2048 -q -N "" -f ./id_rsa >>anthos-gke.log 2>>anthos-gke.err.log; then
        fail Failed to generate ssh key
    fi
fi

if [ ! -f anthos-gke-gcr.json ]; then
    gcloud iam service-accounts keys create anthos-gke-gcr.json --iam-account "$service_account"
fi

# There's a bug where service accounts won't have the "kind" field and the tool doesn't like it
# ...this fixes it
if ! jq -e '.kind' anthos-gke-gcr.json >/dev/null 2>&1; then
    info Adding kind field to service account
    jq '. += {"kind":"'"$(jq -r '.type' anthos-gke-gcr.json)"'"}' anthos-gke-gcr.json > anthos-gke-gcr.json.tmp && mv anthos-gke-gcr.json.tmp anthos-gke-gcr.json
fi

if [ ! -f registry-secret ]; then
    secret="$(cat anthos-gke-gcr.json)"
    auth="$(printf '%s' "_json_key:${secret}" | base64 -w0)"
    cat > registry-secret << EOF
{ "auths": { "gcr.io": { "auth": "${auth}" } } }
EOF
fi

if [ ! -f "$HOME"/.aws/credentials ]; then
    fail "$HOME"/.aws/credentials not found - please log in to AWS using the AWS CLI
fi


info Generating baselayer

_anthos-gke generate baselayer -f .

info Updating region to "$aws_region"
if [ ! -f "baselayer.yaml" ]; then
    fail No baselayer found
fi

sed -i 's/ca-central-1a/'"$aws_region"'/' baselayer.yaml

info Applying baselayer

_anthos-gke apply -f .

for cluster in "${clusters[@]}"; do
    info Generating cluster "$cluster"
    _anthos-gke generate gke "$cluster" -f .
    info Standing up cluster "$cluster"
    _anthos-gke apply -f "$cluster"
done

info Waiting for clusters to come up
anthos-gke login gke "${clusters[0]}" >/dev/null 2>&1
for i in {1..15}; do
    if kubectl get ns >/dev/null 2>&1; then
        break
    fi
    sleep "$i"
done

for cluster in "${clusters[@]}"; do
    info Logging in to cluster
    _anthos-gke login gke "$cluster"
    info Applying admin config
    _kubectl create serviceaccount -n kube-system admin-user
    _kubectl create clusterrolebinding admin-user-binding --clusterrole cluster-admin --serviceaccount kube-system:admin-user
    secret_name="$(kubectl get serviceaccount -n kube-system admin-user  -o jsonpath='{$.secrets[0].name}')"
    secret="$(kubectl get secret -n kube-system "${secret_name}" -o jsonpath='{$.data.token}'  | base64 -d | sed $'s/$/\\\n/g')"
    info Cluster "$cluster" secret
    echo "$secret" | tee anthos-gke.log
done

info Complete - created clusters "${clusters[@]}"
