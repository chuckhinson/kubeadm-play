#!/bin/bash

set -euo pipefail

sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
   https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

KUBE_VERSION=1.26.0-00

sudo apt-get update
sudo apt-get install -y \
    kubelet="${KUBE_VERSION}" \
    kubeadm="${KUBE_VERSION}" \
    kubectl="${KUBE_VERSION}" 
sudo apt-mark hold kubelet kubeadm kubectl
