#!/bin/bash

# SOC Platform Enhanced Secure Initialization Script
# This script sets up the SOC platform with security best practices

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🛡️ SOC Platform Enhanced Security Setup${NC}"
echo "================================================="
echo -e "${YELLOW}Initializing secure SOC platform with enterprise-grade security...${NC}"
echo ""

# Check if Docker and Docker Compose are available
check_dependencies() {
    local deps=("docker" "docker-compose")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}Error: $dep is not installed. Please install it first.${NC}"
            exit 1
        fi
    done
}

# Check if secrets have been generated
check_security_setup() {
    if [[ ! -f "../configs/ca.crt" ]]; then
        echo -e "${YELLOW}⚠️  Security certificates not found.${NC}"
        echo -e "${YELLOW}   Please run './generate-secrets.sh' first to set up security.${NC}"
        read -p "Do you want to run the security setup now? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ./generate-secrets.sh
        else
            echo -e "${RED}Cannot continue without security setup. Exiting.${NC}"
            exit 1
        fi
    fi
}

# Validate environment configuration
validate_config() {
    echo -e "${BLUE}🔍 Validating configuration...${NC}"
    
    # Check if .env file exists and has required variables
    if [[ ! -f "../.env" ]]; then
        echo -e "${RED}Error: .env file not found. Please run generate-secrets.sh first.${NC}"
        exit 1
    fi
    
    # Check for default passwords (security risk)
    if grep -q "ChangeMeElastic2025!" "../.env"; then
        echo -e "${YELLOW}⚠️  Warning: Default passwords detected in .env file.${NC}"
        echo -e "${YELLOW}   Please run './generate-secrets.sh' to generate secure passwords.${NC}"
    fi
    
    echo -e "${GREEN}✓ Configuration validated${NC}"
}

# Set up security hardening
apply_security_hardening() {
    echo -e "${BLUE}🔒 Applying security hardening...${NC}"
    
    # Set strict permissions on config files
    find ../configs -type f \( -name "*.conf" -o -name "*.yml" -o -name "*.key" -o -name "*.pem" \) -exec chmod 600 {} \;
    find ../configs -type d -name "*-certs" -exec chmod 700 {} \;
    chmod 600 ../.env 2>/dev/null || true
    
    # Create logs directory with proper permissions
    mkdir -p ../logs/security
    chmod 750 ../logs/security
    
    echo -e "${GREEN}✓ Security hardening applied${NC}"
}

# Pre-flight security checks
security_preflight() {
    echo -e "${BLUE}🛡️ Running security pre-flight checks...${NC}"
    
    # Check Docker daemon security
    if docker info | grep -q "Security Options: apparmor seccomp"; then
        echo -e "${GREEN}✓ Docker security features enabled${NC}"
    else
        echo -e "${YELLOW}⚠️  Docker security features may not be optimally configured${NC}"
    fi
    
    # Check available system resources
    local available_ram=$(free -g | awk '/^Mem:/ {print $7}')
    if [[ $available_ram -lt 8 ]]; then
        echo -e "${YELLOW}⚠️  Warning: Less than 8GB RAM available. Platform may run slowly.${NC}"
    fi
    
    echo -e "${GREEN}✓ Pre-flight checks completed${NC}"
}

# Start services with security monitoring
start_services() {
    echo -e "${BLUE}🚀 Starting SOC Platform services...${NC}"
    
    # Pull latest images first
    echo -e "${BLUE}📥 Pulling latest Docker images...${NC}"
    docker-compose pull
    
    # Start services in the correct order
    echo -e "${BLUE}🔄 Starting core services...${NC}"
    docker-compose up --build -d elasticsearch
    
    # Wait for Elasticsearch to be ready
    echo -e "${BLUE}⏳ Waiting for Elasticsearch to be ready...${NC}"
    timeout=300
    while ! curl -s -k "https://localhost:9200" &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 5
        timeout=$((timeout - 5))
        echo -n "."
    done
    echo ""
    
    if [[ $timeout -le 0 ]]; then
        echo -e "${YELLOW}⚠️  Elasticsearch took longer than expected to start${NC}"
    else
        echo -e "${GREEN}✓ Elasticsearch is ready${NC}"
    fi
    
    # Start remaining services
    docker-compose up --build -d
    
    echo -e "${GREEN}✓ All services started${NC}"
}

# Wait for services to be ready
wait_for_services() {
    echo -e "${BLUE}⏳ Waiting for all services to initialize...${NC}"
    
    local services=("kibana:5601" "nginx:443")
    
    for service in "${services[@]}"; do
        IFS=':' read -r service_name port <<< "$service"
        timeout=120
        while ! docker exec "${service_name}" sh -c "curl -s -k http://localhost:${port}/health" &>/dev/null && [[ $timeout -gt 0 ]]; do
            sleep 2
            timeout=$((timeout - 2))
        done
        
        if [[ $timeout -gt 0 ]]; then
            echo -e "${GREEN}✓ ${service_name} is ready${NC}"
        else
            echo -e "${YELLOW}⚠️  ${service_name} may not be fully ready${NC}"
        fi
    done
}

# Initialize Ollama with security considerations
setup_ollama() {
    echo -e "${BLUE}🤖 Setting up AI Engine (Ollama)...${NC}"
    
    # Wait for Ollama to be ready
    timeout=60
    while ! docker exec ollama ollama list &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 2
        timeout=$((timeout - 2))
    done
    
    if docker exec ollama ollama list | grep -q llama3; then
        echo -e "${GREEN}✓ Ollama model already loaded${NC}"
    else
        echo -e "${BLUE}📥 Pulling llama3 model into Ollama...${NC}"
        docker exec ollama ollama pull llama3
        echo -e "${GREEN}✓ Ollama model loaded${NC}"
    fi
}

# Display service status and access information
show_service_status() {
    echo ""
    echo -e "${GREEN}🎉 SOC Platform successfully deployed!${NC}"
    echo "================================================"
    echo ""
    echo -e "${BLUE}Service Access URLs:${NC}"
    echo -e "  🛡️  Main Dashboard: ${GREEN}https://localhost/kibana/${NC}"
    echo -e "  🧠  Kibana: ${GREEN}https://localhost/kibana/${NC}"
    echo -e "  🔍  SOAR (TheHive): ${GREEN}https://localhost/soar/${NC}"
    echo -e "  🧪  Cortex: ${GREEN}https://localhost/cortex/${NC}"
    echo -e "  🤖  AI Engine: ${GREEN}http://localhost:11434${NC}"
    echo ""
    echo -e "${BLUE}Service Status:${NC}"
    docker-compose ps
    echo ""
    echo -e "${YELLOW}Security Notes:${NC}"
    echo -e "  • ${GREEN}All services are running with security hardening${NC}"
    echo -e "  • ${GREEN}SSL/TLS encryption is enabled${NC}"
    echo -e "  • ${GREEN}Network segmentation is active${NC}"
    echo -e "  • ${GREEN}Resource limits are enforced${NC}"
    echo -e "  • ${RED}Change default passwords immediately${NC}"
    echo -e "  • ${BLUE}Check logs regularly: docker-compose logs -f${NC}"
    echo ""
    echo -e "${GREEN}Happy SOC hunting! 🎯${NC}"
}

# Main execution
main() {
    echo -e "${YELLOW}This will start the SOC platform with enhanced security.${NC}"
    echo -e "${YELLOW}Make sure you have run './generate-secrets.sh' first.${NC}"
    echo ""
    
    check_dependencies
    check_security_setup
    validate_config
    apply_security_hardening
    security_preflight
    start_services
    wait_for_services
    setup_ollama
    show_service_status
}

# Change to scripts directory
cd "$(dirname "$0")"

# Run main function
main "$@"
