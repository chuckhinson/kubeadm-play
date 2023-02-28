#!/bin/bash

set -euo pipefail

declare KNOWN_HOSTS_FILE="$(pwd)/known_hosts"
declare SSH_CONFIG_FILE="$(pwd)/ssh_config"
declare SSH_CONFIG_FILE_TEMPLATE="$(pwd)/ssh_config.tmpl"
declare KEY_FILE="$HOME/.ssh/k8schuck_rsa"
declare ADMIN_CONF_FILE=$(pwd)/cluster_admin.conf

declare BASTION_IP
declare CONTROLLER_NODES
declare WORKER_NODES
declare ELB_NAME
declare CERT_KEY

function gatherClusterInfoFromTerraform () {

  echo "Gathering infrastructure info"

  ELB_NAME=$(terraform -chdir=./terraform output -json | jq -r '.elb_dns_name.value')
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

function initPrimaryController () {

  CERT_KEY=$(ssh -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}" "sudo kubeadm certs certificate-key")

  local cmd="sudo kubeadm init --kubernetes-version \"1.26.0\" --control-plane-endpoint ${ELB_NAME}:6443 --pod-network-cidr 10.2.128.0/20 --service-cidr 10.2.64.0/20 --certificate-key $CERT_KEY --upload-certs"
  echo "$cmd"

  ssh -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}" "$cmd"

}

function setupKubectl () {

  echo "Setting up kubectl config"

  local cmd='mkdir -p $HOME/.kube; sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config; sudo chown $(id -u):$(id -g) $HOME/.kube/config'
  ssh -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}" "$cmd"

  scp -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}:~/.kube/config" "${ADMIN_CONF_FILE}"

  echo "For local kubectl access, 'export KUBECONFIG=${ADMIN_CONF_FILE}'"

}

function waitForElbToBecomeHealthy () {
  # All kubernetes API request go through the load balancer.  Until at least one elb target
  # (i.e., a control-plane node) is marked healthy, requests are round-robined across all elb
  # targets (some of which may be pointing to nodes that dont yet have the api server installed).
  # With only the first control-plane node initialized, two of every three api requests will fail.
  # To help prevent problems resulting from failed requests, we want to wait until
  # the first elb target becaomes healthy (by default, it take 5 consecutive successful
  # health checks for a target to be marked healty, and health check)

  printf "\nWaiting for at least one ELB target to get healthy.\n"
  printf "This could take up to three minutes\n"
  local success_count=0
  until [ $success_count -gt 3 ]; do
    if  kubectl --kubeconfig="${ADMIN_CONF_FILE}" get --raw='/readyz' 2> /dev/null ; then
      # see https://askubuntu.com/questions/1379923/increment-operator-does-not-work-on-a-variable-if-variable-is-set-to-0
      ((success_count+=1))
    else
      success_count=0
      printf "."
    fi
    sleep 5
  done

}

function installCalicoCNI () {

  echo "Installing Calico CNI"
  kubectl --kubeconfig="${ADMIN_CONF_FILE}" apply -f https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml

}


function addSecondaryControllers () {

  echo "Adding remaining control plane nodes"
  local cmd="sudo kubeadm token create --print-join-command --certificate-key ${CERT_KEY}"
  local join=$(ssh -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}" "$cmd")
  echo "$join"

  for ip in "${CONTROLLER_NODES[@]:1}"; do
    echo "Joining controller $ip"
    ssh -F "${SSH_CONFIG_FILE}" "$ip" "sudo $join"
  done

}

function addWokerNodes () {

  local cmd="sudo kubeadm token create --print-join-command"
  local join=$(ssh -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}" "$cmd")
  echo "$join"

  for ip in "${WORKER_NODES[@]}"; do
    echo "Joining worker $ip"
    ssh -F "${SSH_CONFIG_FILE}" "$ip" "sudo $join"
  done


}

function main () {

  gatherClusterInfoFromTerraform
  buildSshConfigFile
  buildKnownHostsFile
  initPrimaryController
  addSecondaryControllers
  setupKubectl
  waitForElbToBecomeHealthy
  installCalicoCNI
  addWokerNodes  
}


main "$@"