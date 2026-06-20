# K0s context

## Machines
- Desktop: pc left in place with EndeavourOS using home-manager for most packages (some installed with yay/pacman)
- Laptop: laptop with EndeavourOS using home-manager for most packages (some installed with yay/pacman)
- Nix machines (3): 3 machines with headless nixOS running k0s

## Cluster management
- Repository is GitOps-managed with Flux.
- `cluster/` contains manually applied/bootstrap manifests:
  - `flux-operator.yaml`: Flux Operator Helm values.
  - `flux-instance.yaml`: FluxInstance syncing this repository.
- Flux sync entrypoint is `deploy/`.
- Each file under `deploy/` defines a Flux `Kustomization` pointing to a component under `components/`.
- SOPS with age is configured via `.sops.yaml`; encrypted YAML/JSON/env/conf files should use the configured age recipients.

## Components
- `components/network`: Cilium LoadBalancer IPAM and L2 announcement policy for tailnet-facing services.
- `components/gateway`: Cilium Gateway API Gateway for tailnet HTTP/TCP exposure.
- `components/storage`: Rancher local-path-provisioner deployed by Flux HelmRelease.
- `components/monitoring`: VictoriaMetrics Kubernetes stack deployed by Flux HelmRelease.
- `components/syncthing`: Syncthing deployment, PVCs, ClusterIP service, HTTPRoute, and TCPRoute.
- `components/jellyfin`: Jellyfin deployment, PVCs, ClusterIP service, and HTTPRoute.
- `components/hermes`: Hermes gateway/dashboard deployment, PVC, generated env secret, ClusterIP service, and HTTPRoute.

## Network
Tailscale is installed on each machine. I want services running in the clusters to be accessible from my laptop and desktop at any time.

### Tailnet LoadBalancer exposure
- Tailnet-facing Kubernetes LoadBalancer services use:
  - `type: LoadBalancer`
  - label `exposure: tailnet`
  - annotation `lbipam.cilium.io/ips` for deterministic IP assignment.
- HTTP/TCP application exposure is consolidated behind the Cilium Gateway API Gateway:
  - namespace/name: `gateway/tailnet`
  - GatewayClass: `cilium`
  - address: `10.250.0.14`
  - HTTP listener: TCP `80`, hostname `*.home`
  - Syncthing sync listener: TCP `22000`
- Cilium IP pool:
  - name: `tailnet-lb-pool`
  - range: `10.250.0.10-10.250.0.50`
  - selected services: `exposure: tailnet`
- Cilium L2 announcement policy:
  - name: `tailnet-lb`
  - announces LoadBalancer IPs for selected services.

### Assigned service IPs
- Cilium Gateway API Gateway: `10.250.0.14`
  - Jellyfin: `http://jellyfin.home/` -> service `jellyfin:8096`
  - Syncthing dashboard: `http://syncthing.home/dash` -> service `syncthing:8384`
  - Syncthing sync: `syncthing.home:22000` -> service `syncthing:22000/TCP`
  - Hermes dashboard: `http://hermes.home/dash` -> service `hermes:9119`

### Tailscale routing model
- Cluster nodes must be able to reach `10.250.0.0/24` LoadBalancer IPs locally.
- PC/laptop access requires Tailscale subnet routing for `10.250.0.0/24`.
- At least one cluster node advertises `10.250.0.0/24` as a Tailscale subnet route.
- The subnet route must be approved in the Tailscale admin console.
- Client machines must accept routes, for example with `tailscale up --accept-routes` on Linux.
- Tailscale ACLs must allow the desired source users/devices to reach the service IPs and ports.

### Network troubleshooting checklist
- From PC/laptop:
  - `tailscale status`
  - `ip route get 10.250.0.11`
  - `nc -vz 10.250.0.11 8384`
- From a cluster node:
  - verify service IP reachability, for example `10.250.0.11:8384`
  - verify IP forwarding if the node is a Tailscale subnet router
- If services are reachable from cluster nodes but not from PC/laptop, check:
  1. Tailscale subnet route approval
  2. client `--accept-routes`
  3. route conflict with local LAN/VPN
  4. Tailscale ACLs
  5. node firewall/forwarding
