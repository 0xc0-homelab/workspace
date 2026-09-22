# Closed design — 0xc0-homelab

Status: **closed**. Not reopened without an explicit decision from the operator.

## Addressing

| Group     | Supernet      | Zones          |
|-----------|---------------|----------------|
| control   | 10.10.0.0/22  | mgmt .0, ci .1 |
| platform  | 10.10.4.0/24  | platform       |
| exposed   | 10.10.8.0/24  | edge           |
| workloads | 10.10.16.0/20 | workloads .16  |
| data      | 10.10.32.0/24 | data           |

Reserved so they never overlap:
`10.11.0.0/16` node 2 · `10.20.0.0/16` Hetzner Cloud and vSwitch ·
`10.42.0.0/16` RKE2 pods · `10.43.0.0/16` RKE2 services ·
`10.66.66.0/24` future lab.

## Machines

| Zone      | VM          | vCPU | RAM   | IP           | Contents                          |
|-----------|-------------|------|-------|--------------|-----------------------------------|
| mgmt      | vm-access   | 1    | 1 GB  | 10.10.0.10   | cloudflared + warp-routing        |
| ci        | vm-ci       | 2    | 4 GB  | 10.10.1.10   | Ephemeral runner                  |
| platform  | vm-vault    | 1    | 2 GB  | 10.10.4.10   | Vault (phase 3)                   |
| platform  | vm-platform | 4    | 8 GB  | 10.10.4.20   | Prometheus + Grafana              |
| edge      | vm-edge     | 2    | 4 GB  | 10.10.8.10   | cloudflared + NGINX + open-appsec |
| workloads | vm-apps     | 4    | 12 GB | 10.10.16.10  | Containers                        |
| workloads | vm-rke2     | 4    | 12 GB | 10.10.16.20  | RKE2 (phase 6)                    |
| data      | vm-data     | 2    | 8 GB  | 10.10.32.10  | Postgres, Redis                   |

The host (`pve-1`, `pve.0xc0.cc`) holds `.1` in every zone and is the router
and the firewall. `eno1` keeps the public IP; the zone bridges are internal,
with no physical port, and egress is NAT through `eno1` — Hetzner drops
unknown MACs on the public interface, so guests never bridge onto it.

Besides Proxmox, the host runs the base services, **outside IaC**:

- **Traefik** — reverse proxy for the Proxmox UI, PBS and RustFS.
- **RustFS** — S3-compatible store holding the OpenTofu state (`s3.0xc0.cc`).
- **PBS** — backups, with the datastore on a Hetzner Storage Box.

## Transit

The normative matrix, in machine-readable form, lives in
`infrastructure/docs/zones.md`. `firewall.tf` is generated from it.

| From      | To                              | Ports                          |
|-----------|---------------------------------|--------------------------------|
| mgmt      | all + node                      | 22, 3389, 6443, 8006, 8200     |
| ci        | edge, platform, workloads, data | 22                             |
| ci        | node                            | 8006 (API, not SSH)            |
| ci        | platform                        | 8200                           |
| edge      | workloads                       | 8080, 30000-32767              |
| workloads | data                            | 5432, 6379                     |
| workloads | platform                        | 8200                           |
| platform  | workloads, data, node           | 9100, 10250                    |
| platform  | internet                        | 443                            |
| data      | —                               | initiates nothing              |

Node under DROP policy, only 22 and 8006 from `10.10.0.0/22`.
Nobody initiates towards mgmt.

## Flows

- **Web**: Cloudflare → tunnel → vm-edge → open-appsec → NGINX by
  `server_name` → vm-apps or the cluster ingress.
- **Admin**: Access + WARP → vm-access → straight into any zone, no hop.
  Private dashboards go through this tunnel, **never** through the edge.
- **Deploy**: merge → runner on vm-ci (pull) → SSH or Proxmox API.
- **Egress**: VM → `.1` of its zone → NAT behind the public IP.

## Stack

Proxmox VE 9 on a Hetzner dedicated server, 2× NVMe in mdadm RAID 0 ·
PBS to a Hetzner Storage Box · RustFS for the OpenTofu state · Cloudflare Free
(Tunnel, Access, WARP) · NGINX + open-appsec · Packer + OpenTofu + Ansible ·
GitHub Actions with a self-hosted runner · SOPS+age → Vault over OIDC ·
Prometheus + Grafana · Hetzner Rescue as the emergency path.

Bridges in Ansible for now, SDN with node 2. Native Proxmox firewall through
the `bpg/proxmox` provider.

## Phases

1. **Base** — Proxmox, zones, NAT, Packer, vm-access, vm-edge. SOPS working.
   Rescue and WARP tested. Everything driven manually from the laptop.
2. **Core** — vm-apps, vm-data, repos, vm-ci holding the age key, workflows.
   Backups to B2 with a timed restore.
3. **Platform** — vm-platform with alerts to the phone, vm-vault with OIDC and
   a progressive migration.
4. **Resilience** — Hetzner Cloud VM, vSwitch, external uptime checks.
5. **HA** — node 2, QDevice, storage replication, migration to SDN. Node 1
   has no ZFS (mdadm RAID 0), so the replication model is redesigned here.
6. **Kubernetes** — RKE2 and ArgoCD. The WAF moves to the ingress, never duplicated.

**Non-negotiable: the tested restore in phase 2.** If the RTO is not measured
in writing, it is not tested.

## Discarded — do not propose

| Discarded           | Reason                                               |
|---------------------|------------------------------------------------------|
| WireGuard           | Cloudflare Access + WARP already covers admin access |
| Traefik as ingress  | with no containers alongside it adds nothing over NGINX; it runs on the host only as the reverse proxy for Proxmox, PBS and RustFS, outside IaC |
| Coraza              | open-appsec avoids hand-tuning the CRS               |
| BunkerWeb           | stores its configuration in SQLite                   |
| OPNsense, VyOS      | fragile network hop and immature providers           |
| VLANs now           | they arrive with SDN in phase 5; bridges for now     |
| Terraform Stacks    | paid                                                 |
| OpenBao             | Vault's BSL does not affect this case                |
| Loki, Tempo now     | Prometheus + Grafana only, for now                   |
| Two K8s clusters    | same hardware, adds no isolation                     |
| Bug bounty lab      | reserved range, out of scope                         |
| Flux                | operator decision (2026-09-22): GitOps is ArgoCD     |

## Accepted risks

- Single piece of hardware until phase 5: a hardware failure is an RTO of hours.
- Disks in RAID 0 (operator decision, 2026-09-23): one NVMe failure loses the
  whole node. Recovery is a reinstall plus a restore from PBS on the Storage
  Box, which is why that restore has to be tested and timed.
- The Proxmox UI, PBS and RustFS are reachable from the internet through
  Traefik on the host. RustFS in particular is open until the CI runner exists
  (0xc0-homelab/.github#13).
- Dependency on Cloudflare to get in, with Hetzner Rescue as the way out.
- Six zones is a fair amount of surface for a single operator.
- open-appsec is a piece never operated before. Its documentation is sparse and
  unreliable in model training data: **do not invent syntax**, look up the
  official docs.

## Repos and policies

`infrastructure` and `.github`: `main` only, PR required, apply behind manual
approval. `app-*`: test→prod promotion of the same digest.
ArgoCD will point at `deployments/clusters/prod/`.
