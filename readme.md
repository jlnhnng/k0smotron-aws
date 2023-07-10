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


## Next

Next, you can use k0smotron to create k0s control planes:
``` yaml=
apiVersion: k0smotron.io/v1beta1
kind: Cluster
metadata:
  name: k0s-demo-cluster
  namespace: demo
spec:
  replicas: 1
  k0sImage: k0sproject/k0s
  k0sVersion: v1.27.3-k0s.0
  service:
    type: LoadBalancer
    apiPort: 6443
    konnectivityPort: 8132
  persistence:
    type: emptyDir
```
To get kubeconfig of the newly created Control Plane, we execute the following command:
``` shell
kubectl get secret k0s-demo-cluster-kubeconfig -n demo -o jsonpath='{.data.value}' | base64 -d > ~/.kube/child.conf
```
Now, we want to add Worker Nodes. To do that we will create a `JoinTokenRequest`:
``` yaml=
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
apiVersion: k0smotron.io/v1beta1
kind: JoinTokenRequest
metadata:
  name: edge-token
  namespace: demo
spec:
  clusterRef:
    name: k0s-demo-cluster
    namespace: demo
```
Let's get the token to add worker nodes.:
```shell
kubectl get secret edge-token -n demo -o jsonpath='{.data.token}' | base64 -d
```

With the join token, we can install k0s on an external node and add it to our cluster:
``` shell
curl -sSLf https://get.k0s.sh | sudo sh

sudo k0s install worker --token-file /path/to/token/file

sudo k0s start
```

### ClusterAPI
Since this is only half the solution and we don't want to manually create VMs for k0s workers, there is a close integration between k0smotron and ClusterAPI.
You can find a detailed guide on how this works [here](https://docs.k0smotron.io/v0.4.2/cluster-api/).


### TODO
- Make AMI configurable
- Add Loadbalancer