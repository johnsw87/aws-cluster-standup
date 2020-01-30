# AWS Cluster Standup

This small script automates the process of standing up an AWS cluster. It is designed to work with Cloud Shell

You will need:

1. A [whitelisted service account](https://docs.google.com/forms/d/e/1FAIpQLSfEUuzy_RHaArKi1nE9gWUJlqanWLFzpTJDlsiTi0fnUmewrw/viewform)
2. AWS Credentials and the [AWS CLI](https://aws.amazon.com/cli/)
3. Some CLI tools:
    * `jq`
    * `terraform`
    * `kubectl`
    * `anthos-gke` (`gsutil cp gs://gke-multi-cloud-release/bin/aws-0.1.0-gke.8/anthos-for-gke.tgz .`)
    * `gcloud`
4. Send PR and issues if it doesn't work!
