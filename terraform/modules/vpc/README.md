Terraform module for creating a base vpc that contains a jumpbox (that is publicly accessible).

The VPC will have the following components
- The VPC
- InternetGateway
- NAT Gateway (optional)
- A prublic subnet
- A jumpbox