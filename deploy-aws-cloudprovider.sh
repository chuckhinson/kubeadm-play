#!/bin/bash

set -euo pipefail

# Note that this assumes that terraform has already labelled resources properly.  
# Note also that it appears this needs to be done before joining additional
# constrol plane nodes

export KUBECONFIG="$(pwd)/cluster_admin.conf"

mkdir -p ./tmp
if [ -d ./tmp/cloud-provider-aws ] ; then
  :
else
  (cd ./tmp; git clone git@github.com:kubernetes/cloud-provider-aws.git)
fi

kubectl kustomize ./tmp/cloud-provider-aws/examples/existing-cluster/overlays/superset-role/ | \
    sed 's|node-role.kubernetes.io/master|node-role.kubernetes.io/control-plane|g' | \
    sed 's/cloud-controller-manager:v1.23.0-alpha.0/cloud-controller-manager:v1.26.0/g' \
    > ./tmp/aws-cloud-provider.yaml



kubectl apply -f ./tmp/aws-cloud-provider.yaml
