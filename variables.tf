variable "cluster_name" {
  type    = string
  default = "k0smotron-cluster"
}

variable "controller_count" {
  type    = number
  default = 3
}

variable "controller_flavor" {
  type    = string
  default = "m5.xlarge"
}

variable "worker_count" {
  type    = number
  default = 3
}

variable "worker_flavor" {
  type    = string
  default = "m5.xlarge"
}

variable "cluster_region" {
  type    = string
  default = "eu-central-1"
}

variable "iam_instance_profile" {
  type    = string
  default = "presales-cluster_host"
}