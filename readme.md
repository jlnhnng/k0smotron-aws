# k0s on AWS with k0smotron

This installation includes:
- k0s incl. k0smotron (v0.4.2)
- AWS Cloud Controller Manager
- AWS EBS CSI Driver
- AWS EBS StorageClass

## Prep

Get and apply your AWS creds in the terminal, so we can use Terraform to create resources. 

## Installation

```terraform init```

```terraform apply -auto-approve```

```terraform output -raw k0s_cluster | k0sctl apply --no-wait --debug --config -```

```terraform output -raw k0s_cluster | k0sctl kubeconfig --config -```

et voilà, a k0s cluster with 1 controller, 1 worker, integration into AWS and k0smotron.


### TODO
- Make AMI configurable
- Add Loadbalancer