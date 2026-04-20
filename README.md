# MERN Task App — Full Infrastructure Guide

A full-stack task management application built with **MongoDB, Express, React, and Node.js**, packaged with Docker and backed by a complete CI/CD, monitoring, and infrastructure-as-code setup.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Prerequisites](#prerequisites)
3. [Production Deployment — Step by Step](#production-deployment--step-by-step)
   - [Step 1 — Push the repository to GitHub](#step-1--push-the-repository-to-github)
   - [Step 2 — Create a Docker Hub repository](#step-2--create-a-docker-hub-repository)
   - [Step 3 — Provision the VPS with Terraform](#step-3--provision-the-vps-with-terraform)
   - [Step 4 — Add GitHub repository secrets](#step-4--add-github-repository-secrets)
   - [Step 5 — Trigger the first CI/CD run](#step-5--trigger-the-first-cicd-run)
   - [Step 6 — Configure the server with Ansible](#step-6--configure-the-server-with-ansible)
   - [Step 7 — Verify everything is running](#step-7--verify-everything-is-running)
4. [Running Locally with Docker](#running-locally-with-docker)
5. [Monitoring — Grafana & Prometheus](#monitoring--grafana--prometheus)
6. [How CI/CD Works](#how-cicd-works)
7. [Environment Variables Reference](#environment-variables-reference)

---

## Project Structure

```
final-project/
├── src/
│   ├── backend/            # Express API (Node.js, ESM)
│   │   ├── Dockerfile
│   │   └── server.js
│   └── frontend/           # React app (CRA) served by Nginx
│       ├── Dockerfile
│       └── nginx.conf
├── monitoring/
│   ├── prometheus/
│   │   └── prometheus.yml  # Scrape config (node-exporter, mongo-exporter)
│   └── grafana/
│       ├── provisioning/   # Auto-provisioned datasource + dashboard provider
│       └── dashboards/     # Pre-built dashboard JSONs
├── .github/
│   └── workflows/
│       └── deploy.yml      # CI/CD pipeline
├── terraform/              # DigitalOcean droplet provisioning
├── ansible/                # Server setup + app deployment
├── docker-compose.yml
└── .env.example
```

---

## Prerequisites

| Tool                                                                   | Minimum Version | Install                            |
| ---------------------------------------------------------------------- | --------------- | ---------------------------------- |
| [Docker](https://docs.docker.com/get-docker/)                          | 24+             | Required locally and on the server |
| [Docker Compose](https://docs.docker.com/compose/)                     | v2 (plugin)     | Bundled with Docker Desktop        |
| [Terraform](https://developer.hashicorp.com/terraform/install)         | 1.5+            | Run on your local machine          |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | 2.15+           | Run on your local machine          |
| [Git](https://git-scm.com/)                                            | any             | Triggers CI/CD on push             |
| [Docker Hub account](https://hub.docker.com/)                          | —               | Stores built images                |
| [DigitalOcean account](https://cloud.digitalocean.com/)                | —               | Hosts the VPS                      |

---

## Production Deployment — Step by Step

Follow these steps in order for a brand-new production deployment.

---

### Step 1 — Push the repository to GitHub

If you haven't already, create a new GitHub repository and push this project to it.

```bash
git init
git remote add origin https://github.com/<your-username>/<your-repo>.git
git add .
git commit -m "Initial commit"
git push -u origin main
```

> The CI/CD pipeline triggers automatically on every push to `main`. Do **not** push secrets — `.env` and `terraform.tfvars` are in `.gitignore`.

---

### Step 2 — Create a Docker Hub repository

The CI/CD pipeline pushes two images to Docker Hub. Create them before the first run.

1. Log in to [hub.docker.com](https://hub.docker.com/)
2. Click **Create Repository**
3. Create a repository named **`mern-backend`** (visibility: Public or Private)
4. Repeat and create a repository named **`mern-frontend`**
5. Go to **Account Settings → Security → New Access Token**, create a token with **Read, Write, Delete** scope, and copy it — you will need it in Step 5.

---

### Step 3 — Provision the VPS with Terraform

Terraform creates a `s-2vcpu-4gb` Ubuntu 22.04 droplet in the Singapore (`sgp1`) region and attaches a firewall.

#### 3.1 — Generate an SSH key pair (if you don't have one)

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

#### 3.2 — Add your SSH public key to DigitalOcean

1. Log in to [DigitalOcean](https://cloud.digitalocean.com/)
2. Go to **Settings → Security → SSH Keys → Add SSH Key**
3. Paste the contents of `~/.ssh/id_rsa.pub`
4. Copy the **fingerprint** shown after saving (format: `aa:bb:cc:dd:...`)

#### 3.3 — Get a DigitalOcean API token

1. Go to **API → Personal access tokens → Generate New Token**
2. Give it **read + write** scope and copy the token

#### 3.4 — Configure Terraform variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
do_token        = "dop_v1_your_digitalocean_token_here"
ssh_fingerprint = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
```

> Never commit `terraform.tfvars` — it contains your API token and is already in `.gitignore`.

#### 3.5 — Apply

```bash
terraform init
terraform plan    # review what will be created
terraform apply   # type "yes" to confirm
```

#### 3.6 — Save the droplet IP

```bash
terraform output droplet_ip
```

Copy this IP — you need it for Steps 4 and 5.

---

### Step 4 — Add GitHub repository secrets

These secrets allow GitHub Actions to build and push images, and to SSH into the droplet for deployment. They must be in place **before** triggering the first pipeline run.

Go to your GitHub repository → **Settings → Secrets and variables → Actions → New repository secret** and add each of the following:

| Secret                   | Value                                           |
| ------------------------ | ----------------------------------------------- |
| `DOCKER_USERNAME`        | Your Docker Hub username                        |
| `DOCKER_PASSWORD`        | The Docker Hub access token from Step 2         |
| `SSH_PRIVATE_KEY`        | Full contents of your SSH private key file      |
| `DROPLET_IP`             | The IP from `terraform output droplet_ip`       |
| `MONGO_URI`              | `mongodb://mongo:27017/taskapp`                 |
| `JWT_SECRET`             | A random string, at least 32 characters         |
| `EMAIL_USER`             | Your Gmail address                              |
| `EMAIL_PASS`             | Your Gmail App Password                         |
| `GRAFANA_ADMIN_PASSWORD` | A strong password for the Grafana admin account |

> To copy your private key on Linux/macOS: `cat ~/.ssh/id_rsa` — paste the **entire** output including the `-----BEGIN` and `-----END` lines.

---

### Step 5 — Trigger the first CI/CD run

> **This must happen before Ansible.** Ansible runs `docker compose pull`, which requires the images to already exist on Docker Hub. The CI/CD pipeline is what builds and pushes them.

Push any change to `main` to trigger the full CI/CD pipeline:

```bash
git commit --allow-empty -m "trigger first CI/CD deployment"
git push origin main
```

Watch the pipeline run at `https://github.com/<your-username>/<your-repo>/actions`.

The pipeline has two sequential jobs:

```
build-and-push
  ├── Builds backend image  →  pushes to Docker Hub as mern-backend:latest + :<git-sha>
  └── Builds frontend image →  pushes to Docker Hub as mern-frontend:latest + :<git-sha>

deploy  (runs after build-and-push succeeds)
  ├── Copies docker-compose.yml + monitoring/ to /opt/app on the droplet via SCP
  ├── Writes /opt/app/.env from GitHub secrets via SSH
  └── Runs: docker compose pull && docker compose up -d --remove-orphans
```

Wait for the `deploy` job to show a green checkmark before continuing.

---

### Step 6 — Configure the server with Ansible

Ansible connects to the droplet, installs Docker, copies all application files, and starts every service. By this point the images already exist on Docker Hub (pushed in Step 5), so `docker compose pull` will succeed.

#### 6.1 — Update the inventory

Open [ansible/inventory.ini](ansible/inventory.ini) and replace `<DROPLET_IP>` with the IP from Step 3.6:

```ini
[droplet]
mern-app ansible_host=YOUR_DROPLET_IP ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_rsa
```

#### 6.2 — Create a secrets file (Ansible Vault)

```bash
cd ansible
ansible-vault create secrets.yml
```

Ansible will open your editor. Paste the following and fill in the **same values** you used in Step 4:

```yaml
mongo_uri: "mongodb://mongo:27017/taskapp"
jwt_secret: "same_jwt_secret_as_github_secret"
email_user: "your@gmail.com"
email_pass: "your_gmail_app_password"
docker_username: "your_dockerhub_username"
grafana_admin_password: "same_grafana_password_as_github_secret"
```

Save and close. The file is now AES-256 encrypted.

> **Gmail App Password:** Go to your Google Account → **Security → 2-Step Verification → App Passwords** to generate one. Do not use your main Gmail password.

#### 6.3 — Run the playbook

```bash
ansible-playbook -i inventory.ini playbook.yml \
  --extra-vars "@secrets.yml" \
  --ask-vault-pass
```

Enter the vault password when prompted. Ansible will:

1. Install Docker CE and the Compose plugin
2. Create `/opt/app` on the droplet
3. Copy `docker-compose.yml` and `monitoring/` to the droplet
4. Write `/opt/app/.env` from your vault variables
5. Pull images from Docker Hub and run `docker compose up -d`

The application is now live.

---

### Step 7 — Verify everything is running

Once the pipeline completes, open these URLs in your browser (replace `YOUR_DROPLET_IP`):

| Service        | URL                                   | Expected                              |
| -------------- | ------------------------------------- | ------------------------------------- |
| **App**        | `http://YOUR_DROPLET_IP`              | React login page                      |
| **Grafana**    | `http://YOUR_DROPLET_IP:3000`         | Grafana login (admin / your password) |
| **Prometheus** | `http://YOUR_DROPLET_IP:9090/targets` | All 3 targets showing `UP`            |

#### Verify containers on the droplet

SSH into the droplet and check all services are healthy:

```bash
ssh root@YOUR_DROPLET_IP
cd /opt/app
docker compose ps
```

Expected output — all services `running`:

```
NAME             STATUS
mongo            running
backend          running
frontend         running
prometheus       running
grafana          running
node-exporter    running
mongo-exporter   running
```

#### View live logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f backend
```

#### Grafana dashboards

Log in to Grafana at `http://YOUR_DROPLET_IP:3000` with username `admin` and your `GRAFANA_ADMIN_PASSWORD`. Go to **Dashboards → Browse** — two dashboards are pre-loaded:

| Dashboard                            | Panels                                                                  |
| ------------------------------------ | ----------------------------------------------------------------------- |
| **Node Exporter — Hardware Metrics** | CPU per core, memory, disk I/O, network traffic, system load, uptime    |
| **MongoDB — Database Metrics**       | Up/down status, active connections, ops/sec (CRUD), memory, network I/O |

---

## Running Locally with Docker

For local development without a VPS.

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd final-project
```

### 2. Create your environment file

```bash
cp .env.example .env
```

Open `.env` and fill in values:

```env
MONGO_URI=mongodb://mongo:27017/taskapp
JWT_SECRET=any_local_secret
PORT=8001

EMAIL_USER=your_email@gmail.com
EMAIL_PASS=your_gmail_app_password
EMAIL_FROM=your_email@gmail.com

DOCKER_USERNAME=your_dockerhub_username

GRAFANA_ADMIN_PASSWORD=admin
```

### 3. Start all services

```bash
docker compose up --build
```

### 4. Access

| Service        | URL                   |
| -------------- | --------------------- |
| **App**        | http://localhost      |
| **Grafana**    | http://localhost:3000 |
| **Prometheus** | http://localhost:9090 |

### 5. Stop

```bash
docker compose down          # keep database volume
docker compose down -v       # also wipe database
```

---

## Monitoring — Grafana & Prometheus

Monitoring starts automatically with `docker compose up` — no manual Grafana setup is required.

### How it works

```
node-exporter   (hardware metrics: CPU, memory, disk, network)
mongo-exporter  (MongoDB metrics: connections, ops, memory)
       │
       ▼  scraped every 15s
prometheus      (stores time-series data)
       │
       ▼  queried by
grafana         (visualises dashboards — auto-provisioned on startup)
```

### Prometheus scrape targets

Open `/targets` on Prometheus to verify all jobs are `UP`:

| Job                | Endpoint              | Metrics           |
| ------------------ | --------------------- | ----------------- |
| `prometheus`       | `localhost:9090`      | Self-monitoring   |
| `node-exporter`    | `node-exporter:9100`  | Host hardware     |
| `mongodb-exporter` | `mongo-exporter:9216` | MongoDB internals |

---

## How CI/CD Works

The workflow in [.github/workflows/deploy.yml](.github/workflows/deploy.yml) runs on every push to `main`.

### Pipeline

```
push to main
    │
    ▼
Job: build-and-push
    ├── docker/login-action     → logs in to Docker Hub
    ├── docker/build-push-action → builds + pushes mern-backend:latest + :<sha>
    └── docker/build-push-action → builds + pushes mern-frontend:latest + :<sha>
    │
    ▼ (only if build-and-push succeeded)
Job: deploy
    ├── appleboy/scp-action  → copies docker-compose.yml + monitoring/ to /opt/app
    └── appleboy/ssh-action  → writes .env, runs docker compose pull + up -d
```

### Re-deploying manually

If you need to redeploy without a code change:

```bash
git commit --allow-empty -m "redeploy"
git push origin main
```

### Teardown

To permanently destroy the VPS and all its data:

```bash
cd terraform
terraform destroy   # type "yes" to confirm
```

---

## Environment Variables Reference

| Variable                 | Required | Description                                                                                      |
| ------------------------ | -------- | ------------------------------------------------------------------------------------------------ |
| `MONGO_URI`              | Yes      | MongoDB connection string — always `mongodb://mongo:27017/taskapp` when using Docker             |
| `JWT_SECRET`             | Yes      | Secret key used to sign and verify JSON Web Tokens. Use a random 32+ character string            |
| `PORT`                   | No       | Backend port (default: `8001`)                                                                   |
| `EMAIL_USER`             | Yes      | Gmail address used to send password-reset emails                                                 |
| `EMAIL_PASS`             | Yes      | Gmail [App Password](https://support.google.com/accounts/answer/185833) — not your main password |
| `EMAIL_FROM`             | No       | Sender display address (defaults to `EMAIL_USER` if omitted)                                     |
| `DOCKER_USERNAME`        | Yes      | Docker Hub username — used to tag and pull images in `docker-compose.yml`                        |
| `GRAFANA_ADMIN_PASSWORD` | Yes      | Grafana `admin` account password                                                                 |
