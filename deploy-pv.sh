#!/bin/bash

set -euo pipefail

declare ZONE
declare REGION

declare CLUSTER_NAME=$(terraform -chdir=./terraform output -json | jq -r '.cluster_name.value')

function installAwsEbsCSI () {

  kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.16"	

  # give pods time to start up
  sleep 10s

  # Patch the controller to make it label volumes to make it easier for us to see volumes
  # that belong to this cluster
  local tag_value="$CLUSTER_NAME-ebs-csi"
  kubectl patch deployment -n kube-system ebs-csi-controller --type='json' \
         --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value":"--extra-tags=Name='"${tag_value}"'"}]'

  # give pods time to restart since we've updated the deployment
  sleep 10s

}

function labelNodes () {

  # This is something a cloud-controller-manager would automatically take care of,
  # but we dont have one (yet), so we have to manually label the nodes so that
  # volumes will get mounted on the right nodes

  # NOTE that currently, all cluster nodes are deployed to the same az
  # NOTE also that we're relying on the aws ebs CSI provider having labeled the node already
  #      so this cant happen until after CSI provider has been installed
  ZONE="$(kubectl get nodes -o=jsonpath='{.items[0].metadata.labels.topology\.ebs\.csi\.aws\.com/zone}')"
  REGION="${ZONE:0:-1}"

  kubectl label nodes --all=true "topology.kubernetes.io/region=${REGION}"
  kubectl label nodes --all=true "topology.kubernetes.io/zone=${ZONE}"

}

function createStorageClass () {

	kubectl apply -f - << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp2
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/region
    values:
    - ${REGION}
  - key: topology.kubernetes.io/zone
    values:
    - ${ZONE}
EOF

}

function createPersistentVolumeClaim () {

	kubectl apply -f  - << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ebs-claim
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ebs-gp2
  resources:
    requests:
      storage: 4Gi
EOF

}

function main () {

  installAwsEbsCSI
  labelNodes
  createStorageClass
  createPersistentVolumeClaim

}

main "$@"