#!/bin/bash
# Script to quickly stand up ACM on Anthos on AWS clusters.

# - define GCP account email i.e. bob@google.com.
if [ -z "$account_email" ]; then
    echo Please enther the email address used to sign into GCP:
    read account_email
fi

kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$account_email"

gsutil cp gs://config-management-release/released/latest/config-management-operator.yaml config-management-operator.yaml

kubectl apply -f config-management-operator.yaml

echo Operator Deployed.

# - define git username for acm repo.
if [ -z "$git_username" ]; then
    echo Please enther the github username for the acm repository:
    read git_username
fi

# - define filename got git keys, created local to this script.
if [ -z "$git_keypair_filename" ]; then
    echo 'Please enter a filename for the ssh Key Pair)':
    read git_keypair_filename
fi

ssh-keygen -t rsa -b 4096 -C "$git_username" -N '' -f "$git_keypair_filename"

git_keypair_private="$git_keypair_filename"
git_keypair_filename+=".pub"

cat "$git_keypair_filename"

echo copy and paste this to git.

kubectl create secret generic git-creds --namespace=config-management-system --from-file=ssh="$git_keypair_private"

# - define filename got git keys, created local to this script.
if [ -z "$gke_cluster_name" ]; then
    echo 'Please enter your gke cluster name':
    read gke_cluster_name
fi

# - define filename got git keys, created local to this script.
if [ -z "$git_repo" ]; then
    echo 'Please enter your git repo name that will be monitored.':
    read git_repo
fi

cat <<EOF >config-management.yaml
apiVersion: configmanagement.gke.io/v1
kind: ConfigManagement
metadata:
    name: config-management
    namespace: config-management-system
spec:
  clusterName: $gke_cluster_name
  git:
    syncRepo: git@github.com:$git_username/$git_repo.git
    syncBranch: master
    secretType: ssh
    policyDir: "."
EOF

kubectl apply -f config-management.yaml
