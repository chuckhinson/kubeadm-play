This project is for learning about kubeadm.

There are two components:
- packer - a hashicorp packer build for building a base image that can be used as the ami for the cluster nodes
- terraform - a hashicorp terraform project for privisioning the network and compute infrastructure for a cluster.

Basic process is
1. Review the packer build template and the terraform tfvars to make sure things match up with the target enviornment
    1. You will need an AWS keypair before you start
    2. You will need to setup your AWS credentials in $HOME/.aws/credentials
    3. You will need a profile setup in $HOME/.aws/config and credentials set up appropriately
2. Run `packer build containerd-ubuntu.pkr.hcl` to build the base image that the cluster nodes will use
2. Run `terraform apply` (or `terraform plan` as appropriate)
3. ssh into the jump box (find public IP in aws console)
4. setup your private key in .ssh/id_rsa
5. ssh to first control-plane node
    1. run `sudo kubeadm init --kubernetes-version "1.26.0" --control-plane-endpoint kubeadm-api-e993cd27451095b3.elb.us-east-2.amazonaws.com:6443 --pod-network-cidr 10.2.128.0/20 --service-cidr 10.2.64.0/20 --upload-certs`
    2. change the name of the elb as appropriate
6. 	Install the calico CNI plugin
    1. `kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml` 
7.  Capture the join commands for the controllers and workers from the kubadm summary screen
7.  ssh to second and third control-plane nodes and run the join commands
8.  ssh to worker nodes and run worker join commands