# FastAPI Production Deployment

Production-ready deployment of a FastAPI service with Kubernetes, monitoring, and CI/CD.

## 🚀 Quick Start

```bash
# Build and run locally
docker build -t fastapi-service .
docker run -p 8000:8000 fastapi-service

# Deploy to Kubernetes
./scripts/deploy.sh production latest
```

## 📁 Project Structure

```
production-deployment/
├── Dockerfile              # Multi-stage, distroless build
├── main.py                # FastAPI application
├── requirements.txt       # Python dependencies
├── k8s/                   # Kubernetes manifests
│   ├── deployment.yaml    # App deployment (3 replicas, resource limits)
│   ├── service.yaml       # ClusterIP service
│   ├── ingress.yaml       # NGINX ingress with TLS
│   ├── hpa.yaml          # Auto-scaling (3-10 pods)
│   └── ...               # ConfigMap, secrets, RBAC, network policies
├── .github/workflows/     # CI/CD pipeline
│   └── deploy.yml        # Automated testing and deployment
├── monitoring/           # Observability stack
│   ├── prometheus.yml    # Metrics collection
│   ├── alerts.yml       # Alerting rules
│   └── grafana-dashboard.json
└── scripts/             # Automation tools
    ├── deploy.sh        # Deployment automation
    ├── health-check.sh  # Health validation
    └── rollback.sh     # Rollback procedures
```

## 🔧 Key Features

### Security

- **Distroless base image** - Minimal attack surface
- **Non-root user** - Container runs as user 65534
- **Network policies** - Restricted pod communication
- **RBAC** - Least privilege access
- **Secrets management** - Encrypted sensitive data
- **Container scanning** - Trivy vulnerability scanning

### High Availability

- **3+ replicas** - No single point of failure
- **Auto-scaling** - HPA scales 3-10 pods based on CPU/memory
- **Health checks** - Liveness, readiness, and startup probes
- **Rolling updates** - Zero-downtime deployments
- **Resource limits** - CPU: 100m-500m, Memory: 128Mi-512Mi

### Monitoring

- **Prometheus metrics** - Request rate, latency, errors
- **Grafana dashboards** - Real-time visualization
- **Alerting** - High error rate, pod restarts, certificate expiry
- **Health endpoints** - `/health` and `/ready`

## 🚦 CI/CD Pipeline

```mermaid
graph LR
    A[Push Code] --> B[Run Tests]
    B --> C[Build & Scan]
    C --> D[Test K8s Deploy]
    D --> E[Deploy Staging]
    E --> F[Deploy Production]
```

### Pipeline Stages

1. **Test** - Unit tests with pytest
1. **Build** - Multi-stage Docker build
1. **Scan** - Trivy security scanning
1. **Test Deploy** - Local kind cluster validation
1. **Staging** - Deploy to staging environment
1. **Production** - Deploy with manual approval

## 📊 Endpoints

|Endpoint  |Method|Description       |
|----------|------|------------------|
|`/health` |GET   |Health check      |
|`/ready`  |GET   |Readiness check   |
|`/metrics`|GET   |Prometheus metrics|
|`/items`  |GET   |List items        |
|`/items`  |POST  |Create item       |

## 🛠️ Deployment

### Prerequisites

- Docker
- Kubernetes cluster (or kind/minikube)
- kubectl configured
- NGINX Ingress Controller

### Deploy to Production

```bash
# 1. Create namespace
kubectl apply -f k8s/namespace.yaml

# 2. Create secrets
kubectl create secret generic fastapi-secrets \
  --from-literal=API_SECRET_KEY=your-secret \
  -n production

# 3. Deploy application
./scripts/deploy.sh production latest

# 4. Verify deployment
./scripts/health-check.sh production
```

### Local Testing with Kind

```bash
# Create cluster
kind create cluster --config kind-config.yaml

# Install NGINX Ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Deploy
./scripts/deploy.sh local latest
```

## 📈 Monitoring Setup

```bash
# Install Prometheus
helm install prometheus prometheus-community/kube-prometheus-stack

# Apply custom config
kubectl apply -f monitoring/prometheus.yml

# Access Grafana
kubectl port-forward svc/prometheus-grafana 3000:80
# Default: admin/prom-operator
```

## 🔄 Operations

### Rollback

```bash
# Rollback to previous version
./scripts/rollback.sh production

# Rollback to specific revision
./scripts/rollback.sh production 5
```

### Scaling

```bash
# Manual scaling
kubectl scale deployment/fastapi-service --replicas=5 -n production

# Update HPA limits
kubectl edit hpa fastapi-service -n production
```

### Troubleshooting

```bash
# Check pod logs
kubectl logs -l app=fastapi-service -n production --tail=100

# Describe pods
kubectl describe pods -l app=fastapi-service -n production

# Check metrics
kubectl top pods -l app=fastapi-service -n production
```

## 🔐 Security Considerations

- Container runs as non-root user
- Read-only root filesystem
- Network policies restrict traffic
- Secrets encrypted at rest
- Regular vulnerability scanning
- Pod security standards enforced

## 📝 Configuration

Environment variables via ConfigMap:

- `APP_ENV` - Environment name
- `LOG_LEVEL` - Logging verbosity
- `WORKERS` - Number of workers
- `RATE_LIMIT_ENABLED` - Enable rate limiting

Secrets via Secret:

- `API_SECRET_KEY` - API authentication
- `DATABASE_URL` - Database connection
- `REDIS_URL` - Cache connection

## 🎯 SLOs

- **Availability**: 99.9% uptime
- **Latency**: p95 < 200ms, p99 < 500ms
- **Error Rate**: < 0.1%
- **Pod Startup**: < 30 seconds

## 📚 Additional Resources

- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [Prometheus Monitoring](https://prometheus.io/docs/introduction/overview/)

-----

**Note**: Update image registry, ingress host, and secrets before production deployment.
