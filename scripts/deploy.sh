#!/bin/bash
set -euo pipefail

# Deployment script for FastAPI service
# Usage: ./deploy.sh [environment] [image-tag]

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT=${1:-production}
IMAGE_TAG=${2:-latest}
NAMESPACE=${ENVIRONMENT}
DEPLOYMENT_NAME="fastapi-service"
REGISTRY="ghcr.io/yourusername"
IMAGE_NAME="${REGISTRY}/fastapi-service:${IMAGE_TAG}"

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check if connected to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Not connected to a Kubernetes cluster. Please configure kubectl."
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace ${NAMESPACE} &> /dev/null; then
        log_warn "Namespace ${NAMESPACE} does not exist. Creating..."
        kubectl apply -f k8s/namespace.yaml
    fi
}

validate_manifests() {
    log_info "Validating Kubernetes manifests..."
    
    # Validate YAML syntax
    for file in k8s/*.yaml; do
        if [[ -f "$file" ]]; then
            kubectl apply --dry-run=client -f "$file" &> /dev/null || {
                log_error "Invalid manifest: $file"
                exit 1
            }
        fi
    done
    
    log_info "All manifests are valid"
}

create_secrets() {
    log_info "Checking secrets..."
    
    # Check if secret exists
    if ! kubectl get secret fastapi-secrets -n ${NAMESPACE} &> /dev/null; then
        log_warn "Secret 'fastapi-secrets' not found. Please create it manually."
        log_warn "Run: kubectl create secret generic fastapi-secrets --from-literal=API_SECRET_KEY=your-secret -n ${NAMESPACE}"
    fi
}

deploy_application() {
    log_info "Deploying FastAPI service to ${ENVIRONMENT}..."
    
    # Apply configurations
    log_info "Applying ConfigMap..."
    kubectl apply -f k8s/configmap.yaml -n ${NAMESPACE}
    
    log_info "Applying ServiceAccount and RBAC..."
    kubectl apply -f k8s/serviceaccount.yaml -n ${NAMESPACE}
    
    log_info "Applying NetworkPolicy..."
    kubectl apply -f k8s/networkpolicy.yaml -n ${NAMESPACE}
    
    log_info "Applying Service..."
    kubectl apply -f k8s/service.yaml -n ${NAMESPACE}
    
    log_info "Applying Deployment..."
    # Update image tag in deployment
    kubectl set image deployment/${DEPLOYMENT_NAME} \
        fastapi=${IMAGE_NAME} \
        -n ${NAMESPACE} --record || {
        # If deployment doesn't exist, create it
        kubectl apply -f k8s/deployment.yaml -n ${NAMESPACE}
        kubectl set image deployment/${DEPLOYMENT_NAME} \
            fastapi=${IMAGE_NAME} \
            -n ${NAMESPACE} --record
    }
    
    log_info "Applying HPA..."
    kubectl apply -f k8s/hpa.yaml -n ${NAMESPACE}
    
    log_info "Applying Ingress..."
    kubectl apply -f k8s/ingress.yaml -n ${NAMESPACE}
}

wait_for_rollout() {
    log_info "Waiting for deployment to complete..."
    
    # Wait for rollout with timeout
    if kubectl rollout status deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE} --timeout=5m; then
        log_info "Deployment completed successfully!"
    else
        log_error "Deployment failed or timed out"
        log_info "Rolling back..."
        kubectl rollout undo deployment/${DEPLOYMENT_NAME} -n ${NAMESPACE}
        exit 1
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check pod status
    READY_PODS=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.status.readyReplicas}')
    DESIRED_PODS=$(kubectl get deployment ${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.replicas}')
    
    if [[ "$READY_PODS" == "$DESIRED_PODS" ]]; then
        log_info "All pods are ready: ${READY_PODS}/${DESIRED_PODS}"
    else
        log_warn "Only ${READY_PODS}/${DESIRED_PODS} pods are ready"
    fi
    
    # Show pod status
    echo -e "\nPod Status:"
    kubectl get pods -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE}
    
    # Show service endpoints
    echo -e "\nService Endpoints:"
    kubectl get endpoints ${DEPLOYMENT_NAME} -n ${NAMESPACE}
    
    # Show ingress
    echo -e "\nIngress Status:"
    kubectl get ingress ${DEPLOYMENT_NAME} -n ${NAMESPACE}
}

run_health_check() {
    log_info "Running health check..."
    
    # Get a pod name
    POD_NAME=$(kubectl get pods -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE} -o jsonpath='{.items[0].metadata.name}')
    
    if [[ -n "$POD_NAME" ]]; then
        # Port forward and check health
        kubectl port-forward pod/${POD_NAME} 8080:8000 -n ${NAMESPACE} &
        PF_PID=$!
        
        sleep 5
        
        if curl -f http://localhost:8080/health &> /dev/null; then
            log_info "Health check passed!"
        else
            log_error "Health check failed!"
        fi
        
        kill $PF_PID 2>/dev/null || true
    else
        log_warn "No pods found for health check"
    fi
}

show_deployment_info() {
    echo -e "\n${GREEN}Deployment Summary:${NC}"
    echo "================================"
    echo "Environment: ${ENVIRONMENT}"
    echo "Namespace: ${NAMESPACE}"
    echo "Image: ${IMAGE_NAME}"
    echo "Deployment: ${DEPLOYMENT_NAME}"
    echo "================================"
    
    echo -e "\n${GREEN}Next Steps:${NC}"
    echo "1. Check application logs: kubectl logs -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE}"
    echo "2. Monitor metrics: kubectl top pods -l app=${DEPLOYMENT_NAME} -n ${NAMESPACE}"
    echo "3. Access the application: https://api.example.com"
}

# Main execution
main() {
    log_info "Starting deployment process..."
    
    check_prerequisites
    validate_manifests
    create_secrets
    deploy_application
    wait_for_rollout
    verify_deployment
    run_health_check
    show_deployment_info
    
    log_info "Deployment completed successfully! 🎉"
}

# Run main function
main