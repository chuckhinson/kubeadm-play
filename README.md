This project is for learning about kubeadm.

There are two components:
- packer - a hashicorp packer build for building a base image that can be used as the ami for the cluster nodes
  - This image has the container runtime, kubeadm, kubelet and kubectl installed
- terraform - a hashicorp terraform project for privisioning the network and compute infrastructure for a cluster.

Basic process is
1. Review the packer build template and the terraform tfvars to make sure things match up with the target enviornment
    1. You will need an AWS keypair before you start
    2. Terraform and packer both expect an AWS CLI profile name.  Make sure you have one defined with appropriate region and credentials in $HOME/.aws/config and $HOME/.aws/credentials
1. Run `packer build containerd-ubuntu.pkr.hcl` to build the base image that the cluster nodes will use
    1. (Run `packer init` first if you've just checked out the repo)
1. Provision aws infrastrcuture
    1. Run `terraform -chdir=./terraform init` (only needed the first time you use the project)
    2. Run `terraform -chdir=./terraform apply` 
    3. Be sure to capture elb_dns_name and jumpbox_public_ip values for use below
1. Setup your ~/.ssh/conf to proxy through the jump box
    1. Use content from ssh_config.tmpl
    2. Be sure to update ProxyJump directive with jumpbox public IP address
    3. It may be necessary to do e.g., ssh-keygen -f "/home/chinson/.ssh/known_hosts" -R "10.2.2.10" in the case where you're tearing down and recreating the cluster
1. Deploy k8s on first control-plane node
    1. run `ssh 10.2.2.10 "sudo kubeadm init --kubernetes-version "1.26.0" --control-plane-endpoint $(terraform output -state terraform/terraform.tfstate -raw elb_dns_name):6443 --pod-network-cidr 10.2.128.0/20 --service-cidr 10.2.64.0/20 --upload-certs"`
    2. Substitute correct ip address for control-plane node (e.g., 10.2.2.10)
    3. change cidr blocks as appropriate
1. Capture the join commands for the control-plane and worker nodes from the kubadm init summary screen
1. ssh into inital control-plane node and setup kubectl admin kubeconfig (use separate terminal window)
    2. relevant commands are found in the output of the kubeadm init command
1. Check the controller node is working
    1. run `kubectl get nodes`
    2. run `kubectl get pods -n kube-system`
    3. You may need to wait up to three minutes for the load balancer to get healthy before kubectl will respond reliably (the elb will round robin until at lease one target is healthy)
    4. Note that the node will be marked Not Ready until the CNI plugin is installed
    5. Note also that the coredns pods will be marked Pending until the CNI plugin is installed
1. 	Install the calico CNI plugin (run from control-plan node)
    1. `kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml`
    2. wait for all pods to be in a Running state before continuing
1.  Run join commands (locally) for second and third control-plane nodes
    1. e.g., `ssh 10.2.2.11 "sudo $CONTROLLER_JOIN_CMD"` where CONTROLLER_JOIN_CMD is the join command for adding control-plane nodes as captured from the output of the kubeadm init command above
1.  Run join commands (locally) to join worker nodes
    1. e.g., `ssh 10.2.2.11 "sudo $WORKER_JOIN_CMD"` where WORKER_JOIN_CMD is the join command for adding worker nodes as captured from the output of the kubeadm init command above


I found the following resources helpful while figuring all of this out:

- https://github.com/containerd/containerd/blob/main/docs/getting-started.md
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- https://k8s-school.fr/resources/en/blog/kubeadm/
- https://devopscube.com/setup-kubernetes-cluster-kubeadm/
- https://joshrosso.com/docs/2019/2019-03-26-ha-control-plane-kubeadm/
