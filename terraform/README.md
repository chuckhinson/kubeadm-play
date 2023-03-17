A Hashicorp terrform progect for provisioning the network and compute infrasctructure for the cluster

Note that the terraform project references a base AMI created by the packer project for use as the base image for the cluster nodes.  

The project creates the following resources
1. A VPC (should be at least a /22 CIDR block)
    1. You can specify an existing vpc or have a new one created
2. An internet gateway (IGW)
3. A public subnet (the first /24 subnet of the vpc CIDR block)
    1. A NAT gatweway
    2. A network load balancer for the k8s apiserver
    2. EC2 instance to serve as a jumpbox
4. A private subnet (the second /24 subnet of the vpc CIDR block)
    1. 3 EC2 instances for the control-plane
    2. 3 EC2 instances for the worker nodes
    3. Note that the EC2 instances are created from the AMI created by the packer module
5. Security Group for the jumpbox allowing remote ssh access
6. Security group for the cluster nodes only allowing access from withing the vpc
7. Route tables for the public and private subnets