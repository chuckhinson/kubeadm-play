variable "cluster_name" {
  nullable = false
  type = string
  description = "The cluster name - will be used in the names of all resources.  This must be the cluster name as provided to kubespray in order for the cloud-controller manager to work properly"
}
