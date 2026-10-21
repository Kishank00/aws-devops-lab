# AWS DevOps Lab

A hands-on DevOps project. One real application, [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool) (a FastAPI service), is deployed on AWS once for each era of DevOps:

| Phase | How the app runs | Status |
|---|---|---|
| **1. Virtual machines** | EC2 + systemd + nginx, the classic "on-prem" way, fully automated | ✅ Done |
| **2. Containers** | Docker image built by CI, stored in ECR, run on the same EC2 next to the VM version | ✅ Done |
| **3. Orchestration** | Kubernetes | 🔜 Planned |

All infrastructure is Terraform. All deployments run through GitHub Actions with OIDC, so no AWS keys are stored anywhere.

Phases 1 and 2 run **side by side on the same server**, so the two approaches can be compared directly:

| URL | Version |
|---|---|
| `http://<alb-dns>/` | Phase 1: app installed on the VM, run by systemd |
| `http://<alb-dns>:8080/` | Phase 2: the same app as a Docker container |

---

## Table of contents

- [Phase 1: Virtual machines (EC2)](#phase-1-virtual-machines-ec2)
  - [Architecture](#architecture)
  - [What is built](#what-is-built)
  - [CI/CD pipelines](#cicd-pipelines)
  - [How the server sets itself up](#how-the-server-sets-itself-up)
  - [Security highlights](#security-highlights)
- [Phase 2: Containers (Docker)](#phase-2-containers-docker)
  - [Architecture](#architecture-1)
  - [What changed from Phase 1](#what-changed-from-phase-1)
  - [Release pipeline](#release-pipeline)
  - [The live-version record](#the-live-version-record)
  - [Rollback](#rollback)
  - [Known limitations](#known-limitations)
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
| `modules/ec2` | Ubuntu 24.04 instance in a private subnet, security group (inbound only from the ALB), IAM role + instance profile, boot script (`user_data.sh`), and the live image tag parameter (Phase 2). |
| `modules/alb` | Internet-facing Application Load Balancer, its security group, and one target group, listener and attachment per app version, all generated from one map (`local.app_ports`). |
| `modules/ecr` | One private ECR repository with immutable tags and scan on push (Phase 2). |

Terraform is split into **layers**, each with its own state file, by how long the resources live:

| Layer | Contains | Lifetime | Applied by |
|---|---|---|---|
| `bootstrap/` | S3 state bucket, GitHub OIDC provider, the CI roles | permanent, **never destroyed** | an admin, by hand (the pipeline cannot manage its own permissions) |
| `environments/shared` | ECR repositories (`for_each` over app names) | long-lived, survives env teardowns | pipeline |
| `environments/dev` | network, ec2, alb | created for a session, destroyed the same day | pipeline |

`environments/dev` calls the modules and passes outputs between them. Network IDs go into ec2 and alb, the instance ID goes into alb, and the ALB security group ID goes into ec2.

Roles in `bootstrap/`:

| Role | Can do | Who can assume it |
|---|---|---|
| `github-actions-terraform` | read-only, for `plan` | any branch or PR of this repo |
| `github-actions-terraform-apply` | admin, for `apply`/`destroy` | only jobs in the approved `dev` or `shared` GitHub environments |
| `github-actions-app-deploy` | SSM commands on the instance tagged `devops-lab-dev-diagnostic`, push to the `linux-diagnostic-tool` ECR repo, write the one live-tag parameter | only the `master` branch of the **app repo** |

### CI/CD pipelines

There are two repos and three pipelines. Infrastructure and application change at different speeds, so each gets its own pipeline and its own least-privilege role.

**1. Infrastructure: `.github/workflows/terraform.yml` (this repo)**
```
push / PR ──► check (shared, dev in parallel): fmt ──► validate ──► plan (read-only role)
                                                                      │
push to main only ────────────────────────────────────────────────────┴─► apply shared ──► apply dev
                                                                          (each needs manual approval
                                                                           in its GitHub environment)
```
Changes that touch only `bootstrap/` skip this pipeline (`paths-ignore`), because bootstrap is applied by hand.

**2. Teardown: `.github/workflows/terraform-destroy.yml` (this repo)**
Started manually. You pick the environment and type `destroy` to confirm, and it still needs approval. Only `dev` is offered: `shared` and `bootstrap` are never destroyed from a workflow.

**3. Application: `ci.yaml` in [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool)**

Covered in [Release pipeline](#release-pipeline). It deploys both versions on every push to `master`.

### How the server sets itself up

`modules/ec2/user_data.sh` runs once, on first boot. It does exactly what was first done by hand over SSM:

| Step | What it does |
|---|---|
| 0 | Waits for internet (up to 30 tries). On a fresh apply the NAT gateway may still be starting. |
| 1 | Installs nginx and Docker. |
| 1b | Installs the ECR credential helper, so Docker pulls from ECR with the instance role (no `docker login`). |
| 2 | Creates the `sysdiag` service account (system user, no login shell, home `/opt/sysdiag`). |
| 3 | Clones the app into `/opt/sysdiag/app`, as that user. |
| 4-5 | Installs `uv` and the locked dependencies into the app's own `.venv`. |
| 6 | Installs a systemd unit: runs as `sysdiag`, restarts on crash, starts on boot. The app listens on `127.0.0.1:8000` only. |
| 7 | Configures nginx: port 80 → VM app on `127.0.0.1:8000`, port 8080 → container on `127.0.0.1:8001`. Disables the default site. |
| 8 | Installs `/usr/local/bin/deploy-sysdiag`, the release script for the VM version. |
| 9 | Installs `/usr/local/bin/deploy-sysdiag-docker <tag>`, the release script for the Docker version. |
| 10 | Reads the live image tag from Parameter Store and starts the container with `deploy-sysdiag-docker`. |

Because the instance sets `user_data_replace_on_change = true`, any change to this script replaces the server on the next apply. App releases do **not** replace the server; they go through the deploy scripts.

### Security highlights

- **No stored AWS credentials.** Every pipeline uses GitHub OIDC with short-lived tokens.
- **Least privilege per pipeline:**
  - plan is read-only
  - apply is gated by a manual approval
  - the app pipeline can only target one tagged instance, push to one ECR repo and write one parameter
- **No SSH.** Port 22 is closed, there are no key pairs, and the instance has no public IP. Access is SSM only, controlled by IAM.
- **Layered network:**
  - the instance accepts traffic only from the ALB's security group
  - both app versions listen only on `127.0.0.1`; nginx is the only way in
- **Non-root app.** The VM app runs as a dedicated service account, and the container runs as uid 10001. The deploy scripts live in a root-owned path, so the app cannot modify them.
- **Account guard.** `allowed_account_ids` in the provider stops Terraform from ever running against the wrong AWS account.
- **State protection.** The state bucket is versioned and encrypted, and its lock file prevents concurrent writes.

---

## Phase 2: Containers (Docker)

Goal: build the app **once** as an image and run that exact image everywhere, with rollback by image tag.

### Architecture

```
                                   Internet
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
              ALB listener :80                    ALB listener :8080
              target group "vm"                   target group "docker"
              (health: /health on 80)             (health: /health on 8080)
                    │                                   │
┌─────────────── EC2 (private subnet) ──────────────────┼─────────────────────┐
│                   ▼                                   ▼                     │
│            nginx :80                            nginx :8080                 │
│                   │                                   │                     │
│                   ▼                                   ▼                     │
│     uvicorn 127.0.0.1:8000              Docker port 127.0.0.1:8001          │
│     (systemd, Phase 1)                         │                            │
│                                                ▼                            │
│                                  ┌─ container "sysdiag" ─┐                  │
│                                  │ uvicorn 0.0.0.0:8000  │                  │
│                                  │ user appuser (10001)  │                  │
│                                  └───────────────────────┘                  │
└──────────────────────────────────────────┬──────────────────────────────────┘
                                           │ pull with the instance role
                                           ▼
                     ECR  linux-diagnostic-tool:<git sha>
                     SSM Parameter Store  /devops-lab-dev/sysdiag/image-tag
```

Each version has its own target group, so each is health checked on its own. If the container fails, only `:8080` goes unhealthy.

### What changed from Phase 1

| | Phase 1 (VM) | Phase 2 (Docker) |
|---|---|---|
| What the server gets | source code (`git clone`) | a finished image from ECR |
| Dependencies installed | on every server, at deploy time | once, in CI, at build time |
| Runs the app | systemd unit | `docker run --restart unless-stopped` |
| App user | `sysdiag` service account on the host | `appuser` inside the image |
| Release | `git pull` + `uv sync` + restart | `docker pull <sha>` + swap the container |
| Rollback | check out an old commit and reinstall | run the previous tag (the image is often already on disk) |
| Same build everywhere? | no: two servers can resolve dependencies differently | yes: one image, identified by the commit SHA |

New infrastructure for this phase:
- `modules/ecr` + `environments/shared`: the ECR repository, with **immutable tags** (a tag can never be overwritten) and **scan on push**.
- `modules/alb`: a second listener, target group and attachment (port 8080), generated from the same map as port 80.
- `modules/ec2`:
  - `AmazonEC2ContainerRegistryReadOnly` on the instance role
  - port 8080 from the ALB
  - the live image tag parameter
- `bootstrap/github-app-deploy.tf`: the app pipeline may push to the one repository and write the one parameter.

### Release pipeline

`ci.yaml` in the app repo, on every push to `master`:

```
test-and-build ──┬──► deploy-ec2          VM version:  SSM → deploy-sysdiag
 (pytest,        │
  docker build)  └──► publish-ecr         docker build -t <registry>/linux-diagnostic-tool:<git sha>
                           │              docker push
                           ▼
                      deploy-ec2-docker   SSM → deploy-sysdiag-docker <git sha>
                                              docker pull <sha>
                                              docker rm -f sysdiag
                                              docker run ... <sha>
                                              curl /health (with retries)
                           │
                           ▼ only if the health check passed
                      record the tag      put-parameter image-tag = <sha>
```

The image is tagged with the **commit SHA**, never `latest`, so every running container can be traced to the exact code it was built from.

### The live-version record

`/devops-lab-dev/sysdiag/image-tag` in SSM Parameter Store holds **the last version that passed its health check**.

- **The CI writes it** as the last step of a release. A failed deploy never reaches that step, so the record keeps pointing at the last good version.
- **A new server reads it** at boot (user_data step 10), so a replaced instance comes up on the current release, not on whatever tag was written in the code.
- **Terraform creates it** with an initial value and then ignores later changes to it (`lifecycle { ignore_changes = [value] }`), so an apply never rolls the version back.
- Its **History** tab is a free deploy log: every version, when it was set, and by which role.

What brings the app back in each case:

| Event | user_data runs? | What restores the app | Version |
|---|---|---|---|
| App crashes | no | Docker restart policy | same container |
| Server reboots | no | dockerd (systemd) + restart policy | same container |
| New or replacement server | yes | Parameter Store → `deploy-sysdiag-docker` | last good tag |

### Rollback

1. Find the previous good tag:
   ```bash
   aws ssm get-parameter-history --name /devops-lab-dev/sysdiag/image-tag \
     --query 'Parameters[].[Version,Value,LastModifiedUser]' --output table
   ```
2. Run it on the server (from an SSM session):
   ```bash
   sudo deploy-sysdiag-docker <previous sha>
   ```
3. Update the record from your laptop. A rollback isn't finished until the record matches what is running, otherwise the next new server boots the bad version:
   ```bash
   aws ssm put-parameter --name /devops-lab-dev/sysdiag/image-tag --value <previous sha> --overwrite
   ```

### Known limitations

- **A few seconds of downtime per release.** The old container is removed before the new one starts. Zero downtime needs two copies and a switch-over (blue/green behind nginx, or Kubernetes rolling updates in Phase 3).
- **One server.** A release or a replacement takes the app down briefly. Multi-AZ with an Auto Scaling Group is the next step.
- **Hardcoded values in `user_data.sh`**: the account ID and the parameter name. They should be passed in from Terraform (`templatefile`).
- **Base image CVEs.** ECR scanning reports HIGH findings in Debian packages of `python:3.12-slim` (glibc, zlib), not in the app code.

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
│   └── github-app-deploy.tf    #   role for the app repo: SSM deploy, ECR push, live-tag parameter
├── modules/                    # reusable building blocks
│   ├── network/                #   VPC, subnets, IGW, NAT, routes
│   ├── ec2/                    #   instance, SG, IAM role, user_data.sh, image tag parameter
│   ├── alb/                    #   load balancer, target groups, listeners (one per app version)
│   └── ecr/                    #   container image repository
├── environments/
│   ├── shared/                 # long-lived resources shared by all environments (ECR)
│   └── dev/                    # wires the modules together; one folder per environment
└── .github/workflows/
    ├── terraform.yml           # fmt → validate → plan → (approval) → apply shared, then dev
    └── terraform-destroy.yml   # manual, confirmed, approved teardown of dev
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
Then, in GitHub, create the environments **`shared`** and **`dev`**, each with a required reviewer, a deployment branch rule for `main`, and the variable `AWS_ROLE_ARN` set to the apply role's ARN.

### Deploy
Push to `main` and approve the `apply (shared)` and `apply (dev)` jobs, or re-run the latest workflow run. About 3-4 minutes later the app is live. Get the URL with:
```bash
cd environments/dev
terraform output -raw alb_dns_name
```
Then open `http://<alb-dns>/docs` (VM version) and `http://<alb-dns>:8080/docs` (Docker version).

### Connect to the server
```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

### Roll back the Docker version
See [Rollback](#rollback).

### Destroy
**Actions → terraform-destroy → Run workflow**, pick `dev`, type `destroy`, and approve.
Never destroy `bootstrap/` (it holds the state of every environment) or `shared` (it holds every image ever built).

### Troubleshooting

| Symptom | Where to look |
|---|---|
| App not reachable after deploy | `cloud-init status` and `sudo tail -50 /var/log/cloud-init-output.log` on the instance |
| VM app down or crash-looping | `systemctl status sysdiag` and `sudo journalctl -u sysdiag -n 50` |
| Docker app down | `sudo docker ps -a` and `sudo docker logs sysdiag` |
| `deploy-sysdiag-docker` fails on pull | image tag exists in ECR? instance role has ECR read? `/root/.docker/config.json` has the credential helper? |
| ALB returns 502/503 | Target group health in the console. Each version's health check calls `/health` through nginx on its own port. |
| `Error acquiring the state lock` | Make sure no pipeline or local run is active, then run `terraform force-unlock <LOCK_ID>` |

---

## Cost

The NAT gateway and ALB bill per hour (roughly $2/day together in ap-south-1), so the `dev` environment is created for a session and destroyed the same day. The bootstrap stack (S3 + IAM) and the `shared` stack (ECR, about $0.10 per GB of images per month) cost close to nothing and stay up.

---

## Tech stack

**Cloud:** AWS (VPC, EC2, ALB, NAT, IAM, SSM Session Manager / Run Command / Parameter Store, ECR, S3) · **IaC:** Terraform (modules, layered state, `for_each`, S3 remote state with native locking) · **CI/CD:** GitHub Actions, OIDC, environment approvals · **Server:** Ubuntu 24.04, systemd, nginx · **Containers:** Docker, ECR credential helper · **App:** Python 3.12, FastAPI, uvicorn, uv
