A Hashicorp packer project for creating a AMI suitable for use as
a base image for a kubenetes cluster

The produced AMI is essentially ubuntu jammy (22.04) with containerd installed.

Note that the AMI name has a timestamp appended to it, so everytime packer build is run, a new AMI will be added to the account.


