variable "cluster_name" {
  type    = string
  default = "k0smotron-cluster"
}

variable "controller_count" {
  type    = number
  default = 3
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "cluster_flavor" {
  type    = string
  default = "m5.xlarge"
}
