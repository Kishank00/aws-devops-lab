# AWS DevOps Lab

A hands-on DevOps project. One real application, [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool) (a FastAPI service), is deployed on AWS once for each era of DevOps:

| Phase | How the app runs | Status |
|---|---|---|
| **1. Virtual machines** | EC2 + systemd + nginx, the classic "on-prem" way, fully automated | ✅ Done |
| **2. Containers** | Docker image built by CI, stored in ECR, run on the same EC2 next to the VM version | ✅ Done |
| **3. Scaling and high availability** | Auto Scaling Group across 2 AZs, self-healing, rolling replacement, immutable releases | ✅ Done: zero-downtime release and self-healing tested (rollout speed-up merged, to be measured) |
| **4. Orchestration** | Kubernetes | 🔜 Planned |

All infrastructure is Terraform. All deployments run through GitHub Actions with OIDC, so no AWS keys are stored anywhere.

Phases 1 and 2 run **side by side on every server**, so the two approaches can be compared directly:

| URL | Version |
|---|---|
| `http://<alb-dns>/` | Phase 1: app installed on the VM, run by systemd |
| `http://<alb-dns>:8080/` | Phase 2: the same app as a Docker container |

### Browse the code of each phase

Every finished phase is tagged with the same name in both repos, so the code of any era can be opened as it was (GitHub branch dropdown → **Tags**, or `git checkout <tag>`):

| Tag | What the code does | Infrastructure | App CI |
|---|---|---|---|
| `phase-1-vm-ec2` | one EC2, app on systemd + nginx, released over SSM | [aws-devops-lab](https://github.com/Kishank00/aws-devops-lab/tree/phase-1-vm-ec2) | [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool/tree/phase-1-vm-ec2) |
| `phase-2-docker-ecr` | + the app as a Docker container from ECR on the same EC2, live tag in Parameter Store | [aws-devops-lab](https://github.com/Kishank00/aws-devops-lab/tree/phase-2-docker-ecr) | [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool/tree/phase-2-docker-ecr) |
| `phase-3-autoscaling-asg` | Auto Scaling Group across 2 AZs, instance refresh, immutable releases; servers configured at boot by user_data ("fry") | [aws-devops-lab](https://github.com/Kishank00/aws-devops-lab/tree/phase-3-autoscaling-asg) | [linux-diagnostic-tool](https://github.com/Kishank00/linux-diagnostic-tool/tree/phase-3-autoscaling-asg) |
| `phase-3b-packer-ami-build` | Packer + Ansible template that bakes the server software into an AMI (not yet used by Terraform) | [aws-devops-lab](https://github.com/Kishank00/aws-devops-lab/tree/phase-3b-packer-ami-build) | (no change) |

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
  - [Release pipeline (Phase 2 version)](#release-pipeline-phase-2-version)
  - [The live-version record](#the-live-version-record)
  - [Known limitations](#known-limitations)
- [Phase 3: Scaling and high availability (ASG)](#phase-3-scaling-and-high-availability-asg)
  - [Architecture](#architecture-2)
  - [What changed from Phase 2](#what-changed-from-phase-2)
  - [How the ASG keeps the app running](#how-the-asg-keeps-the-app-running)
  - [Infrastructure changes: instance refresh](#infrastructure-changes-instance-refresh)
  - [Release pipeline: replace, don't patch](#release-pipeline-replace-dont-patch)
  - [Rollback](#rollback)
  - [Test results](#test-results)
  - [Lessons learned](#lessons-learned)
  - [Known limitations](#known-limitations-1)
- [Phase 4: Orchestration (Kubernetes)](#phase-4-orchestration-kubernetes)
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

In Phases 1 and 2 this was a single `aws_instance`. Phase 3 replaced it with an Auto Scaling Group; the server itself is configured exactly the same way.

### What is built

Everything below is Terraform, organised as reusable modules that an environment folder wires together.

| Module | Resources |
|---|---|
| `modules/network` | VPC, 2 public + 2 private subnets across 2 AZs, internet gateway, NAT gateway, route tables. Subnets are created from lists (`count`), so adding an AZ is a tfvars change. |
| `modules/ec2` | Launch template (Ubuntu 24.04, boot script `user_data.sh`) and an Auto Scaling Group across the private subnets (Phase 3), security group (inbound only from the ALB), IAM role + instance profile, and the live image tag parameter (Phase 2). |
| `modules/alb` | Internet-facing Application Load Balancer, its security group, and one target group and listener per app version, all generated from one map (`local.app_ports`). It outputs the target group ARNs for the ASG. |
| `modules/ecr` | One private ECR repository with immutable tags and scan on push (Phase 2). |

Terraform is split into **layers**, each with its own state file, by how long the resources live:

| Layer | Contains | Lifetime | Applied by |
|---|---|---|---|
| `bootstrap/` | S3 state bucket, GitHub OIDC provider, the CI roles | permanent, **never destroyed** | an admin, by hand (the pipeline cannot manage its own permissions) |
| `environments/shared` | ECR repositories (`for_each` over app names) | long-lived, survives env teardowns | pipeline |
| `environments/dev` | network, ec2, alb | created for a session, destroyed the same day | pipeline |

`environments/dev` calls the modules and passes outputs between them:
- network → ec2: VPC ID and the private subnet IDs;
- network → alb: VPC ID and the public subnet IDs;
- alb → ec2: the ALB security group ID and the target group ARNs.

Roles in `bootstrap/`:

| Role | Can do | Who can assume it |
|---|---|---|
| `github-actions-terraform` | read-only, for `plan` | any branch or PR of this repo |
| `github-actions-terraform-apply` | admin, for `apply`/`destroy` | only jobs in the approved `dev` or `shared` GitHub environments |
| `github-actions-app-deploy` | push to the `linux-diagnostic-tool` ECR repo, read and write the one live-tag parameter, start, cancel and watch an instance refresh on `devops-lab-dev-asg` only (plus SSM commands on instances tagged `devops-lab-dev-diagnostic`, from Phase 2) | only the `master` branch of the **app repo** |

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

Covered in [Release pipeline: replace, don't patch](#release-pipeline-replace-dont-patch). Every push to `master` replaces all servers with fresh ones running the new version.

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

A full boot takes about 3-4 minutes. Since Phase 3, a change to this script creates a new **launch template version**, and an instance refresh rolls it out (see [Infrastructure changes](#infrastructure-changes-instance-refresh)).

### Security highlights

- **No stored AWS credentials.** Every pipeline uses GitHub OIDC with short-lived tokens.
- **Least privilege per pipeline:**
  - plan is read-only
  - apply is gated by a manual approval
  - the app pipeline can only push to one ECR repo, write one parameter and refresh one ASG
- **No SSH.** Port 22 is closed, there are no key pairs, and the instances have no public IP. Access is SSM only, controlled by IAM.
- **Layered network:**
  - the instances accept traffic only from the ALB's security group
  - both app versions listen only on `127.0.0.1`; nginx is the only way in
- **Non-root app.** The VM app runs as a dedicated service account, and the container runs as uid 10001. The deploy scripts live in a root-owned path, so the app cannot modify them.
- **No secrets in user_data.** It is only base64-encoded (readable by anyone with EC2 describe rights and by any process on the instance), so it holds pointers such as a parameter name, never passwords.
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
- `modules/alb`: a second listener and target group (port 8080), generated from the same map as port 80.
- `modules/ec2`:
  - `AmazonEC2ContainerRegistryReadOnly` on the instance role
  - port 8080 from the ALB
  - the live image tag parameter
- `bootstrap/github-app-deploy.tf`: the app pipeline may push to the one repository and write the one parameter.

### Release pipeline (Phase 2 version)

> Replaced in Phase 3 by [replace, don't patch](#release-pipeline-replace-dont-patch). Kept here because it shows the "patch in place" approach that Phase 3 moves away from.

With one server, the app CI **patched** it in place over SSM Run Command:

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

The two deploy scripts are still installed on every server, as an emergency tool: `sudo deploy-sysdiag-docker <sha>` from an SSM session swaps the container on that one server.

### The live-version record

`/devops-lab-dev/sysdiag/image-tag` in SSM Parameter Store holds **the version every server should run**.

- **A new server reads it** at boot (user_data step 10), so a scale-out or replacement instance comes up on the current release, not on whatever tag was written in the code. With an Auto Scaling Group (Phase 3) this happens all the time, which is why the record exists.
- **The CI writes it.** In Phase 2 it was written *after* a successful deploy. In Phase 3 it is written *before* the instance refresh, because the new servers must read it at boot, and the CI puts the old value back if the release fails.
- **Terraform creates it** with an initial value and then ignores later changes to it (`lifecycle { ignore_changes = [value] }`), so an apply never rolls the version back.
- Its **History** tab is a free deploy log: every version, when it was set, and by which role.

What brings the app back in each case:

| Event | user_data runs? | What restores the app | Version |
|---|---|---|---|
| App crashes | no | Docker restart policy | same container |
| Server reboots | no | dockerd (systemd) + restart policy | same container |
| Server fails its health check | yes, on the replacement | ASG launches a new server, which reads Parameter Store | current tag |
| New server (scale-out, refresh) | yes | Parameter Store → `deploy-sysdiag-docker` | current tag |

### Known limitations

- **A few seconds of downtime per release.** The old container is removed before the new one starts. *Fixed in Phase 3: releases now replace servers, and the ALB drains the old ones first.*
- **One server.** *Fixed in Phase 3: two servers in two AZs.*
- **Hardcoded values in `user_data.sh`**: the account ID and the parameter name. They should be passed in from Terraform (`templatefile`).
- **Base image CVEs.** ECR scanning reports HIGH findings in Debian packages of `python:3.12-slim` (glibc, zlib), not in the app code.

---

## Phase 3: Scaling and high availability (ASG)

Goal: no single server and no single AZ. A dead server is replaced automatically, and both infrastructure changes and app releases roll out with zero downtime.

### Architecture

```
                              Internet
                                 │
                      ┌──────────▼───────────┐
                      │  ALB (AZ a + b)      │  :80 → tg "vm"   :8080 → tg "docker"
                      └───┬──────────────▲───┘
            traffic       │              │ ASG registers / deregisters
                          │              │ instances automatically
          ap-south-1a     │              │                 ap-south-1b
   ┌──────────────────────▼───┐      ┌───┴──────────────────────────┐
   │ private subnet 10.0.2.0  │      │ private subnet 10.0.4.0      │
   │  ┌────────────────────┐  │      │  ┌────────────────────┐      │
   │  │ instance           │  │      │  │ instance           │      │
   │  │ nginx, VM app,     │  │      │  │ nginx, VM app,     │      │
   │  │ container          │  │      │  │ container          │      │
   │  └────────────────────┘  │      │  └────────────────────┘      │
   └────────────▲─────────────┘      └─────────────▲────────────────┘
                │                                  │
            ┌───┴──────────────────────────────────┴───┐
            │  Auto Scaling Group  devops-lab-dev-asg  │  min 2 / desired 2 / max 4
            │  health check: ELB (/health on 80 + 8080)│  grace period 600 s
            └───────────────────┬──────────────────────┘
                                │ launches from
                    ┌───────────▼────────────┐
                    │ Launch template (vN)   │  AMI, t3.micro, SG, IAM role,
                    └────────────────────────┘  user_data, Name tag
```

The ALB never talks to the ASG. Traffic goes ALB → target group → instances; the ASG only keeps the target groups' instance list correct.

### What changed from Phase 2

| | Phase 2 | Phase 3 |
|---|---|---|
| Servers | one `aws_instance` in AZ a | `aws_launch_template` + `aws_autoscaling_group`, 2 instances, one per AZ |
| Subnets passed to ec2 | `private_subnet_ids[0]` | all private subnets (`subnet_ids`) |
| Target group registration | `aws_lb_target_group_attachment` with a fixed instance ID | the ASG registers each instance it launches (`target_group_arns`) |
| A server dies | the site is down until someone runs Terraform | the ASG replaces it |
| An AZ goes down | the site is down | the other AZ keeps serving; the ASG relaunches there |
| user_data change | instance destroyed, then created (downtime) | new template version, instance refresh (no downtime) |
| App release | SSM patches the running server | servers are replaced by fresh ones (immutable) |

Kubernetes equivalents, for orientation:

| AWS | Kubernetes |
|---|---|
| launch template | pod template |
| ASG + desired capacity | ReplicaSet + replicas |
| spreading over subnets in 2 AZs | topology spread constraints on zones |
| ELB health check + replacement | liveness probe + restart |
| health check grace period | `initialDelaySeconds` |
| target group registration | Service endpoints |
| instance refresh | Deployment rolling update |

### How the ASG keeps the app running

The ASG is a control loop: it compares healthy instances with the desired count and fixes the difference.

```
healthy == desired (2)?  ── yes ──► check again
        │ no
        ▼
  pick the AZ with the fewest instances
  launch from the launch template
  register in both target groups
  wait for the grace period (600 s), then trust the ALB health check
        healthy   → keep
        unhealthy → deregister, terminate, launch a replacement
```

- **AZ balance.** Each subnet lives in one AZ, so two subnets give the ASG two AZs. It launches into the AZ with the fewest instances. If an AZ cannot take an instance, it launches in the other one and rebalances later.
- **Health check type `ELB`.** The default (`EC2`) only checks that the VM is powered on. `ELB` uses the target groups' `/health` checks, so a broken app gets its server replaced too. An instance must be healthy in **both** target groups.
- **Grace period 600 s.** user_data takes 3-4 minutes. Without a grace period, the ASG would see a booting server as unhealthy, kill it, and loop forever.

### Infrastructure changes: instance refresh

```hcl
launch_template {
  id      = aws_launch_template.app.id
  version = aws_launch_template.app.latest_version   # not "$Latest"
}
instance_refresh {
  strategy = "Rolling"
  preferences {
    min_healthy_percentage = 100   # never fewer than 2 healthy (maxUnavailable: 0)
    max_healthy_percentage = 200   # may run 4 during the refresh (maxSurge: 100%)
  }
}
```

1. A change to the launch template (for example `user_data.sh`) creates a **new version** (`update_default_version = true`).
2. Because the ASG references `latest_version` (a number Terraform can see change), the plan updates the ASG and Terraform starts an **instance refresh**. With `"$Latest"`, Terraform would see no change and the running servers would stay on the old version.
3. With 100/200, the refresh **launches new instances first**, waits until they are healthy, then terminates the old ones. Capacity never drops.

```
start:   [v1] [v1]
step 1:  [v1] [v1] [v2…] [v2…]   launch new (up to 200%)
step 2:  [v1] [v1] [v2✓] [v2✓]   new ones pass /health
step 3:            [v2✓] [v2✓]   old ones drained and terminated
```

Two timers decide how long a refresh takes:

| Setting | Value | Why |
|---|---|---|
| `default_instance_warmup` (ASG) | 300 s | how long a new instance must be in service before the refresh trusts it and moves on. It must cover the real boot time (3-4 min), because during the grace period the ASG counts a still-booting instance as healthy. Set on the ASG, so it applies to every refresh (Terraform's and the CI's) and to scaling policies. Without it, the warmup falls back to the 600 s grace period. |
| `deregistration_delay` (target groups) | 30 s | how long the ALB drains an old instance before it is terminated. The default is 300 s; this app's requests take milliseconds. |

### Release pipeline: replace, don't patch

There are two ways to put a new version on servers: **patch** them (Phase 2, Ansible, SSM) or **replace** them with fresh ones (Kubernetes, Spinnaker, CodeDeploy blue/green). Phase 3 replaces. Every server is then fresh and identical, the ALB drains old servers so no request fails, and nothing drifts.

The app version is not in the launch template. The template says "read the tag from Parameter Store", so a release only changes the parameter and replaces the servers. No Terraform runs for an app release.

`ci.yaml` in the app repo, on every push to `master`:

```
test-and-build ──► publish-ecr ──► deploy-asg
 (pytest,          (build + push    1. read the live tag     (kept for rollback)
  docker build)     :<git sha>)     2. write the new tag     (new servers read it at boot)
                                    3. start-instance-refresh (100/200)
                                    4. poll every 30 s until Successful / Failed (30 min max)
                                    5. on failure: restore the old tag, cancel the refresh,
                                       start a rollback refresh
```

- One job updates **both** versions: new servers clone `master` (VM version) and pull the tagged image (Docker version) at boot.
- The CI passes the 100/200 preferences itself. The `instance_refresh` block in Terraform only applies to refreshes that Terraform starts; a refresh started from the CLI would otherwise use the AWS default (90%), which terminates one of the two servers first.
- The job runs in a `deploy-asg` concurrency group that never cancels a running deploy, so two refreshes never overlap.
- A release takes several minutes, because every server boots from scratch (see [Test results](#test-results)). Baking the app into an AMI (Packer) is the planned fix.

### Rollback

**Automatic:** if the refresh fails or times out, the CI restores the previous tag in Parameter Store, cancels the refresh and starts a new one, so every server comes back on the old version. The CI job is still marked failed, and it does not wait for the rollback refresh to finish.

**Manual:**
1. Find the previous good tag:
   ```bash
   aws ssm get-parameter-history --name /devops-lab-dev/sysdiag/image-tag \
     --query 'Parameters[].[Version,Value,LastModifiedUser]' --output table
   ```
2. Point the record at it:
   ```bash
   aws ssm put-parameter --name /devops-lab-dev/sysdiag/image-tag --value <previous sha> --overwrite
   ```
3. Replace the servers so they boot that version:
   ```bash
   aws autoscaling start-instance-refresh --auto-scaling-group-name devops-lab-dev-asg \
     --preferences '{"MinHealthyPercentage":100,"MaxHealthyPercentage":200}'
   ```

**Emergency (one server, seconds instead of minutes):** from an SSM session, `sudo deploy-sysdiag-docker <previous sha>`. This patches only that server, so finish with steps 2 and 3, or the next new server boots the bad version.

### Test results

Both tests ran against the live dev environment on 2026-10-24, with a probe hitting `/health` on `:80` and `:8080` through the ALB every 2 seconds.

**1. Release by instance refresh** (app commit `5bcc666`, pushed to `master`):

| Measure | Result |
|---|---|
| Health probes during the rollout | 400, **0 failed** |
| Refresh duration | 15 min 42 s |
| Result | both new instances (AZ a and b) run `linux-diagnostic-tool:5bcc666`, and the parameter holds the new tag |

Where the 15 minutes went:

```
~1.5 min  test, build and push the image
~3-4 min  new instances boot (user_data)       ← real work
~6 min    waiting for the 600 s warmup          ← timer
~5 min    draining the old instances (300 s)    ← timer
```

The timers were then cut to 300 s warmup and 30 s drain (see [Infrastructure changes](#infrastructure-changes-instance-refresh)), which should bring a release to about 6-7 minutes. Not measured yet.

**2. Self-healing** (one instance terminated by hand in the console):

| Time | Event |
|---|---|
| t+0 | instance in AZ a terminated |
| t+33 s | ASG takes it out of service ("EC2 health check indicating it has been terminated") |
| t+34 s | replacement launched, **in the same AZ** (AZ balancing) |
| t+3 min 20 s | replacement healthy in both target groups |

5 of 80 probes failed (502 or timeout), all in the first ~15 seconds. A crash is not a graceful refresh: the ALB keeps sending requests to the dead instance until its health checks fail. A shorter health check interval and a lower unhealthy threshold would shrink that window. After that, the surviving instance in AZ b served everything.

### Lessons learned

- **The first ASG in an account can fail with "Access denied when attempting to assume role AWSServiceRoleForAutoScaling".** AWS creates that service-linked role on the first `CreateAutoScalingGroup`, and IAM takes a minute or two to make a new role usable. The ASG retried on its own and launched both instances, but Terraform had already seen the failed launches and marked the ASG as tainted. Re-running the apply replaced it cleanly. This happens once per account.
- **ALB fails open.** While the containers were still starting, every target in the `docker` group was unhealthy, yet `:8080/health` already answered. When all targets in a group are unhealthy, the ALB sends traffic to all of them anyway.
- **Most of a slow refresh is timers, not work.** Without an explicit warmup, the refresh waited for the full 600 s grace period, then the target groups drained for their default 300 s. Together they were about 11 of the 16 minutes.
- **Merging a PR seconds after opening it makes two pipeline runs plan at once**, and the second fails on the state lock. The plans now wait (`-lock-timeout=5m`), and the habit is to wait for the PR check before merging.
- **Docs examples copy in deprecated arguments.** The `aws_autoscaling_group` example uses `launch_configuration` (the 2009-era, now-deprecated predecessor of launch templates), `placement_group` and `force_delete`. Take only the arguments you need and check each one in the argument reference.

### Known limitations

- **One NAT gateway, in AZ a.** If AZ a fails, the AZ b instance loses outbound internet (no ECR pulls, no apt), so replacements cannot boot. Production uses one NAT per AZ; here it would roughly double the NAT cost.
- **Slow boots (fry, not bake).** Every server installs everything at boot, which takes 3-4 minutes and depends on apt, GitHub and ECR being reachable. A Packer-built AMI would boot in about a minute.
- **The VM version always deploys `master`.** New servers clone the latest `master`, not the commit that was tested, so the VM version is not pinned to a SHA the way the image is.
- **No scaling policy yet.** The ASG self-heals and spreads across AZs but does not scale on load. A target tracking policy on CPU is planned.
- **The rollback refresh is not watched.** If it also fails, it is only visible in the ASG console.

---

## Phase 4: Orchestration (Kubernetes)

> 🔜 **Planned.** This section will be filled in when the phase is built.

Goal: run the same app on EKS, where rolling updates, self-healing and service discovery are built into the platform instead of assembled from ASG, ALB and SSM.

<!-- Phase 4 sections, to add here:
### Architecture
### What changed from Phase 3
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
│   └── github-app-deploy.tf    #   role for the app repo: ECR push, live-tag parameter, instance refresh
├── modules/                    # reusable building blocks
│   ├── network/                #   VPC, subnets, IGW, NAT, routes
│   ├── ec2/                    #   launch template, ASG, SG, IAM role, user_data.sh, image tag parameter
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
Open a PR, wait for the `check` jobs and read the plan, then merge to `main` and approve the `apply (shared)` and `apply (dev)` jobs. The ASG launches 2 instances; about 4-5 minutes after the apply both are healthy. Get the URL with:
```bash
cd environments/dev
terraform output -raw alb_dns_name
```
Then open `http://<alb-dns>/docs` (VM version) and `http://<alb-dns>:8080/docs` (Docker version).

### Check the instances
```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names devops-lab-dev-asg \
  --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]' \
  --output table
```

### Connect to a server
Instance IDs change whenever the ASG replaces a server, so take one from the command above:
```bash
aws ssm start-session --target <instance-id>
```

### Roll back
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
| ASG keeps replacing instances | Boot takes longer than the grace period, or one target group stays unhealthy. Check the ASG **Activity** tab and cloud-init logs on a fresh instance. |
| Instance refresh fails | `aws autoscaling describe-instance-refreshes --auto-scaling-group-name devops-lab-dev-asg`. The status reason usually names the instance that never became healthy. |
| First apply: "Access denied ... AWSServiceRoleForAutoScaling" | IAM propagation of the newly created service-linked role. Re-run the failed apply job. See [Lessons learned](#lessons-learned). |
| `Error acquiring the state lock` | Make sure no pipeline or local run is active, then run `terraform force-unlock <LOCK_ID>` |

---

## Cost

The NAT gateway, the ALB and the two t3.micro instances bill per hour (roughly $2.5/day together in ap-south-1), so the `dev` environment is created for a session and destroyed the same day. An instance refresh briefly doubles the instance count. The bootstrap stack (S3 + IAM) and the `shared` stack (ECR, about $0.10 per GB of images per month) cost close to nothing and stay up.

---

## Tech stack

**Cloud:** AWS (VPC, EC2, Auto Scaling with launch templates and instance refresh, ALB, NAT, IAM, SSM Session Manager / Run Command / Parameter Store, ECR, S3) · **IaC:** Terraform (modules, layered state, `for_each`, `for` expressions, S3 remote state with native locking) · **CI/CD:** GitHub Actions, OIDC, environment approvals, immutable releases · **Server:** Ubuntu 24.04, systemd, nginx · **Containers:** Docker, ECR credential helper · **App:** Python 3.12, FastAPI, uvicorn, uv
