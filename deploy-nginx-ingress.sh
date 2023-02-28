#!/bin/bash

set -euo pipefail

# Deploy the nginx ingress controller
# See https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-manifests/
#
# NOTE: this is NOT the same as the nginx ingress controller that is supplied by
# the kubernetes organization on github (https://github.com/kubernetes/ingress-nginx)
# so be careful when searching for documentation


mkdir -p ./tmp
(cd ./tmp; git clone https://github.com/nginxinc/kubernetes-ingress.git --branch v3.0.2)

declare MANIFESTS_DIR="$(pwd)/tmp/kubernetes-ingress/deployments"

kubectl apply -f "${MANIFESTS_DIR}/common/ns-and-sa.yaml"
kubectl apply -f "${MANIFESTS_DIR}/rbac/rbac.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/default-server-secret.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/nginx-config.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/ingress-class.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/crds/k8s.nginx.org_virtualservers.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/crds/k8s.nginx.org_virtualserverroutes.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/crds/k8s.nginx.org_transportservers.yaml"
kubectl apply -f "${MANIFESTS_DIR}/common/crds/k8s.nginx.org_policies.yaml"
kubectl apply -f "${MANIFESTS_DIR}/daemon-set/nginx-ingress.yaml"
