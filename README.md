This project is for learning about kubeadm.

There are two components:
- packer - a hashicorp packer build for building a base image that can be used as the ami for the cluster nodes
- terraform - a hashicorp terraform project for privisioning the network and compute infrastructure for a cluster.

Basic process is
1. Review the packer build template and the terraform tfvars to make sure things match up with the target enviornment
    1. You will need an AWS keypair before you start
    2. Terraform and packer both expect an AWS CLI profile name.  Make sure you have one defined with appropriate region and credentials in $HOME/.aws/config and $HOME/.aws/credentials
2. Run `packer build containerd-ubuntu.pkr.hcl` to build the base image that the cluster nodes will use
2. Run `terraform apply` (or `terraform plan` as appropriate)
3. ssh into the jump box (find public IP in aws console)
4. setup your private key in .ssh/id_rsa
5. ssh to first control-plane node
    1. run `sudo kubeadm init --kubernetes-version "1.26.0" --control-plane-endpoint kubeadm-api-e993cd27451095b3.elb.us-east-2.amazonaws.com:6443 --pod-network-cidr 10.2.128.0/20 --service-cidr 10.2.64.0/20 --upload-certs`
    2. change the name of the elb as appropriate
    3. change cidr blocks as appropriate
9. Capture the join commands for the controllers and workers from the kubadm summary screen
6. setup kubectl admin kubeconfig for local user
7. Check the controller node is working 
    1. run `kubectl get nodes`
    2. run `kubectl get pods -n kube-system`
    3. You may need to wait close to three minutes for the load balancer to get healthy before kubectl will respond reliably (the elb will round robin until at lease one target is healthy)
    4. Note that the node will be marked Not Ready until the CNI plugin is installed
    5. Note also that the coredns pods will be marked Pending until the CNI plugin is installed
8. 	Install the calico CNI plugin
    1. `kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml` 
9.  ssh to second and third control-plane nodes and run the join commands
9.  ssh to worker nodes and run worker join commands


I found the following resources helpful while figuring all of this out:

- https://github.com/containerd/containerd/blob/main/docs/getting-started.md
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- https://k8s-school.fr/resources/en/blog/kubeadm/
- https://devopscube.com/setup-kubernetes-cluster-kubeadm/
- https://joshrosso.com/docs/2019/2019-03-26-ha-control-plane-kubeadm/