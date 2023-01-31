A Hashicorp packer project for creating a AMI suitable for use as a base image for a kubenetes cluster

The produced AMI is ubuntu jammy (22.04) with containerd installed and configured along with kubeadm, kubelet and kubectl install.

Note that the AMI name has a timestamp appended to it, so everytime packer build is run, a new AMI will be added to the account.


