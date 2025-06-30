#!/bin/bash
set -euo pipefail

# Health check script for FastAPI service
# Usage: ./health-check.sh [environment] [endpoint]

# Default values
ENVIRONMENT=${1:-production}
ENDPOINT=${2:-https://api.example.com}
NAMESPACE=${ENVIRONMENT}
DEPLOYMENT_NAME="fastapi-service"
TIMEOUT=10
RETRIES=3

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_endpoint() {
    local url=$1
    local expected_status=${2:-200}
    
    log_info "Checking endpoint: $url"
    
    for i in $(seq 1 $RETRIES); do
        if response=$(curl -s -w "\n%{http_code}" --connect-timeout $TIMEOUT "$url"); then
            status_code=$(echo "$response" | tail -n1)
            body=$(echo "$response" | sed '$d')
            
            if [[ "$status_code" == "$expected_status" ]]; then
                log_info "✓ Endpoint responded with status $status_code"
                echo "Response: $body"
                return 0
            else
                log_warn "Endpoint returned status $status_code (expected $expected_status)"
            fi
        else
            log_warn "Failed to connect to endpoint (attempt $i/$RETRIES)"
        fi
        
        if [[ $i -lt $RETRIES ]]; then
            sleep 5
        fi
    done
    
    return 1
}

check_kubernetes_resources() {
    log_info "Checking Kubernetes resources..."
    
    # Check deployment
    if kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} &> /dev/null; then
        log_info "✓ Deployment exists"
        
        # Get deployment status
        READY=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
        
        if [[ "$READY" == "$DESIRED" ]]; then
            log_info "✓ All replicas are ready: $READY/$DESIRED"
        else
            log_warn "⚠ Only $READY/$DESIRED replicas are ready"
        fi
    else
        log_error "✗ Deployment not found"
        return 1
    fi
    
    # Check pods
    log_info "Checking pods..."
    kubectl get pods -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE} --no-headers | while read -r line; do
        POD_NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        READY=$(echo "$line" | awk '{print $2}')
        RESTARTS=$(echo "$line" | awk '{print $4}')
        
        if [[ "$STATUS" == "Running" ]]; then
            log_info "✓ Pod $POD_NAME is running ($READY, $RESTARTS restarts)"
        else
            log_warn "⚠ Pod $POD_NAME status: $STATUS"
        fi
    done
    
    # Check service endpoints
    ENDPOINTS=$(kubectl get endpoints ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
    if [[ $ENDPOINTS -gt 0 ]]; then
        log_info "✓ Service has $ENDPOINTS endpoints"
    else
        log_error "✗ Service has no endpoints"
        return 1
    fi
}

check_metrics() {
    log_info "Checking metrics endpoint..."
    
    # Get a pod to check metrics
    POD_NAME=$(kubectl get pods -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -n "$POD_NAME" ]]; then
        # Port forward to check metrics
        kubectl port-forward pod/${POD_NAME} 9090:8000 -n ${NAMESPACE} &> /dev/null &
        PF_PID=$!
        
        sleep 3
        
        if curl -s http://localhost:9090/metrics &> /dev/null; then
            log_info "✓ Metrics endpoint is accessible"
        else
            log_warn "⚠ Metrics endpoint not accessible"
        fi
        
        kill $PF_PID 2>/dev/null || true
    fi
}

run_smoke_tests() {
    log_info "Running smoke tests..."
    
    # Test health endpoint
    if check_endpoint "${ENDPOINT}/health" 200; then
        log_info "✓ Health check passed"
    else
        log_error "✗ Health check failed"
        return 1
    fi
    
    # Test items endpoint
    if check_endpoint "${ENDPOINT}/items" 200; then
        log_info "✓ Items endpoint accessible"
    else
        log_error "✗ Items endpoint failed"
        return 1
    fi
    
    # Test create item
    log_info "Testing item creation..."
    if response=$(curl -s -X POST "${ENDPOINT}/items" \
        -H "Content-Type: application/json" \
        -d '{"name":"test-item","description":"Test item from health check"}' \
        --connect-timeout $TIMEOUT); then
        log_info "✓ Item creation successful"
        echo "Response: $response"
    else
        log_error "✗ Item creation failed"
        return 1
    fi
}

check_logs() {
    log_info "Checking recent logs for errors..."
    
    ERROR_COUNT=$(kubectl logs -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE} --tail=100 --since=5m 2>/dev/null | grep -iE "error|exception|fatal" | wc -l)
    
    if [[ $ERROR_COUNT -eq 0 ]]; then
        log_info "✓ No errors found in recent logs"
    else
        log_warn "⚠ Found $ERROR_COUNT error entries in recent logs"
        echo "Recent errors:"
        kubectl logs -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE} --tail=20 --since=5m | grep -iE "error|exception|fatal" || true
    fi
}

generate_report() {
    echo -e "\n${GREEN}=== Health Check Report ===${NC}"
    echo "Timestamp: $(date)"
    echo "Environment: ${ENVIRONMENT}"
    echo "Endpoint: ${ENDPOINT}"
    echo "Namespace: ${NAMESPACE}"
    echo -e "${GREEN}=========================${NC}\n"
}

# Main execution
main() {
    generate_report
    
    log_info "Starting health checks..."
    
    # Track overall health
    HEALTH_STATUS=0
    
    # Run checks
    check_kubernetes_resources || HEALTH_STATUS=1
    check_metrics
    run_smoke_tests || HEALTH_STATUS=1
    check_logs
    
    echo -e "\n${GREEN}=== Summary ===${NC}"
    if [[ $HEALTH_STATUS -eq 0 ]]; then
        log_info "All health checks passed! ✅"
        exit 0
    else
        log_error "Some health checks failed! ❌"
        exit 1
    fi
}

# Run main function
main