This project is for learning about kubeadm.

There are two components:
- packer - a hashicorp packer build for building a base image that can be used as the ami for the cluster nodes
  - This image has the container runtime, kubeadm, kubelet and kubectl installed
- terraform - a hashicorp terraform project for privisioning the network and compute infrastructure for a cluster.

Prereqs:
1. You will need an AWS keypair before you start
2. Terraform and packer both expect an AWS CLI profile name.  Make sure you have one defined with appropriate region and credentials in $HOME/.aws/config and $HOME/.aws/credentials.
3. Note that terraform has an issue where it does not use the region specified in your aws profile, so you will also need to provide the region in terraform.tfvars

Basic process is
1. Review the packer build template and the terraform tfvars to make sure things match up with the target enviornment
    1. `cp packer/containerd-ubuntu.auto.pkrvars.hcl.tmpl packer/containerd-ubuntu.auto.pkrvars.hcl`
    2. `vi packer/containerd-ubuntu.auto.pkrvars.hcl`
        1. provide appropriate values.  Note that commented out variables have 'reasonable' default values.  Check to make sure they're suitable for you environment
    2. `cp terraform/terraform.tfvars.tmpl terraform/terraform.tfvars`
    3. `vi terraform/terraform.tfvars`
        4. Provide appropriate values for you environment
        5. Note that remote_access_address is the IP address (as a /32 CIDR) of the machine you will be using to access the cluster (e.g., your laptop)
1. Build the base image AMI that your kubernetes nodes will use
    1. `packer init ./packer/`    (only need to do this the first time after cloning the repo)
    2. `packer build ./packer/`
1. Provision aws infrastrcuture
    1. `terraform -chdir=./terraform init` (only needed the first time you use the project)
    2. `terraform -chdir=./terraform apply`
    3. Capture jumpbox_public_ip for next step
1. Setup your ~/.ssh/conf to proxy through the jump box
    1. `cp ssh_config.tmpl ssh_config`
    1. `vi ssh_config.tmpl ssh_config`
        1. Be sure to update ProxyJump directive with jumpbox public IP address
        2. It may be necessary to do e.g., ssh-keygen -f "~/.ssh/known_hosts" -R "10.2.2.10" in the case where you're tearing down and recreating the cluster
    4. verify configuration by running `ssh -F ssh_config 10.2.2.10`
       1. You may need to run `ssh-keygen -f "$HOME/.ssh/known_hosts" -R "10.2.2.10` if you're recreating the cluster
1. Deploy k8s on first control-plane node
    1. run `ssh -F ./ssh_config 10.2.2.10 "sudo kubeadm init --kubernetes-version "1.26.0" --control-plane-endpoint $(terraform output -state terraform/terraform.tfstate -raw elb_dns_name):6443 --pod-network-cidr 10.2.128.0/20 --service-cidr 10.2.64.0/20 --upload-certs"`
    2. Substitute correct ip address for control-plane node (e.g., 10.2.2.10)
    3. change cidr blocks as appropriate
1. Capture the join commands for the control-plane and worker nodes from the kubadm init summary screen
1. In a separate terminal, setup kubectl on the intial controller node so you can monitor progress
    1. `ssh -F ssh_config 10.2.2.10` 
    2. `mkdir -p $HOME/.kube; sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config; sudo chown $(id -u):$(id -g) $HOME/.kube/config`
    1. `kubectl get nodes`
    2. `kubectl get pods -n kube-system`
    3. You may need to wait up to three minutes for the load balancer to get healthy before kubectl will respond reliably (the elb will round robin until at lease one target is healthy)
    4. Note that the node will be marked Not Ready until the CNI plugin is installed
    5. Note also that the coredns pods will be marked Pending until the CNI plugin is installed
1. 	Install the calico CNI plugin (run from control-plan node)
    2. `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml`
    2. wait for all pods to be in a Running state before continuing
1. Switch back to original (local) terminal window and add the rest of the controller nodes
    1.  Run join commands for second and third control-plane nodes
        1. e.g., `ssh -F ssh_config 10.2.2.11 "sudo $CONTROLLER_JOIN_CMD"` where CONTROLLER_JOIN_CMD is the join command for adding control-plane nodes as captured from the output of the kubeadm init command above
    1.  Run join commands to join worker nodes
        1. e.g., `ssh -F ssh_config 10.2.2.20 "sudo $WORKER_JOIN_CMD"` where WORKER_JOIN_CMD is the join command for adding worker nodes as captured from the output of the kubeadm init command above


I found the following resources helpful while figuring all of this out:

- https://github.com/containerd/containerd/blob/main/docs/getting-started.md
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- https://k8s-school.fr/resources/en/blog/kubeadm/
- https://devopscube.com/setup-kubernetes-cluster-kubeadm/
- https://joshrosso.com/docs/2019/2019-03-26-ha-control-plane-kubeadm/
