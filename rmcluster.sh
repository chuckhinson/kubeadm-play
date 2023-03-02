#!/bin/bash

set -euo pipefail

declare SSH_CONFIG_FILE="$(pwd)/ssh_config"

declare CONTROLLER_NODES
declare WORKER_NODES

function gatherClusterInfoFromTerraform () {

  echo "Gathering infrastructure info"

  CONTROLLER_NODES=()
  while read -r IP; do
    CONTROLLER_NODES+=("$IP")
  done <<< "$(terraform -chdir=./terraform output -json | jq -r '.controller_nodes.value')"

  WORKER_NODES=()
  while read -r IP; do 
    WORKER_NODES+=("$IP")
  done <<< "$(terraform -chdir=./terraform output -json | jq -r '.worker_nodes.value')"

}

function releaseVolumes () {

  kubectl delete pvc --all=true -A

}

function resetNodes () {

  local nodes=( "${WORKER_NODES[@]}" "${CONTROLLER_NODES[@]}" )

  for node in "${nodes[@]}"; do
    echo "resetting node $node"
    ssh -F "${SSH_CONFIG_FILE}" "$node" "sudo kubeadm reset --force"
  done

}


function main () {

  gatherClusterInfoFromTerraform
  releaseVolumes
  resetNodes

}


main "$@"
