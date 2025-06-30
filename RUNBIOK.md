# FastAPI Service Runbook

Operational procedures for managing the FastAPI service in production.

## 🚨 Incident Response

### Service Down

**Symptoms**: Health checks failing, no response from endpoints

**Actions**:

1. Check pod status:
   
   ```bash
   kubectl get pods -l app=fastapi-service -n production
   kubectl describe pods -l app=fastapi-service -n production
   ```
1. Check recent events:
   
   ```bash
   kubectl get events -n production --sort-by='.lastTimestamp' | grep fastapi
   ```
1. Check logs for errors:
   
   ```bash
   kubectl logs -l app=fastapi-service -n production --tail=100
   ```
1. If pods are crashing, check resource limits:
   
   ```bash
   kubectl top pods -l app=fastapi-service -n production
   ```
1. Emergency rollback if needed:
   
   ```bash
   ./scripts/rollback.sh production
   ```

### High Error Rate

**Alert**: Error rate > 5% for 5 minutes

**Actions**:

1. Check error logs:
   
   ```bash
   kubectl logs -l app=fastapi-service -n production | grep -E "ERROR|CRITICAL"
   ```
1. Check specific endpoint errors:
   
   ```bash
   kubectl exec -it deployment/fastapi-service -n production -- curl localhost:8000/metrics | grep http_requests_total
   ```
1. Scale up if load-related:
   
   ```bash
   kubectl scale deployment/fastapi-service --replicas=6 -n production
   ```

### High Response Time

**Alert**: p95 latency > 1 second

**Actions**:

1. Check CPU/Memory usage:
   
   ```bash
   kubectl top pods -l app=fastapi-service -n production
   ```
1. Check HPA status:
   
   ```bash
   kubectl get hpa fastapi-service -n production
   ```
1. Check for slow queries in logs:
   
   ```bash
   kubectl logs -l app=fastapi-service -n production | grep -E "Duration: [0-9]{4,}"
   ```

## 🔄 Common Operations

### Deployment

#### Standard Deployment

```bash
# Deploy specific version
./scripts/deploy.sh production v1.2.3

# Deploy latest
./scripts/deploy.sh production latest
```

#### Canary Deployment

```bash
# Deploy canary (10% traffic)
kubectl apply -f k8s/deployment-canary.yaml
kubectl set image deployment/fastapi-service-canary fastapi=ghcr.io/yourusername/fastapi-service:canary -n production

# Monitor canary
watch kubectl get pods -l app=fastapi-service,version=canary -n production

# Promote canary
kubectl set image deployment/fastapi-service fastapi=ghcr.io/yourusername/fastapi-service:canary -n production
kubectl delete deployment fastapi-service-canary -n production
```

### Scaling

#### Manual Scaling

```bash
# Scale up
kubectl scale deployment/fastapi-service --replicas=10 -n production

# Scale down
kubectl scale deployment/fastapi-service --replicas=3 -n production
```

#### Update Auto-scaling

```bash
# Edit HPA
kubectl edit hpa fastapi-service -n production

# Update HPA limits
kubectl patch hpa fastapi-service -n production -p '{"spec":{"maxReplicas":15}}'
```

### Maintenance Mode

#### Enable Maintenance

```bash
# Update ingress to maintenance page
kubectl patch ingress fastapi-service -n production --type=json -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "maintenance-page"}]'
```

#### Disable Maintenance

```bash
# Restore normal traffic
kubectl patch ingress fastapi-service -n production --type=json -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/0/backend/service/name", "value": "fastapi-service"}]'
```

## 📊 Monitoring Procedures

### Daily Checks

1. Review dashboard metrics:
- Request rate trends
- Error rate (should be < 0.1%)
- Response time (p95 < 200ms)
- Pod count and restarts
1. Check certificate expiry:
   
   ```bash
   kubectl get certificate -n production
   ```
1. Review resource usage:
   
   ```bash
   kubectl top nodes
   kubectl top pods -n production
   ```

### Weekly Tasks

1. Review and acknowledge alerts
1. Check for security updates:
   
   ```bash
   trivy image ghcr.io/yourusername/fastapi-service:latest
   ```
1. Review scaling patterns
1. Update documentation

## 🔧 Troubleshooting

### Pod Not Starting

**CrashLoopBackOff**:

```bash
# Check logs
kubectl logs <pod-name> -n production --previous

# Check resource limits
kubectl describe pod <pod-name> -n production | grep -A5 "Limits:"

# Check secrets/configmaps
kubectl get secrets,configmaps -n production
```

**ImagePullBackOff**:

```bash
# Check image exists
docker manifest inspect ghcr.io/yourusername/fastapi-service:latest

# Check pull secrets
kubectl get secrets -n production
kubectl describe pod <pod-name> -n production | grep -A5 "Events:"
```

### Network Issues

**Service Not Reachable**:

```bash
# Check endpoints
kubectl get endpoints fastapi-service -n production

# Test from inside cluster
kubectl run test-pod --image=busybox -it --rm -- wget -O- http://fastapi-service.production/health

# Check network policies
kubectl get networkpolicies -n production
```

### Performance Issues

**High Memory Usage**:

```bash
# Check memory usage
kubectl top pods -l app=fastapi-service -n production --sort-by=memory

# Get memory dump
kubectl exec <pod-name> -n production -- python -c "import gc; print(gc.get_stats())"

# Restart high-memory pods
kubectl delete pod <pod-name> -n production
```

## 🔐 Security Procedures

### Rotate Secrets

```bash
# Generate new secret
NEW_SECRET=$(openssl rand -base64 32)

# Update secret
kubectl create secret generic fastapi-secrets-new \
  --from-literal=API_SECRET_KEY=$NEW_SECRET \
  -n production

# Update deployment
kubectl patch deployment fastapi-service -n production \
  -p '{"spec":{"template":{"spec":{"volumes":[{"name":"secrets","secret":{"secretName":"fastapi-secrets-new"}}]}}}}'

# Delete old secret
kubectl delete secret fastapi-secrets -n production
```

### Security Scan

```bash
# Scan running image
kubectl get pods -l app=fastapi-service -n production -o jsonpath="{.items[0].spec.containers[0].image}" | xargs trivy image

# Check security policies
kubectl get podsecuritypolicies
kubectl auth can-i --list --as=system:serviceaccount:production:fastapi-service
```

## 📝 Backup & Recovery

### Backup Configuration

```bash
# Backup all resources
kubectl get all,configmaps,secrets,ingress -n production -o yaml > backup-$(date +%Y%m%d).yaml

# Backup specific deployment
kubectl get deployment fastapi-service -n production -o yaml > deployment-backup.yaml
```

### Disaster Recovery

```bash
# Restore from backup
kubectl apply -f backup-20240115.yaml

# Verify restoration
./scripts/health-check.sh production
```

## 📞 Escalation

### Severity Levels

**P1 - Critical** (Service Down)

- Immediate response required
- Page on-call engineer
- Update status page

**P2 - Major** (Degraded Performance)

- Response within 30 minutes
- Notify team lead
- Monitor closely

**P3 - Minor** (Non-critical Issues)

- Response within 2 hours
- Create ticket
- Schedule fix

### Contacts

- **On-Call**: Check PagerDuty schedule
- **Team Lead**: #fastapi-team Slack channel
- **Infrastructure**: #platform-team Slack channel
- **Security**: security@example.com

## 📋 Checklists

### Pre-Deployment

- [ ] Run tests locally
- [ ] Review changes with team
- [ ] Check resource requirements
- [ ] Update documentation
- [ ] Prepare rollback plan

### Post-Deployment

- [ ] Verify health checks passing
- [ ] Check metrics dashboard
- [ ] Monitor error rates (15 mins)
- [ ] Verify all features working
- [ ] Update deployment log

### Post-Incident

- [ ] Document timeline
- [ ] Identify root cause
- [ ] Create action items
- [ ] Update runbook
- [ ] Share learnings

-----

**Last Updated**: January 2024
**Owner**: Platform Team
**Review Cycle**: Monthly
