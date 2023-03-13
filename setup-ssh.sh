#!/bin/bash

set -euo pipefail

# Script for setting up ssh connectivity.  Sets up a ssh configuration for a proxy host (jumpbox)
# so that you can ssh directly into any of the servers in the environment
# using 'ssh -F ssh_config $SERVER_IP'  where SERVER_IP is the ip address of any server in the
# target environment.
# The script fetches that ssh private key from terraform and generates a local key file, ssh config
# file and a known hosts file (to avoid the prompt for trusting host keys on first connect)
#
# NOTE: This approach is only suitable for temporary environments used for experimentation; it would
# not be suitable for any kind of production environment

declare BASTION_IP
declare CONTROLLER_NODES
declare WORKER_NODES

declare KNOWN_HOSTS_FILE="$(pwd)/known_hosts"
declare SSH_CONFIG_FILE="$(pwd)/ssh_config"
declare KEY_FILE="$(pwd)/ssh_key.pem"

declare SSH_CONFIG_TMPL=$(cat <<'EOF'
# Sample ssh config file to enable ssh proxy via jumpbox
# With this setup, you should be able to e.g., ssh -F ssh_config 10.2.2.10 to ssh into a k8s node

UserKnownHostsFile $KNOWN_HOSTS_FILE
IdentityFile $KEY_FILE

Host jumpbox $BASTION_IP
   HostName $BASTION_IP
   User ubuntu

Host 10.2.2.*
   User ubuntu
   ProxyJump jumpbox
EOF
)

function gatherClusterInfoFromTerraform () {

  echo "Gathering infrastructure info"

  BASTION_IP=$(terraform -chdir=./terraform output -json | jq -r '.jumpbox_public_ip.value')

  terraform -chdir=./terraform output -json | jq -r '.ssh_private_key.value' > "$KEY_FILE"
  chmod 0600 "$KEY_FILE"

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

  ( export BASTION_IP KEY_FILE KNOWN_HOSTS_FILE ; envsubst > "${SSH_CONFIG_FILE}" <<< "$SSH_CONFIG_TMPL" )

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