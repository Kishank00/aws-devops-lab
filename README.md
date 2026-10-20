# AWS DevOps Lab

A hands-on DevOps project. One real application, [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool) (a FastAPI service), is deployed on AWS three times, once for each era of DevOps:

| Phase | How the app runs | Status |
|---|---|---|
| **1. Virtual machines** | EC2 + systemd + nginx, the classic "on-prem" way, fully automated | ✅ Done |
| **2. Containers** | Docker image, built and published by CI | 🔜 Planned |
| **3. Orchestration** | Kubernetes | 🔜 Planned |

All infrastructure is Terraform. All deployments run through GitHub Actions with OIDC, so no AWS keys are stored anywhere.

---

## Table of contents

- [Phase 1: Virtual machines (EC2)](#phase-1-virtual-machines-ec2)
  - [Architecture](#architecture)
  - [What is built](#what-is-built)
  - [CI/CD pipelines](#cicd-pipelines)
  - [How the server sets itself up](#how-the-server-sets-itself-up)
  - [Security highlights](#security-highlights)
- [Phase 2: Containers (Docker)](#phase-2-containers-docker)
- [Phase 3: Orchestration (Kubernetes)](#phase-3-orchestration-kubernetes)
- [Repository layout](#repository-layout)
- [Runbook](#runbook)
- [Cost](#cost)
- [Tech stack](#tech-stack)

---

## Phase 1: Virtual machines (EC2)

### Architecture

```
                         Internet
                            │
                            ▼
        ┌──────────── VPC 10.0.0.0/16 (ap-south-1) ───────────────┐
        │                                                          │
        │   Public subnets (AZ a + b)                              │
        │   ┌─────────────────────────────────────────────┐        │
        │   │  ALB :80  (SG: 80 from internet)            │        │
        │   │  NAT gateway        Internet gateway        │        │
        │   └──────────┬──────────────────▲───────────────┘        │
        │              │ /health check    │ outbound only          │
        │              ▼                  │ (apt, git, pip)        │
        │   Private subnets (AZ a + b)    │                        │
        │   ┌─────────────────────────────┴───────────────┐        │
        │   │  EC2 (Ubuntu 24.04, no public IP, no SSH)   │        │
        │   │  SG: 80 from ALB SG only                    │        │
        │   │                                             │        │
        │   │  nginx :80 ──► uvicorn 127.0.0.1:8000       │        │
        │   │                (systemd, user "sysdiag")    │        │
        │   └─────────────────────────────────────────────┘        │
        └──────────────────────────────────────────────────────────┘

  Admin access: AWS SSM Session Manager (no port 22, no keys)
```

Request path: `browser → ALB → nginx → FastAPI app`

### What is built

Everything below is Terraform, organised as reusable modules that an environment folder wires together.

| Module | Resources |
|---|---|
| `modules/network` | VPC, 2 public + 2 private subnets across 2 AZs, internet gateway, NAT gateway, route tables. Subnets are created from lists (`count`), so adding an AZ is a tfvars change. |
| `modules/ec2` | Ubuntu 24.04 instance in a private subnet, security group (inbound 80 only from the ALB), IAM role + instance profile for SSM, boot script (`user_data.sh`). |
| `modules/alb` | Internet-facing Application Load Balancer, its security group, a target group with a `/health` health check, an HTTP listener, and the instance attachment. |

`environments/dev` calls the three modules and passes outputs between them. Network IDs go into ec2 and alb, the instance ID goes into alb, and the ALB security group ID goes into ec2.

`bootstrap/` is a separate, long-lived stack that is applied once and **never destroyed**:

| Resource | Purpose |
|---|---|
| S3 state bucket | Remote state for every environment: versioned, encrypted, public access blocked, `prevent_destroy`. Locking uses S3's native lock file (`use_lockfile`), so no DynamoDB is needed. |
| GitHub OIDC provider | Lets GitHub Actions get short-lived AWS credentials without stored keys. |
| `github-actions-terraform` | Read-only role for `plan`. Usable by any branch or PR of this repo. |
| `github-actions-terraform-apply` | Admin role for `apply`/`destroy`. Usable **only** by jobs running in the approved `dev` GitHub environment. |
| `github-actions-app-deploy` | Role for the **app repo**. It can only run SSM commands on the instance tagged `devops-lab-dev-diagnostic`, and only from the `master` branch. |

### CI/CD pipelines

There are two repos and three pipelines. Infrastructure and application change at different speeds, so each gets its own pipeline and its own least-privilege role.

**1. Infrastructure: `.github/workflows/terraform.yml` (this repo)**
```
push / PR ──► check: fmt ──► validate ──► plan (read-only role)
                                             │
push to main only ───────────────────────────┴─► apply (needs manual approval in the "dev" environment)
```

**2. Teardown: `.github/workflows/terraform-destroy.yml` (this repo)**
Started manually. You pick the environment and type `destroy` to confirm, and it still needs approval.

**3. Application: `ci.yaml` in [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool)**
```
push to master ──► pytest ──► OIDC ──► find instance by tag ──► SSM Run Command: deploy-sysdiag
                                                                   │
                                     git pull ► uv sync ► systemctl restart ► curl /health
```
A code change is live in about 10 seconds on the **same** server. If the health check fails after the restart, the pipeline goes red.

### How the server sets itself up

`modules/ec2/user_data.sh` runs once, on first boot. It does exactly what was first done by hand over SSM:

| Step | What it does |
|---|---|
| 0 | Waits for internet (up to 30 tries). On a fresh apply the NAT gateway may still be starting. |
| 1 | Installs nginx. |
| 2 | Creates the `sysdiag` service account (system user, no login shell, home `/opt/sysdiag`). |
| 3 | Clones the app into `/opt/sysdiag/app`, as that user. |
| 4-5 | Installs `uv` and the locked dependencies into the app's own `.venv`. |
| 6 | Installs a systemd unit: runs as `sysdiag`, restarts on crash, starts on boot. The app listens on `127.0.0.1:8000` only. |
| 7 | Configures nginx as a reverse proxy, port 80 to the app, and disables the default site. |
| 8 | Installs `/usr/local/bin/deploy-sysdiag`, the script the app pipeline runs for each release. |

Because the instance sets `user_data_replace_on_change = true`, any change to this script replaces the server on the next apply. App code changes do **not** replace the server; they go through `deploy-sysdiag`.

### Security highlights

- **No stored AWS credentials.** Every pipeline uses GitHub OIDC with short-lived tokens.
- **Least privilege per pipeline:**
  - plan is read-only
  - apply is gated by a manual approval
  - app deploys can only target one tagged instance
- **No SSH.** Port 22 is closed, there are no key pairs, and the instance has no public IP. Access is SSM only, controlled by IAM.
- **Layered network:**
  - the instance accepts port 80 only from the ALB's security group
  - the app itself listens only on `127.0.0.1`
- **Non-root app.** The app runs as a dedicated service account. The deploy script lives in a root-owned path, so the app user cannot modify it.
- **Account guard.** `allowed_account_ids` in the provider stops Terraform from ever running against the wrong AWS account.
- **State protection.** The state bucket is versioned and encrypted, and its lock file prevents concurrent writes.

---

## Phase 2: Containers (Docker)

> 🔜 **Planned.** This section will be filled in when the phase is built.

Goal: build the app once as an image and run that exact image everywhere, with rollback by image tag.

Why move on from Phase 1:
- The app and its runtime are installed directly on the OS, so an OS upgrade can break it.
- Each server builds its own environment from source, so two servers can differ.
- There is no simple rollback to the previous release.

<!-- Phase 2 sections, to add here:
### Architecture
### What changed from Phase 1
### CI/CD pipeline
### How to run
-->

---

## Phase 3: Orchestration (Kubernetes)

> 🔜 **Planned.** This section will be filled in when the phase is built.

Goal: several copies of the app across AZs, zero-downtime rolling updates, self-healing, and Ingress-based routing.

<!-- Phase 3 sections, to add here:
### Architecture
### What changed from Phase 2
### CI/CD pipeline
### How to run
-->

---

## Repository layout

```
aws-devops-lab/
├── bootstrap/                  # one-time, long-lived: state bucket + GitHub OIDC roles (never destroy)
│   ├── main.tf                 #   S3 state bucket
│   ├── github-oidc.tf          #   OIDC provider, plan + apply roles for this repo
│   └── github-app-deploy.tf    #   deploy role for the app repo (SSM only)
├── modules/                    # reusable building blocks
│   ├── network/                #   VPC, subnets, IGW, NAT, routes
│   ├── ec2/                    #   instance, SG, SSM role, user_data.sh
│   └── alb/                    #   load balancer, target group, listener
├── environments/
│   └── dev/                    # wires the modules together; one folder per environment
└── .github/workflows/
    ├── terraform.yml           # fmt → validate → plan → (approval) → apply
    └── terraform-destroy.yml   # manual, confirmed, approved teardown
```

---

## Runbook

### Prerequisites
- An AWS account and a local CLI profile for it
- Terraform `>= 1.16`
- AWS CLI with the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) (`brew install --cask session-manager-plugin`)

### First-time setup (once per AWS account)
```bash
cd bootstrap
terraform init
terraform apply        # state bucket, OIDC provider, GitHub roles
```
Then, in GitHub, create the environment **`dev`** with a required reviewer, a deployment branch rule for `main`, and the variable `AWS_ROLE_ARN` set to the apply role's ARN.

### Deploy
Push to `main` and approve the `apply` job, or re-run the latest workflow run. About 3-4 minutes later the app is live. Get the URL with:
```bash
cd environments/dev
terraform output -raw alb_dns_name
```
Then open `http://<alb-dns>/docs`.

### Connect to the server
```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

### Destroy
**Actions → terraform-destroy → Run workflow**, pick `dev`, type `destroy`, and approve.
Never destroy `bootstrap/`: it holds the state of every environment.

### Troubleshooting

| Symptom | Where to look |
|---|---|
| App not reachable after deploy | `cloud-init status` and `sudo tail -50 /var/log/cloud-init-output.log` on the instance |
| App down or crash-looping | `systemctl status sysdiag` and `sudo journalctl -u sysdiag -n 50` |
| ALB returns 502/503 | Target group health in the console. The health check calls `/health` through nginx. |
| `Error acquiring the state lock` | Make sure no pipeline or local run is active, then run `terraform force-unlock <LOCK_ID>` |

---

## Cost

The NAT gateway and ALB bill per hour (roughly $2/day together in ap-south-1), so the environment is created for a session and destroyed the same day. The bootstrap stack (S3 + IAM) costs close to nothing.

---

## Tech stack

**Cloud:** AWS (VPC, EC2, ALB, NAT, IAM, SSM, S3) · **IaC:** Terraform (modules, S3 remote state with native locking) · **CI/CD:** GitHub Actions, OIDC, environment approvals · **Server:** Ubuntu 24.04, systemd, nginx · **App:** Python 3.12, FastAPI, uvicorn, uv
