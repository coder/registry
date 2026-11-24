# Cluster setup for kubernetes-substrate

A cluster administrator does this once. It installs Agent Substrate in its own cluster, runs coder-bridge there, and gives the Coder provisioner a namespace in the Coder cluster. These are the steps we ran, with Substrate on a kind cluster on one EC2 host next to an EKS cluster that runs Coder. Replace the values in angle brackets.

## Files

| Path                                                               | What it is                                                                                 |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| [`coder-cluster.yaml`](coder-cluster.yaml)                         | Coder cluster: the namespace, RBAC for the provisioner, a read-only token for coder-bridge |
| [`substrate-cluster.yaml`](substrate-cluster.yaml)                 | Substrate cluster: the worker pool, coder-bridge, and its NetworkPolicy                    |
| [`actor-template.yaml`](actor-template.yaml)                       | Substrate actor template for workspaces                                                    |
| [`access-policy.yaml`](access-policy.yaml)                         | Lets coder-bridge manage actors in the `coder` atespace                                    |
| [`../bridge/cmd/coder-boot`](../bridge/cmd/coder-boot/main.go)     | Main process of the actor                                                                  |
| [`../bridge/cmd/coder-bridge`](../bridge/cmd/coder-bridge/main.go) | TLS front, token broker, and controller                                                    |
| [`../build/Dockerfile`](../build/Dockerfile)                       | Workspace image                                                                            |
| [`../build/Dockerfile.bridge`](../build/Dockerfile.bridge)         | coder-bridge image                                                                         |

The Go module in `bridge/` uses only the standard library.

## 1. The host

- A VM with nested virtualization on, such as an `m7i.2xlarge` (8 vCPU, 32 GiB) with a 250 GB disk. Substrate keeps snapshots on the same disk as the images.
- In the same network as the Coder cluster. Allow all traffic from the Coder cluster's nodes, and SSH only from your IP address.
- Docker with buildx, Go, and `kubectl`.

## 2. Agent Substrate

```sh
git clone https://github.com/agent-substrate/substrate && cd substrate
git checkout v0.6.0
hack/create-kind-cluster.sh
ATE_INGRESS_ALLOWED_SPIFFE_IDS=spiffe://cluster.local/ns/coder-bridge/sa/bridge \
  hack/install-ate-kind.sh deploy ate-system --credential-provider='{"name":"k8s.io"}'
NO_DEV_ENV=true KO_DOCKER_REPO=localhost:5001 KUBECTL_CONTEXT=kind-kind \
  ATE_INSTALL_KIND=true BUCKET_NAME=ate-snapshots \
  hack/install-microvm-deps.sh --install
go install ./cmd/kubectl-ate
```

`ATE_INGRESS_ALLOWED_SPIFFE_IDS` lets coder-bridge call the Substrate API. The microVM step builds the Cloud Hypervisor worker image and pushes it to the local registry on port 5001.

## 3. The Coder cluster

```sh
kubectl apply -f coder-cluster.yaml
kubectl -n coder-substrate get secret coder-bridge-token -o jsonpath='{.data.token}' | base64 -d > token
kubectl -n coder-substrate get secret coder-bridge-token -o jsonpath='{.data.ca\.crt}' | base64 -d > ca.crt
```

The Role lets the `coder` ServiceAccount in the `coder` namespace, which the provisioner uses, manage ConfigMaps and Secrets in `coder-substrate` only. Change the subject if your provisioner uses another ServiceAccount. coder-bridge gets read access to the same namespace.

## 4. Certificates

The egress gateway passes raw bytes only for a `tlsPassthrough` rule, which matches a host name. The Coder agent needs WebSocket, which an `http` rule blocks. So coder-bridge serves TLS for `coder.substrate.internal` with a certificate from its own CA, and copies the bytes to the Coder server.

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 365 \
  -subj '/CN=coder-bridge CA' -keyout bridge-ca.key -out bridge-ca.crt
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
  -subj '/CN=coder.substrate.internal' -keyout tls.key -out tls.csr
printf 'subjectAltName=DNS:coder.substrate.internal\n' > ext.cnf
openssl x509 -req -in tls.csr -CA bridge-ca.crt -CAkey bridge-ca.key -CAcreateserial -days 365 \
  -extfile ext.cnf -out tls.crt
```

Keep the keys out of Git.

## 5. Images

Build both images on the host from the template directory, and push them to `localhost:5001`. Copy `kubectl-ate` into the template directory first for the bridge image.

```sh
docker build -f build/Dockerfile --build-arg BASE= image \
  BRIDGE_CA="$(cat bridge-ca.crt)" -t localhost:5001/coder-workspace:v1 . < base > --build-arg
docker build -f build/Dockerfile.bridge -t localhost:5001/coder-bridge:v1 .
docker push localhost:5001/coder-workspace:v1
docker push localhost:5001/coder-bridge:v1
```

The base image must have the Coder agent at `/usr/local/bin/coder`, at your Coder server's version, and a `coder` user with UID 1000. Use image digests in the manifests, not tags.

## 6. The Substrate cluster

```sh
kubectl create namespace coder-bridge
kubectl -n coder-bridge create secret generic coder-kube --from-file=token --from-file=ca.crt
kubectl -n coder-bridge create secret tls coder-bridge-tls --cert=tls.crt --key=tls.key
sed -e 's#WORKER_IMAGE_MICROVM#<worker image from step 2>#' \
  -e 's#BRIDGE_IMAGE#<bridge image>#' \
  -e 's#CODER_UPSTREAM#<Coder host>:<port>#' \
  -e 's#CODER_KUBE_API#<Coder cluster API server URL>#' \
  substrate-cluster.yaml | kubectl apply -f -
```

`CODER_UPSTREAM` is where coder-bridge sends the agent's bytes, over plain HTTP. Use an address inside your network.

Add two lines to the CoreDNS `Corefile`, before the `kubernetes` block, so that the gateway resolves the two names to coder-bridge:

```text
rewrite name exact coder.substrate.internal coder-bridge.coder-bridge.svc.cluster.local
rewrite name exact broker.substrate.internal coder-bridge.coder-bridge.svc.cluster.local
```

Then create the atespace, the access policy, and the actor template:

```sh
kubectl ate create atespace coder
kubectl ate create access-policy -a coder -f access-policy.yaml
sed 's#WORKSPACE_IMAGE#<workspace image>#' actor-template.yaml \
  | kubectl ate create actor-template -f -
```

Substrate boots a golden actor and snapshots it. That took about 1 minute for us. `kubectl ate get actor-template coder-workspace -a coder -o yaml` shows `snapshotTime` when it is done.

## 7. Push the template

```sh
coder templates push kubernetes-substrate -d ..
```

## Security model

- **Kernel:** each workspace is a Cloud Hypervisor microVM with its own kernel, inside a worker Pod.
- **Network:** the egress gateway is outside the microVM. It allows only the host names and ports in the actor's policy, plus the Coder front and the broker. It resolves names itself, so a forged server name or a forced IP address does not reach another host. Rules cannot name IP addresses, so cloud metadata, the cluster, and other actors are not reachable.
- **Credentials:** the workspace never has a Substrate or Kubernetes credential. It has only its own agent token, from the broker. The broker checks a signed token for the actor that the gateway adds, and returns only that actor's agent token.
- **coder-bridge:** it has a read-only token for one namespace in the Coder cluster and the editor role in one atespace. A NetworkPolicy lets only the egress gateway reach it.
- **Users:** the shell runs as UID 1000 with no capabilities and no `sudo`. Only coder-boot has `CHOWN`, `SETUID`, and `SETGID`, which the actor template adds. Substrate starts the container as root and shows image files as owned by root, so coder-boot gives `/home/coder` to UID 1000 once, in the golden actor, and starts the agent as that user.

## Limits

- **Plain HTTP from coder-bridge to Coder:** the TLS front ends TLS, and the bytes go to `CODER_UPSTREAM` over plain HTTP. Keep that path inside your network.
- **Polling:** coder-bridge reads the Coder cluster every 250 ms instead of using a watch. That is a few small requests a second.
- **No autoscaling:** the worker pool has a fixed size (5 in `substrate-cluster.yaml`).
