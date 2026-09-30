# Closed design — 0xc0-homelab

Status: **closed**. Not reopened without an explicit decision from the operator.

This file records the decisions. How the pieces fit together, with diagrams,
is in [`infrastructure/docs/architecture.md`](https://github.com/0xc0-homelab/infrastructure/blob/main/docs/architecture.md).

## Addressing

| Group    | Supernet     | Zones          |
|----------|--------------|----------------|
| control  | 10.10.0.0/22 | mgmt .0, ci .1 |
| platform | 10.10.4.0/24 | platform       |

Three zones (operator decision, 2026-09-24): `mgmt` and `ci`, which build and
reach everything else and never depend on it, and `platform`, which holds the
Kubernetes cluster and its load balancer. Separation inside the cluster is by
namespace and NetworkPolicy, not by zone.

Reserved so they never overlap:
`10.11.0.0/16` node 2 · `10.20.0.0/16` Hetzner Cloud and vSwitch ·
`10.42.0.0/16` RKE2 pods · `10.43.0.0/16` RKE2 services ·
`10.66.66.0/24` future lab.

## Machines

| Zone     | VM           | OS     | Contents                                          |
|----------|--------------|--------|---------------------------------------------------|
| mgmt     | vm-access-01 | Debian | cloudflared connector of the admin tunnel (QUIC)  |
| mgmt     | vm-access-02 | Debian | cloudflared connector of the admin tunnel (QUIC)  |
| ci       | vm-ci-01     | Debian | two ephemeral GitHub Actions runners              |
| ci       | vm-ci-02     | Debian | two ephemeral GitHub Actions runners              |
| platform | vm-lb-01     | Debian | HAProxy + keepalived; public tunnel connector     |
| platform | vm-lb-02     | Debian | HAProxy + keepalived; public tunnel connector     |
| platform | vm-rke2-01   | Rocky  | RKE2 server                                       |
| platform | vm-rke2-02   | Rocky  | RKE2 server                                       |
| platform | vm-rke2-03   | Rocky  | RKE2 server                                       |
| platform | vm-rke2-04   | Rocky  | RKE2 agent                                        |

Sizes and addresses are in `infrastructure/docs/zones.md`.

**The three RKE2 nodes are identical, and all three are servers** (operator
decision, 2026-09-27): each runs the control plane and etcd, and takes
workloads. In Kubernetes the role is configuration, not a different machine;
three servers keep etcd's quorum through the loss of one VM.

**Capacity grows with agents; etcd stays at three servers** (operator
decision, 2026-09-30). An agent runs workloads only, with no control plane or
etcd: a fourth server would tolerate no more failures than three, and two
would tolerate none. `vm-rke2-04` is the first, sized and disked like the
servers, Longhorn included. On one host it adds capacity, not availability.

**Outside the cluster, deliberately:** the vm-access pair is the admin way in,
and the vm-ci pair builds and changes the infrastructure, the cluster included.
Neither may depend on what it has to fix.

**Two CI VMs, identical** (operator decision, 2026-09-29): CI keeps running
while one is down, and a job on one can rebuild the other, so no rebuild of a
CI VM has to run from the laptop.

**The RKE2 nodes run Rocky Linux 10**, the latest release RKE2 supports
(RHEL 10 and its derivatives, with the package that allows `nf_conntrack`;
operator decision, 2026-09-24). They clone their own template chain, from the official
Rocky cloud image, as the Debian VMs do from theirs.

**The load balancer is deployed with the cluster**: the same OpenTofu module
creates the nodes and the two LB VMs, and Ansible writes HAProxy's backends from
the node list. HAProxy fronts the Kubernetes API (6443, 9345) and the ingress
NodePorts; keepalived moves its VIP between the two VMs.

The host (`pve-1`, `pve.0xc0.cc`) holds `.1` in every zone and is the router
and the firewall. `eno1` keeps the public IP. Each zone is an SDN VNet with no
physical port, and egress is SNAT through `eno1` — Hetzner drops unknown MACs
on the public interface, so guests never bridge onto it.

Besides Proxmox, the host runs the base services, **outside IaC**:

- **Traefik** — reverse proxy for the Proxmox UI, PBS and RustFS.
- **RustFS** — S3-compatible store holding the OpenTofu state (`s3.0xc0.cc`).
- **PBS** — backups, with the datastore on a Hetzner Storage Box.

## Transit

The matrix that decides is the `transit` variable in
`infrastructure/environments/prod/terraform.tfvars`: the `zone-firewall` module
computes every rule from it. `infrastructure/docs/zones.md` explains it. This
table is the target once the cluster exists:

| From     | To       | Ports                                                   |
|----------|----------|---------------------------------------------------------|
| mgmt     | ci       | 22                                                      |
| mgmt     | platform | 22, 443 (portals), 6443 (Kubernetes API), 8200 (Vault)  |
| mgmt     | node     | 22, 443, 8006                                           |
| mgmt     | mgmt     | 22, between the vm-access connectors                    |
| ci       | platform | 22, 6443                                                |
| ci       | mgmt     | 22, from the CI VMs only: Ansible on the vm-access pair |
| ci       | node     | 443, 8006 (API, not SSH)                                |
| internet | node     | 22, break-glass; closed at the Hetzner firewall         |
| platform | platform | the cluster's own traffic, and VRRP between the LBs     |
| platform | node     | 9100 (node metrics)                                     |

Inside `platform`, the cluster needs more than TCP (VXLAN for the pod network,
VRRP for keepalived), so the matrix gains a protocol per entry.

The node is on a DROP policy: 22, 443 and 8006 from the admin zones, 22 never
from ci, the metrics port from platform, and from the internet only SSH, as
break-glass (operator decision, 2026-09-26): the Hetzner firewall keeps it
closed until the operator opens it, and sshd is key-only. Traefik (Proxmox UI,
PBS, RustFS) is reached over WARP, where Gateway resolves its hostnames to the
node's address in mgmt. If WARP breaks, the way back is that SSH, then the
Hetzner Rescue system.

No other zone initiates towards mgmt, with one exception: SSH from the CI VMs'
addresses, not the whole `ci` zone, so the pipeline can run the vm-access
playbook (operator decision, 2026-09-29).

## Flows

- **Web**: Cloudflare → public tunnel → cloudflared on the LB VMs → HAProxy
  (layer 4) on 443 → NodePort → Traefik, with CrowdSec's bouncer → service.
  cloudflared talks HTTPS to Traefik and checks its certificate, with the
  request's host as SNI. The client's address reaches Traefik as
  `CF-Connecting-IP`, trusted only from `platform`.
- **TLS** (operator decision, 2026-09-29): it ends at Traefik, on both paths,
  with a Let's Encrypt wildcard per domain (`*.d` and `d`) from cert-manager,
  through DNS-01 challenges in Cloudflare. Port 80 only redirects to HTTPS.
  Domains: `0xc0.cc` and `offby1.cc`; `sergioaten.cloud` once the Cloudflare
  token reaches its zone.
- **Public names**: the tunnel serves every name of the domains in
  `public_domains`, but a name is public only once external-dns gives it a
  record (a proxied CNAME to the tunnel), which it does only for an HTTPRoute
  annotated `gateway.0xc0.cc/public: "true"`. Only zones in the tunnel's own
  Cloudflare account can be public: a CNAME to it from another account's zone
  (`offby1.cc`) fails at the edge (1014). external-dns comes ahead of phase 6
  on purpose (operator decision, 2026-09-29).
- **Portals** (Grafana, ArgoCD, Headlamp): internal, reached only over WARP.
  None has a public record (operator decision, 2026-09-29): publishing one
  behind Cloudflare Access is deferred.
- **Internal services** (operator decision, 2026-09-30): a path of their own,
  separated by network. A second VIP on the LBs, `10.10.4.9`, sends its 443
  to Traefik's `internal` entrypoint; Cloudflare Gateway resolves every
  `*.int.0xc0.cc` name to it for WARP devices, and those names have no public
  record. The public tunnel only ever targets the public VIP, so nothing from
  the internet reaches the internal path. Headlamp, the Kubernetes UI, is the
  first, at `headlamp.int.0xc0.cc`, logged into with a short-lived token. The
  internal path has no WAF: CrowdSec's bouncer is on the public entrypoint
  only.
- **Admin**: WARP → admin tunnel → either vm-access connector → any zone. The
  Kubernetes API, SSH, Vault, Proxmox, PBS and RustFS are reached **only** this
  way, never through the public tunnel.
- **Deploy**: infrastructure through the runners on the CI VMs (Proxmox API,
  SSH), OpenTofu, Packer and every Ansible playbook alike (operator decision,
  2026-09-29): `--check`/plan on the PR, the real run on merge behind manual
  approval. Nothing is applied from the laptop. What runs in the cluster goes
  through ArgoCD, from `gitops/clusters/prod/`.
- **Egress**: VM → `.1` of its zone → NAT behind the public IP.

## Stack

Proxmox VE 9 on a Hetzner dedicated server, 2× NVMe in mdadm RAID 0 ·
PBS to a Hetzner Storage Box · RustFS for the OpenTofu state · Cloudflare Free
(Tunnel, Access, WARP) · Packer + OpenTofu + Ansible · GitHub Actions with
self-hosted runners · RKE2 on Rocky Linux · HAProxy + keepalived · ArgoCD ·
Traefik with the Gateway API · CrowdSec · cert-manager with Let's Encrypt ·
external-dns · Longhorn · Headlamp · Vault · Prometheus + Grafana · Hetzner
Rescue as the emergency path.

**ArgoCD is installed with the cluster, and everything else in the cluster by
ArgoCD** (operator decision, 2026-09-29, replacing the OpenTofu root of
2026-09-27). The Ansible playbook that brings RKE2 up also writes ArgoCD's
`HelmChart` and its root `Application` into RKE2's manifests directory, and
RKE2's own helm-controller installs it. An OpenTofu root would have needed
Ansible to have run first, and the admin kubeconfig outside the servers;
this needs neither. RKE2's helm-controller keeps managing ArgoCD itself, so
two controllers never fight over it. From there ArgoCD deploys every other
component (Longhorn, Traefik, CrowdSec, Vault, monitoring, applications) from
the `gitops` repo, which is public: no repo credentials. A private repo would
get a read-only GitHub App, its key bootstrapped from SOPS the same way.

**Vault runs in the cluster** (operator decision, 2026-09-24). The cluster
boots with secrets from SOPS only, so it never needs Vault to start: the RKE2
token and ArgoCD's admin password go from SOPS, through Ansible, into files
only root reads on the servers. ArgoCD then deploys Vault, and applications
take their secrets from it through Vault Secrets Operator. No secret lives
in `gitops`, not even encrypted, so ArgoCD never holds the age key. Vault is
unsealed by hand after a restart.

**Vault's shape** (installed ahead of closing phase 2, at the operator's
request, 2026-09-30; gitops#33): three servers in HA over integrated storage
(Raft), one per RKE2 node, each on a Longhorn volume. Shamir seal: the keys
live in the operator's password manager and offline, never in the cluster or
SOPS. It is on the WARP-only path, `https://vault.int.0xc0.cc`; Traefik ends
TLS, and inside the cluster the API is plain HTTP behind NetworkPolicies
(Raft's port is TLS with Vault's own certificates; TLS on the API is a
follow-up). No agent injector: Vault Secrets Operator reads it. The init and
unseal runbook is `gitops/platform/vault/README.md`.

**Vault Secrets Operator, not External Secrets Operator** (operator decision,
2026-09-30). Vault is the only backend, so ESO's reach across backends buys
nothing, while VSO renews dynamic secrets' leases (the data services'
short-lived credentials) and restarts what uses a secret when it changes,
with no Reloader beside it. No global access: each namespace brings its own
`VaultAuth`, bound to a Kubernetes auth role named after it, which reads only
its own paths.

**Secrets are laid out by trust boundary** (operator decision, 2026-09-30):
one KV v2 engine each, `platform/` (the shared services), `apps/` (the
applications) and `ci/` (the pipelines), with paths `<engine>/<owner>/<name>`,
the owner being the namespace or the repo. Keys inside are `snake_case`, and
every secret carries `owner` and `rotated_at` metadata. A policy scopes to one
owner; the `vault` repo defines engines, roles and policies, never values.
Dynamic engines (`pki/`, `database/`) come when something needs them. The
full standard is in the `vault` repo's README.

**Vault is configured with OpenTofu from its own repo, `vault`** (operator
decision, 2026-09-30; .github#6): auth methods and roles, policies, secret
engines. It is downstream of `gitops`, which deploys Vault, so the order stays
linear: `.github → infrastructure → gitops → vault → app-*`. Its CI logs in
with the job's GitHub OIDC token (JWT auth, `hashicorp/vault-action`): no Vault
credential is stored. A PR plans read-only from any ref (role
`terraform-plan`); only `main`, inside the `production` environment that waits
for the operator, writes (role `terraform`). Neither policy touches a stored
secret. The CI VMs reach Vault on the internal VIP (`ci → platform: 443`).
The CI can only log in once its auth method and roles exist, so **the first
apply of `vault` is local**: the operator runs it once, over WARP, with the
root token (operator decision, 2026-09-30). It is the one exception to nothing
being applied from the laptop; every change after it goes through the
pipeline, and the root token is revoked once another admin way in exists.

**The ingress is Traefik, with the Gateway API, and the WAF is CrowdSec**
(operator decision, 2026-09-29). open-appsec was the plan, and it is deferred:
every Kubernetes integration it has runs on something retired or unmaintained
(ingress-nginx, retired in March 2026; Kong, with no free images since 3.10;
Istio 1.23-1.26 and Envoy 1.32-1.34, all end of life; APISIX on unmaintained
etcd images). Cloudflare Free covers DDoS and the most exploited CVEs; what it
leaves, application attacks on public apps without Access, is CrowdSec's:
Traefik's bouncer checks every request against CrowdSec's AppSec component
(virtual-patching rules, no CRS to tune) and its community blocklist, shared in
return for the attacking IPs, never request contents. The load balancers stay
layer 4, with no WAF of their own. open-appsec is reconsidered when public
applications arrive, in phase 6.

**Longhorn is the cluster's storage** (operator decision, 2026-09-29): the
default `StorageClass`, three replicas on different nodes, on each RKE2 node's
two data disks, the agents' included. It has no backup target of its own: **PBS backs the VMs up whole**,
data disks included, and that is what the timed restore tests.

Zones are Proxmox SDN: one Simple zone, a VNet and a subnet per zone, the host
as `.1` and SNAT for egress, all in OpenTofu through `bpg/proxmox`. Zones
spanning nodes come with node 2. Native Proxmox firewall through the same
provider.

## Phases

vm-ci and Packer belong to phase 1: CI needs a runner inside the network so
RustFS stays closed. The cluster comes in phase 2 (operator decision,
2026-09-24): everything after phase 1 runs in it.

1. **Base** — Proxmox, zones, NAT, the templates baked with Packer from the
   official Debian cloud image, the vm-access pair, vm-ci with the self-hosted
   runners, the zone firewall and the node firewall on DROP. SOPS working.
   Rescue and WARP tested.
2. **Cluster** — the Rocky template chain, the RKE2 cluster, the HAProxy LB
   with the public tunnel, ArgoCD, Longhorn, the ingress (Traefik) with its WAF
   (CrowdSec), cert-manager with Let's Encrypt, external-dns. Backups through
   PBS with a timed restore.
3. **Platform** — Vault in the cluster with OIDC and a progressive migration
   off SOPS, credential rotation with it; Prometheus + Grafana with alerts to
   the phone; data services (Postgres, Redis) in the cluster.
4. **Resilience** — Hetzner Cloud VM, vSwitch, external uptime checks.
5. **HA** — node 2, QDevice, storage replication, SDN zones across both nodes,
   the three RKE2 servers spread over the two nodes. Node 1 has no ZFS (mdadm RAID
   0), so the replication model is redesigned here.
6. **Applications** — the `app-*` repos, with test→prod promotion of the same
   digest.

**Non-negotiable: the tested restore in phase 2.** If the RTO is not measured
in writing, it is not tested.

## Templates

Every VM clones a template baked by Packer (operator decision, 2026-09-24).
Each chain starts from an official cloud image, which OpenTofu imports through
the Proxmox API as a raw template that no VM clones:

- **Debian**: `debian-13-cloud` → `debian-13-base` (the `base` role: guest
  agent, SSH hardening) → `debian-13-runner`.
- **Rocky**, for the RKE2 nodes: the Rocky cloud image → its base template,
  with the same `base` role, which then supports both families.

What is per VM or secret, the VM's role included, stays with cloud-init and
Ansible.

Templates carry no version. Each takes a fixed VMID from its range (operator
decision, 2026-09-29): 9000-9099 for the raw images, 9100-9199 for Packer's.
VMs keep the VMIDs Proxmox assigns. Everything still finds a template by name.
A rebuild deletes it and builds it again under the same VMID;
VMs are full clones and ignore later changes to their template, so moving one
onto a rebuilt template is a deliberate `rebuild`.

## Secrets

SOPS+age, and the encrypted files are **committed** (operator decision,
2026-09-23), even though the repos are public. Each file is encrypted to the
operator's key and to that repo's own CI key, which is the only Actions secret
the repo holds. CI decrypts with SOPS; no decrypted copies live in GitHub. From
phase 2 the CI keys move to `vm-ci`; from phase 3 secrets migrate to Vault over
OIDC.

## Discarded — do not propose

| Discarded           | Reason                                               |
|---------------------|------------------------------------------------------|
| WireGuard           | Cloudflare Access + WARP already covers admin access |
| Coraza              | the OWASP CRS needs hand-tuning; CrowdSec's virtual patching does not |
| open-appsec, for now | every Kubernetes integration runs on retired or unmaintained pieces; reconsidered in phase 6 (operator decision, 2026-09-29) |
| kube-vip, MetalLB    | the load balancer VMs keep the VIP for WARP and the API (operator decision, 2026-09-29) |
| BunkerWeb           | stores its configuration in SQLite                   |
| OPNsense, VyOS      | fragile network hop and immature providers           |
| VLAN zones now      | one node: an SDN Simple zone isolates the zones; VLAN or EVPN zones come with node 2 |
| Terraform Stacks    | paid                                                 |
| OpenBao             | Vault's BSL does not affect this case                |
| Loki, Tempo now     | Prometheus + Grafana only, for now                   |
| Two K8s clusters    | same hardware, adds no isolation; one cluster, separated by namespace (operator decision, 2026-09-24) |
| A VM per role after phase 1 (vm-edge, vm-apps, vm-data, vm-vault, vm-platform) | replaced by the cluster (operator decision, 2026-09-24) |
| Docker Compose on VMs | replaced by the cluster; `gitops` holds ArgoCD manifests |
| Bug bounty lab      | reserved range, out of scope                         |
| Flux                | operator decision (2026-09-22): GitOps is ArgoCD     |
| One ordered pipeline for the cluster's deployment | the three steps stay apart: OpenTofu creates the VMs, Ansible configures them and installs ArgoCD, ArgoCD syncs gitops (operator decision, 2026-09-30, infrastructure#112) |

## Accepted risks

- Single piece of hardware until phase 5: a hardware failure is an RTO of hours.
- Disks in RAID 0 (operator decision, 2026-09-23): one NVMe failure loses the
  whole node. Recovery is a reinstall plus a restore from PBS on the Storage
  Box, which is why that restore has to be tested and timed.
- Dependency on Cloudflare to get in, with Hetzner Rescue as the way out.
- One cluster holds shared services and applications, Vault included: they are
  separated by namespace and NetworkPolicy, not by zone.
- Vault is sealed after every restart until it is unsealed by hand; meanwhile
  applications get no new secrets.
- Inside the cluster Vault's API is plain HTTP, held in by NetworkPolicies,
  until pod-to-pod TLS: tokens and secrets cross from Traefik to the pod
  unencrypted.
- The public tunnel's connectors run on the LB VMs: public traffic enters
  `platform`, never `mgmt`.
- The CI VMs reach the vm-access connectors over SSH, so a compromised CI VM
  reaches the admin way in. It already holds the keys that change the whole
  infrastructure.
- The WAF (CrowdSec) learns nothing and protects only what its rules know:
  virtual patching for known CVEs and IP reputation, not a model of each
  application's normal traffic.
- Longhorn's pods may egress anywhere: restricting it risks breaking storage
  silently, for little gain (operator decision, 2026-09-29, gitops#10).
- cert-manager and external-dns use OpenTofu's Cloudflare token, which can
  also change the tunnels, Zero Trust and Access: whoever reads its Secret in
  the cluster gets all of that (operator decision, 2026-09-29). They get a
  DNS-only token with Vault (.github#6).
- A portal on the public path (`websecure`) stays internal only by having no
  public record. Every internal service goes on the internal path instead,
  which the public tunnel cannot reach.

## Repos and policies

`infrastructure` and `.github`: `main` only, PR required, apply behind manual
approval. `app-*`: test→prod promotion of the same digest.
ArgoCD points at `gitops/clusters/prod/`.
