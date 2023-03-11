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
declare CLUSTER_NAME


declare CLUSTER_INIT_CONFIG_TMPL=$(cat <<'EOF'
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
apiServer:
  extraArgs:
    cloud-provider: external
clusterName: ${CLUSTER_NAME}
controlPlaneEndpoint: "${ELB_NAME}:6443"
controllerManager:
  extraArgs:
    cloud-provider: external
kubernetesVersion: v1.26.0 # can use "stable"
networking:
  dnsDomain: cluster.local
  podSubnet: 10.2.128.0/20
  serviceSubnet: 10.2.64.0/20
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
certificateKey: "${CERT_KEY}"
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
patches:
  directory: /home/ubuntu/patches
EOF
)

declare CONTROLLER_JOIN_CONFIG_TMPL=$(cat <<'EOF'
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  file:
    kubeConfigPath: /home/ubuntu/kubeconfig
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
controlPlane:
  certificateKey: "${CERT_KEY}"
patches:
  directory: /home/ubuntu/patches
EOF
)

declare WORKER_JOIN_CONFIG_TMPL=$(cat <<'EOF'
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: JoinConfiguration
discovery:
  file:
    kubeConfigPath: /home/ubuntu/kubeconfig
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
patches:
  directory: /home/ubuntu/patches
EOF
)

declare KUBECONIFG_PATCH_SCRIPT=$(cat <<'EOF'
INSTANCE_AZ="$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)"
INSTANCE_ID="$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
PROVIDER_ID="aws:///${INSTANCE_AZ}/${INSTANCE_ID}"

mkdir -p patches
cat > ./patches/kubeletconfiguration.yaml <<< "providerID: $PROVIDER_ID"
EOF
)


function gatherClusterInfoFromTerraform () {

  echo "Gathering infrastructure info"

  CLUSTER_NAME=$(terraform -chdir=./terraform output -json | jq -r '.cluster_name.value')
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

  local init_config=$(export CLUSTER_NAME ELB_NAME CERT_KEY ; envsubst <<< "$CLUSTER_INIT_CONFIG_TMPL")
  ssh -F "${SSH_CONFIG_FILE}" "${CONTROLLER_NODES[0]}" "cat >kubeadm.config"  <<< "$init_config"

  ssh -F ssh_config "${CONTROLLER_NODES[0]}" "bash -s" <<< "$KUBECONIFG_PATCH_SCRIPT"

  local cmd="sudo kubeadm init --config ./kubeadm.config --upload-certs"
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

  local join_config="$(export CERT_KEY; envsubst <<< "$CONTROLLER_JOIN_CONFIG_TMPL")"

  for ip in "${CONTROLLER_NODES[@]:1}"; do
    echo "Joining controller $ip"

    # Copy kubeconfig to node
    scp -F "${SSH_CONFIG_FILE}" "${ADMIN_CONF_FILE}" "${ip}:~/kubeconfig"

    # Create kubeadm controller join config file
    ssh -F ssh_config "$ip" "cat - > ./kubeadm.config" <<< "$join_config"

    # Create kubletconfig patch file
    ssh -F ssh_config "$ip" "bash -s" <<< "$KUBECONIFG_PATCH_SCRIPT"

    # join cluster
    ssh -F "${SSH_CONFIG_FILE}" "$ip" "sudo kubeadm join --config ./kubeadm.config"
  done

}

function addWokerNodes () {

  echo "Adding worker nodes"

  for ip in "${WORKER_NODES[@]}"; do
    echo "Joining worker $ip"

    # Copy kubeconfig to node
    scp -F "${SSH_CONFIG_FILE}" "${ADMIN_CONF_FILE}" "${ip}:~/kubeconfig"

    # Create kubeadm worker join config file
    ssh -F ssh_config "$ip" "cat - > ./kubeadm.config" <<< "$WORKER_JOIN_CONFIG_TMPL"

    # Create kubadm patch file
    ssh -F ssh_config "$ip" "bash -s" <<< "$KUBECONIFG_PATCH_SCRIPT"

    # join cluster
    ssh -F "${SSH_CONFIG_FILE}" "$ip" "sudo kubeadm join --config ./kubeadm.config"
  done

}

function main () {

  gatherClusterInfoFromTerraform
  buildSshConfigFile
  buildKnownHostsFile
  initPrimaryController
  setupKubectl
  waitForElbToBecomeHealthy
  installCalicoCNI
  ./deploy-aws-cloudprovider.sh
  addSecondaryControllers
  addWokerNodes  
}


main "$@"