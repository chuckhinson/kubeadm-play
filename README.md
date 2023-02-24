This project is for learning how to deploy a k8s cluster with kubeadm.

## Before you Start
This process is intended to be run from a linux machine.  You will need to have the following available on your machine:
1. Software
    1. Git
    3. Packer
    4. Terraform
    5. AWS CLI
2. AWS Credentials
    1. You'll need an AWS profile configured with an appropriate access key/secret key and the aws region where the cluster is to be deployed  (~/.aws/config and ~/.aws/credentials)
    2. You'll also need an Key Pair in the region where you'll be provisioning the cluster
3. Externally visible IP address of the machine you'll be using to do the provisioning (e.g., your laptop)
    1. https://www.whatsmyip.org/


## Build Your Cluster

The process is essentially;
- using HashiCorp Packer, build an AMI to be used by the cluster nodes
- using HashiCorp Terrform, provision the AWS infrastructure on which the node will be deployed
- using kubeadm, deploy the cluster

### Configure the project for the target environment
1. `cp packer/containerd-ubuntu.auto.pkrvars.hcl.tmpl packer/containerd-ubuntu.auto.pkrvars.hcl`
1. `vi packer/containerd-ubuntu.auto.pkrvars.hcl`
    1. provide appropriate values.  Note that commented out variables have 'reasonable' default values.  Check to make sure they're suitable for you environment
1. `cp terraform/terraform.tfvars.tmpl terraform/terraform.tfvars`
1. `vi terraform/terraform.tfvars`
    1. Provide appropriate values for you environment
    1. Be sure to pick a unique cluster name to make it easy to distinguish the resources for your cluster from the resources for someone else's cluster
    1. Note that remote_access_address is the IP address (as a /32 CIDR) of the machine you will be using to access the cluster (e.g., your laptop)
1. `cp ssh_config.tmpl ssh_config`
1. `vi ssh_config`
    1. Provide the filename for the ssh key for your ec2 instances (i.e., the AWS Key Pair)
    2. (You'll need to wait until after you provision your infrastructue to fill in the jumpbox IP)
        
### Build the AMI that your kubernetes nodes (ec2 isntances) will use
1. `packer init ./packer/`    (only need to do this the first time after cloning the repo)
1. `packer build ./packer/`

### Provision aws infrastrcuture
1. `terraform -chdir=./terraform init` (only needed the first time you use the project)
1. `terraform -chdir=./terraform apply`
1. Capture jumpbox_public_ip from terrform output for next step

### Update you ssh configuration
1. `vi ssh_config`
    1. update the jumpbox Hostname with the jumpbox public IP address (captured in the previous step)
1. verify configuration by running `ssh -F ssh_config 10.2.2.10 "ls /tmp"`
   1. You may need to run `ssh-keygen -f "$HOME/.ssh/known_hosts" -R "10.2.2.10"` if you're recreating the cluster

### Deploy the cluster
1. Deploy k8s on first control-plane node
    1. run `ssh -F ./ssh_config 10.2.2.10 "sudo kubeadm init --kubernetes-version "1.26.0" --control-plane-endpoint $(terraform output -state terraform/terraform.tfstate -raw elb_dns_name):6443 --pod-network-cidr 10.2.128.0/20 --service-cidr 10.2.64.0/20 --upload-certs"`
1. Capture the join commands for the control-plane and worker nodes from the kubadm init summary screen
1. In a separate terminal window, setup kubectl on the intial controller node so you can monitor progress
    1. `ssh -F ssh_config 10.2.2.10` 
    1. `mkdir -p $HOME/.kube; sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config; sudo chown $(id -u):$(id -g) $HOME/.kube/config`
    1. `kubectl get nodes`
    1. `kubectl get pods -n kube-system`
    1. You may need to wait up to three minutes for the load balancer to get healthy before kubectl will respond reliably (the elb will round robin until at lease one target is healthy)
    1. Note that the node will be marked Not Ready until the CNI plugin is installed
    1. Note also that the coredns pods will be marked Pending until the CNI plugin is installed
1. 	Install the calico CNI plugin (run from control-plan node)
    1. `kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/master/manifests/calico.yaml`
    1. wait for all pods to be in a Running state before continuing
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
