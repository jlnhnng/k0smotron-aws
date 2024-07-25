# k0s on AWS with CAPI & k0smotron

This installation includes:
- k0s incl. k0smotron (v1.0.1)
- AWS Cloud Controller Manager 
- AWS EBS CSI Driver
- AWS EBS StorageClass

## Prep

Get and apply your AWS creds in the terminal, so we can use Terraform to create resources.

```
export AWS_REGION=eu-central-1
export AWS_ACCESS_KEY_ID=<your-access-key>
export AWS_SECRET_ACCESS_KEY=<your-secret-access-key>
export AWS_SESSION_TOKEN=<session-token> 
```

## Installation

### Create management cluster

```terraform init```

```terraform plan``` 

```terraform apply -auto-approve```

```terraform output -raw k0s_cluster | k0sctl apply --no-wait --debug --config -```

```terraform output -raw k0s_cluster | k0sctl kubeconfig --config -```

et voilà, a k0s cluster with 1 controller, 1 worker and integration into AWS via CCM and CSI.

### Option 1: Cluster API and k0smotron

#### Prereqs

Specificially for AWS you need the `clusterawsadm` CLI installed and use it to prepare your environment:

```
curl -L https://github.com/kubernetes-sigs/cluster-api-provider-aws/releases/download/v2.5.2/clusterawsadm-linux-amd64 -o clusterawsadm
chmod +x clusterawsadm
sudo mv clusterawsadm /usr/local/bin
clusterawsadm version
```

`clusterawsadm` will prepare your AWS account for CAPI and create IAM resources:
```
clusterawsadm bootstrap iam create-cloudformation-stack
```

Now the following command to ensure you have the credentials for your AWS account ready for ClusterAPI:
```export AWS_B64ENCODED_CREDENTIALS=$(clusterawsadm bootstrap credentials encode-as-profile)```

Now we can use `clusterctl` to install the ClusterAPI controller, the bootstrap & control-plane provider of k0smotron and the aws infrastructure provider:

> Make sure to have `kubectl` configured to point to your newly created management cluster.
```
clusterctl init --bootstrap k0sproject-k0smotron \
                --control-plane k0sproject-k0smotron \
                --infrastructure aws
```

You can check the pods in the namespaces `capi-system`, `k0smotron` and `capa-system`:
```
kubectl get pods -n capi-system && kubectl get pods -n k0smotron && kubectl get pods -n capa-system 
```

Now, ClusterAPI with k0smotron and AWS is configured and ready to use. 

#### Create a cluster

We have now prepared everything to create clusters. There are two ways to create clusters.
Either a cluster with Hosted Control Plane in the Management Cluster and Worker Nodes in AWS (or other infrastructure providers) OR a cluster with Control Plane and Worker Nodes in AWS (or other infrastructure providers).

You will find the two examples in the folder capa.

Just apply one of the manifests and see the cluster getting created.

> Please make sure to check the manifests and change whatever you need to adjust.

That's it. You now have a workload cluster created by k0smotron, capi and capa. 

### Option 2: k0smotron Standalone

You can use k0smotron to create k0s control planes without Cluster API and add worker nodes to it manually
:
``` yaml=
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
apiVersion: k0smotron.io/v1beta1
kind: Cluster
metadata:
  name: k0s-demo-cluster
  namespace: demo
spec:
  replicas: 1
  k0sImage: k0sproject/k0s
  k0sVersion: v1.30.2-k0s.0
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
Now, we can add Worker Nodes. To do that we will create a `JoinTokenRequest`:
``` yaml=
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
Let's get the token to add worker nodes:
```shell
kubectl get secret edge-token -n demo -o jsonpath='{.data.token}' | base64 -d
```

With the join token, we can install k0s on an external node that can live anywhere and add it to our cluster:
``` shell
curl -sSLf https://get.k0s.sh | sudo sh

sudo k0s install worker --token-file /path/to/token/file

sudo k0s start
```

That's it. You now have a Control Plane living in the management cluster and a worker node somewhere else. 
This architecture can be used for edge szenarios where you have limited resources and want to keep the control plane centrally. 