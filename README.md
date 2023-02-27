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
    1. provide appropriate values.  Note that commented-out variables have 'reasonable' default values.  Check to make sure they're suitable for you environment
1. `cp terraform/terraform.tfvars.tmpl terraform/terraform.tfvars`
1. `vi terraform/terraform.tfvars`
    1. Provide appropriate values for you environment
    1. Be sure to pick a unique cluster name to make it easy to distinguish the resources for your cluster from the resources for someone else's cluster
    1. Note that remote_access_address is the IP address (as a /32 CIDR) of the machine you will be using to access the cluster (e.g., your laptop)
       1. You can use `curl ifconfig.me` 
        
### Build the AMI that your kubernetes nodes (ec2 isntances) will use
1. `packer init ./packer/`    (only need to do this the first time after cloning the repo)
1. `packer build ./packer/`

### Provision aws infrastrcuture
1. `terraform -chdir=./terraform init` (only needed the first time you use the project)
1. `terraform -chdir=./terraform apply`

### Deploy the cluster
1. Check mkcluster.sh to ensure KEY_FILE file is set the location of your ssh private key for the target envrionment
1. `./mkcluster.sh`
1. `export KUBECONFIG=$(pwd)/cluster_admin.conf`
1. `kubectl get nodes`

You can also now use `ssh -F ssh_config 10.2.2.x` to ssh into your cluster nodes


## Dashboard
### Install
1. `deploy-dashboard.sh`

### Access
  - `kubectl -n kubernetes-dashboard create token admin-user`
  - `sudo kubectl port-forward service/kubernetes-dashboard -n kubernetes-dashboard --kubeconfig $(pwd)/cluster_admin.conf 443:443`
  - goto https://localhost/ and login
    - select Token and paste in token from above


### Resources
I found the following resources helpful while figuring all of this out:

- https://github.com/containerd/containerd/blob/main/docs/getting-started.md
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/
- https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
- https://k8s-school.fr/resources/en/blog/kubeadm/
- https://devopscube.com/setup-kubernetes-cluster-kubeadm/
- https://joshrosso.com/docs/2019/2019-03-26-ha-control-plane-kubeadm/
