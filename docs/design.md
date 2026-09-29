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

Sizes and addresses are in `infrastructure/docs/zones.md`.

**The three RKE2 nodes are identical, and all three are servers** (operator
decision, 2026-09-27): each runs the control plane and etcd, and takes
workloads. In Kubernetes the role is configuration, not a different machine;
three servers keep etcd's quorum through the loss of one VM.

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

- **Web**: Cloudflare → public tunnel → cloudflared on the LB VMs → HAProxy →
  NodePort → ingress with open-appsec → service.
- **Portals** (Grafana, ArgoCD): the same path, behind Cloudflare Access. The
  ArgoCD policy also requires the device to be on WARP: it can change the whole
  cluster.
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
an ingress with open-appsec · Vault · Prometheus + Grafana · Hetzner Rescue as
the emergency path.

**ArgoCD is installed with the cluster, and everything else in the cluster by
ArgoCD** (operator decision, 2026-09-29, replacing the OpenTofu root of
2026-09-27). The Ansible playbook that brings RKE2 up also writes ArgoCD's
`HelmChart` and its root `Application` into RKE2's manifests directory, and
RKE2's own helm-controller installs it. An OpenTofu root would have needed
Ansible to have run first, and the admin kubeconfig outside the servers;
this needs neither. RKE2's helm-controller keeps managing ArgoCD itself, so
two controllers never fight over it. From there ArgoCD deploys every other
component (the ingress, open-appsec, Vault, monitoring, applications) from
the `gitops` repo, which is public: no repo credentials. A private repo would
get a read-only GitHub App, its key bootstrapped from SOPS the same way.

**Vault runs in the cluster** (operator decision, 2026-09-24). The cluster
boots with secrets from SOPS only, so it never needs Vault to start: the RKE2
token and ArgoCD's admin password go from SOPS, through Ansible, into files
only root reads on the servers. ArgoCD then deploys Vault, and applications
take their secrets from it through External Secrets Operator. No secret lives
in `gitops`, not even encrypted, so ArgoCD never holds the age key. Vault is
unsealed by hand after a restart. Which ingress controller carries open-appsec
is chosen against open-appsec's documentation when it is built.

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
   with the public tunnel, ArgoCD, the ingress with open-appsec. Backups to B2
   with a timed restore.
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
| Traefik as ingress  | it runs on the host only as the reverse proxy for Proxmox, PBS and RustFS, outside IaC |
| Coraza              | open-appsec avoids hand-tuning the CRS               |
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
- The public tunnel's connectors run on the LB VMs: public traffic enters
  `platform`, never `mgmt`.
- The CI VMs reach the vm-access connectors over SSH, so a compromised CI VM
  reaches the admin way in. It already holds the keys that change the whole
  infrastructure.
- open-appsec is a piece never operated before. Its documentation is sparse and
  unreliable in model training data: **do not invent syntax**, look up the
  official docs.

## Repos and policies

`infrastructure` and `.github`: `main` only, PR required, apply behind manual
approval. `app-*`: test→prod promotion of the same digest.
ArgoCD points at `gitops/clusters/prod/`.
