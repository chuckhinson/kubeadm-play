#!/bin/bash

set -euo pipefail

declare KNOWN_HOSTS_FILE="$(pwd)/known_hosts"
declare SSH_CONFIG_FILE="$(pwd)/ssh_config"
declare SSH_CONFIG_FILE_TEMPLATE="$(pwd)/ssh_config.tmpl"
declare KEY_FILE="$HOME/.ssh/k8schuck_rsa"

declare BASTION_IP
declare CONTROLLER_NODES
declare WORKER_NODES

function gatherClusterInfoFromTerraform () {

  echo "Gathering infrastructure info"

  BASTION_IP=$(terraform -chdir=./terraform output -json | jq -r '.jumpbox_public_ip.value')

  CONTROLLER_NODES=()
  while read -r IP; do
    CONTROLLER_NODES+=("$IP")
  done <<< "$(terraform -chdir=./terraform output -json | jq -r '.controller_nodes.value')"

  WORKER_NODES=()
  while read -r IP; do 
    WORKER_NODES+=("$IP")
  done <<< "$(terraform -chdir=./terraform output -json | jq -r '.worker_nodes.value')"

}

function buildSshConfigFile () {
  
  echo "Building ssh_config"

  ( export BASTION_IP KEY_FILE KNOWN_HOSTS_FILE ; \
    cat "${SSH_CONFIG_FILE_TEMPLATE}" | envsubst > ${SSH_CONFIG_FILE} )

}

function buildKnownHostsFile () {

  echo "Bulding known hosts file"

  ssh-keyscan "${BASTION_IP}" 2> /dev/null > "${KNOWN_HOSTS_FILE}"

  local IPS=("${CONTROLLER_NODES[@]}" "${WORKER_NODES[@]}")
  ssh -F "${SSH_CONFIG_FILE}" "${BASTION_IP}" "ssh-keyscan ${IPS[*]}" 2> /dev/null >> "$KNOWN_HOSTS_FILE"

}


function main () {

  gatherClusterInfoFromTerraform
  buildSshConfigFile
  buildKnownHostsFile
  
}


main "$@"