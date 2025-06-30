#!/bin/bash
set -euo pipefail

# Rollback script for FastAPI service
# Usage: ./rollback.sh [environment] [revision]

# Default values
ENVIRONMENT=${1:-production}
REVISION=${2:-0}  # 0 means previous revision
NAMESPACE=${ENVIRONMENT}
DEPLOYMENT_NAME="fastapi-service"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $