# CredPal DevOps Assessment

> **Production-ready DevOps pipeline for a Node.js application** — containerized with Docker, automated via GitHub Actions CI/CD, provisioned with Terraform on AWS, and secured with HTTPS via Let's Encrypt.

![001-architecture-diagram.png](images/001-architecure-diagram.png)

---

##  Live Application

| Endpoint | URL |
|----------|-----|
| App Domain | [https://credpal.webredirect.org](https://credpal.webredirect.org) |
| Health Check | [https://credpal.webredirect.org/health](https://credpal.webredirect.org/health) |
| Status | [https://credpal.webredirect.org/status](https://credpal.webredirect.org/status) |
| ALB DNS | `credpal-alb-905443240.us-east-1.elb.amazonaws.com` |
| EC2 Public IP | `34.207.112.57` |

---

##  Project Structure

```
credpal-devops-assessment/
├── app/
│   ├── server.js               # Node.js Express application
│   ├── Dockerfile              # Multi-stage Docker build
│   ├── package.json
│   └── package-lock.json
├── terraform/
│   ├── main.tf                 # VPC, EC2, ALB, Security Groups
│   ├── variables.tf
│   └── outputs.tf
├── .github/
│   └── workflows/
│       └── deploy.yml          # GitHub Actions CI/CD pipeline
├── images/                     # Screenshots of deployment & infrastructure
├── docker-compose.yml          # Local development with PostgreSQL
├── .env.example                # Environment variable template
├── .dockerignore
├── .gitignore
└── README.md
```

---

##  Screenshots

All screenshots covering Docker, Terraform, EC2 deployment, CI/CD pipeline, ALB setup, and endpoint tests are in the [`images/`](./images/) folder.

| Screenshot | Description |
|------------|-------------|
| `images/docker-build.png` | Docker image build output |
| `images/docker-push.png` | Pushing image to Docker Hub |
| `images/github-actions.png` | GitHub Actions CI/CD pipeline passing |
| `images/terraform-apply.png` | Terraform apply output with resource creation |
| `images/ec2-instance.png` | EC2 instance running in AWS Console |
| `images/alb-healthy.png` | ALB target group showing healthy target |
| `images/endpoint-tests.png` | curl tests for all API endpoints |
| `images/https-browser.png` | HTTPS live on credpal.webredirect.org |

---

##  Quick Start — Run Locally

### Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose
- Node.js 18+

### 1. Clone the repository

```
git clone https://github.com/oluwasomidotun0502/credpal-devops-assessment.git
cd credpal-devops-assessment
```

### 2. Set up environment variables

```
cp .env.example .env
# Edit .env with your values
```

`.env.example`:
```env
DB_USER=postgres
DB_PASSWORD=yoursecurepassword
DB_NAME=credpaldb
```

### 3. Start with Docker Compose

```
docker compose up --build
```

This starts both the Node.js app and a PostgreSQL database.

### 4. Test the endpoints

```
# Health check
curl http://localhost:3000/health
# Expected: {"status":"healthy"}

# Status
curl http://localhost:3000/status
# Expected: {"service":"running","uptime":...}

# Process (POST)
curl -X POST http://localhost:3000/process \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}'
# Expected: {"message":"Data processed","input":{"name":"test"}}
```

### 5. Run without Docker (optional)

```
cd app
npm install
node server.js
```

---

##  API Endpoints

| Method | Endpoint | Description | Response |
|--------|----------|-------------|----------|
| `GET` | `/` | Root welcome message | `Welcome to CredPal API` |
| `GET` | `/health` | Health check | `{"status":"healthy"}` |
| `GET` | `/status` | App status & uptime | `{"service":"running","uptime":...}` |
| `GET` | `/api` | API status | `{"message":"CredPal API is running"}` |
| `POST` | `/process` | Process JSON payload | `{"message":"Data processed","input":{...}}` |

---

##  Part 1 — Containerization

### Dockerfile (Multi-stage + Non-root User)

The Dockerfile uses a **multi-stage build** to keep the final image lean and runs the app as a **non-root user** for security:

```dockerfile
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY . .

FROM node:18-alpine
RUN apk add --no-cache curl
WORKDIR /app
COPY --from=builder /app .

# Non-root user
RUN addgroup -S nodegroup && adduser -S nodeuser -G nodegroup
USER nodeuser

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:3000/health || exit 1
CMD ["node", "server.js"]
```

**Key decisions:**
- `node:18-alpine` — minimal base image (~50MB vs ~900MB for full Node)
- Multi-stage build — build dependencies are not included in the final image
- Non-root user — limits blast radius if the container is compromised
- Built-in `HEALTHCHECK` — Docker monitors app health automatically

### Docker Compose (with PostgreSQL)

```yaml
services:
  app:
    build: .
    ports:
      - "3000:3000"
    env_file:
      - .env
    depends_on:
      - db
    networks:
      - credpal-network
    restart: unless-stopped

  db:
    image: postgres:14
    env_file:
      - .env
    ports:
      - "5432:5432"
    networks:
      - credpal-network
    restart: unless-stopped

networks:
  credpal-network:
    driver: bridge
```

---

##  Part 2 — CI/CD (GitHub Actions)

Every push or pull request to `main` triggers the full pipeline automatically.

### Pipeline Flow

```
Push to main
    │
    ▼
Checkout code
    │
    ▼
Install dependencies (Node 18)
    │
    ▼
Build Docker image
    │
    ▼
Login to Docker Hub
    │
    ▼
Push image → oluwasomidotun0502/credpal-app:latest
    │
    ▼
SSH into EC2 → Pull latest image → Restart container
```

### GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `DOCKER_USERNAME` | Docker Hub username |
| `DOCKER_PASSWORD` | Docker Hub access token (not password) |
| `EC2_HOST` | EC2 public IP address |
| `EC2_SSH_KEY` | Private SSH key content for EC2 access |

>  **No secrets are hardcoded** — all sensitive values are stored as GitHub repository secrets and injected at runtime.

### Workflow File: `.github/workflows/deploy.yml`

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: 18

      - name: Install dependencies
        run: npm install
        working-directory: ./app

      - name: Build Docker image
        run: docker build -t oluwasomidotun0502/credpal-app:latest ./app

      - name: Log in to Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Push Docker image
        run: docker push oluwasomidotun0502/credpal-app:latest

      - name: Deploy to EC2
        uses: appleboy/ssh-action@v0.1.6
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ubuntu
          key: ${{ secrets.EC2_SSH_KEY }}
          script: |
            docker pull oluwasomidotun0502/credpal-app:latest
            docker stop $(docker ps -q) || true
            docker run -d -p 3000:3000 --restart always oluwasomidotun0502/credpal-app:latest
```

---

##  Part 3 — Infrastructure as Code (Terraform)

All AWS infrastructure is defined as code in the `terraform/` directory.

### Resources Provisioned

| Resource | Name | Purpose |
|----------|------|---------|
| VPC | `credpal-vpc` | Isolated network (`10.0.0.0/16`) |
| Subnet (AZ-a) | `credpal-public-subnet` | Primary subnet (`10.0.1.0/24`) |
| Subnet (AZ-b) | `credpal-public-subnet-2` | ALB requires 2 AZs (`10.0.2.0/24`) |
| Internet Gateway | `credpal-gateway` | Public internet access |
| Route Table | `public-rt` | Routes traffic to IGW |
| Security Group | `credpal-web-sg` | SSH, HTTP, HTTPS, port 3000 |
| EC2 Instance | `credpal-app-server` | `t2.micro` running the app |
| Application Load Balancer | `credpal-alb` | Distributes traffic across AZs |
| Target Group | `credpal-tg` | Routes ALB to EC2 on port 3000 |

### Deploy Infrastructure

```
cd terraform

# Install Terraform (WSL/Ubuntu)
sudo apt update && sudo apt install terraform -y

# Configure AWS credentials
aws configure

# Initialize
terraform init

# Preview changes
terraform plan

# Apply
terraform apply
```

### Outputs

```
alb_dns_name = "credpal-alb-905443240.us-east-1.elb.amazonaws.com"
app_public_ip = "34.207.112.57"
app_domain = "https://credpal.webredirect.org"
```

---

##  Part 4 — Deployment Strategy

### Zero-Downtime Deployment

The deployment uses a **rolling restart** strategy via the CI/CD pipeline:

1. New Docker image is built and pushed to Docker Hub
2. EC2 pulls the latest image
3. Old container is stopped
4. New container starts immediately with `--restart always`

The container's built-in `HEALTHCHECK` ensures Docker monitors app availability after each restart.

### Manual Approval (Production)

For production deployments, a manual approval step can be added to the GitHub Actions workflow using GitHub Environments with required reviewers — preventing accidental deployments to production.

---

##  Part 5 — Security & Observability

### Secrets Management

- All secrets (Docker credentials, EC2 SSH key) stored as **GitHub repository secrets**
- `.env` file is **gitignored** — never committed to version control
- `.env.example` provides a safe template with no real values
- AWS credentials configured via `aws configure` — never hardcoded in Terraform files

### HTTPS / SSL

HTTPS is configured using **Let's Encrypt** via Certbot + Nginx:

```
sudo certbot --nginx -d credpal.webredirect.org
```

Nginx is configured to:
- Redirect all HTTP (`port 80`) → HTTPS (`port 443`) automatically
- Proxy HTTPS traffic to the Node.js app on `localhost:3000`

### Non-Root Container User

The Docker container runs as a non-root user (`nodeuser`) — ensuring the Node.js process cannot escalate privileges even if compromised:

```dockerfile
RUN addgroup -S nodegroup && adduser -S nodeuser -G nodegroup
USER nodeuser
```

### Nginx as Reverse Proxy + Load Balancer

Nginx sits in front of the Node.js app and acts as both a reverse proxy and load balancer. Adding more backend servers is as simple as adding entries to the `upstream` block:

```nginx
upstream credpal_backend {
    server localhost:3000;
    # server 10.0.1.x:3000;  # scale horizontally
}
```

###  Health Check Monitoring

Health checks are implemented at **two independent layers**, providing defense-in-depth observability:

#### Layer 1 — Docker HEALTHCHECK (Container Level)

Defined directly in the Dockerfile, Docker monitors the app from inside the container every 30 seconds:

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s \
  CMD curl -f http://localhost:3000/health || exit 1
```

| Setting | Value | Meaning |
|---------|-------|---------|
| `interval` | 30s | Check every 30 seconds |
| `timeout` | 3s | Fail if no response within 3s |
| `healthy_threshold` | 2 | 2 consecutive passes = healthy |
| `unhealthy_threshold` | 2 | 2 consecutive failures = unhealthy |

If the container becomes unhealthy, Docker marks it and the `--restart always` policy automatically restarts it.

```
# Check container health status
sudo docker ps
# STATUS column shows: Up X minutes (healthy)

# View health check history
sudo docker inspect --format='{{json .State.Health}}' <container_id> | jq
```

#### Layer 2 — AWS ALB Health Check (Infrastructure Level)

The Application Load Balancer independently polls `/health` on port 3000 every 30 seconds:

```hcl
health_check {
  path                = "/health"
  protocol            = "HTTP"
  matcher             = "200"
  interval            = 30
  timeout             = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2
}
```

If the EC2 instance fails 2 consecutive health checks, the ALB **automatically removes it from the rotation** and stops routing traffic to it — ensuring zero unhealthy requests reach users.

You can verify the ALB target health status in the AWS Console under **EC2 → Target Groups → credpal-tg → Targets**:

```
 1 Healthy    0 Unhealthy   ○ 0 Unused
```

#### Health Check Endpoint Response

```
curl https://credpal.webredirect.org/health
# {"status":"healthy"}
```

### Logging

- **Application logs**: Express logs all requests and processing events via `console.log`
- **Nginx access logs**: Every HTTP request logged at `/var/log/nginx/access.log`
- **Nginx error logs**: Proxy and SSL errors at `/var/log/nginx/error.log`

```
# Live application logs
sudo docker logs -f $(sudo docker ps -q)

# Nginx access log
sudo tail -f /var/log/nginx/access.log

# Nginx error log
sudo tail -f /var/log/nginx/error.log

# Check container health
sudo docker inspect --format='{{.State.Health.Status}}' $(sudo docker ps -q)
```

---

##  How to Deploy the Application

### Manual Deployment to EC2

```
# SSH into EC2
ssh -i ~/.ssh/id_rsa ubuntu@34.207.112.57

# Pull latest image
sudo docker pull oluwasomidotun0502/credpal-app:latest

# Stop running containers
sudo docker stop $(sudo docker ps -q)

# Run new container
sudo docker run -d -p 3000:3000 --restart always oluwasomidotun0502/credpal-app:latest
```

### Automated Deployment (CI/CD)

Simply push to `main`:

```
git add .
git commit -m "Your changes"
git push origin main
```

GitHub Actions will automatically build, push, and deploy the new version to EC2.

### Verify Deployment

```
curl https://credpal.webredirect.org/health
curl https://credpal.webredirect.org/api
curl https://credpal.webredirect.org/status
curl -X POST https://credpal.webredirect.org/process \
  -H "Content-Type: application/json" \
  -d '{"name":"test"}'
```

---

##  Key Decisions

### Why Docker multi-stage build?
Keeps the production image small and free of build-time dependencies, reducing attack surface and improving pull times.

### Why Terraform?
Infrastructure as code ensures the entire AWS environment is reproducible, version-controlled, and auditable. Any team member can spin up an identical environment with `terraform apply`.

### Why ALB across two AZs?
AWS requires an Application Load Balancer to span at least two Availability Zones. This also provides high availability — if one AZ goes down, traffic is automatically routed to the other.

### Why Nginx as reverse proxy?
Nginx handles SSL termination, HTTP→HTTPS redirects, and can load balance to multiple backend containers without requiring changes to the application code.

### Why GitHub Actions?
Native GitHub integration means no additional CI/CD tooling. Secrets are managed securely, and the pipeline is version-controlled alongside the application code.

---

##  Tech Stack

| Layer | Technology |
|-------|-----------|
| Application | Node.js 18, Express |
| Containerization | Docker, Docker Compose |
| CI/CD | GitHub Actions |
| Infrastructure | Terraform, AWS |
| Compute | EC2 (`t2.micro`) |
| Networking | VPC, ALB, Security Groups |
| Web Server | Nginx (reverse proxy + load balancer) |
| SSL | Let's Encrypt (Certbot) |
| Registry | Docker Hub |

---

##  Author

**Oluwasomidotun Adepitan**
- Docker Hub: [oluwasomidotun0502](https://hub.docker.com/u/oluwasomidotun0502)
- Email: anuoluwapodotun@gmail.com
- Linkedln: https://www.linkedin.com/in/oluwasomidotun-adepitan?utm_source=share&utm_campaign=share_via&utm_content=profile&utm_medium=ios_app