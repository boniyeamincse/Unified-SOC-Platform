#!/bin/bash

# Complete SOC Platform Deployment Script
# Builds and deploys: SIEM, SOAR, MISP, AI Chat, Threat Hunting

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="soc-deployment.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║          🛡️  COMPLETE SOC PLATFORM DEPLOYMENT 🛡️             ║"
    echo "║                                                              ║"
    echo "║  SIEM + SOAR + MISP + AI Chat + Threat Hunting + Wazuh      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

check_requirements() {
    log "${BLUE}🔍 Checking system requirements...${NC}"
    
    # Check available memory (minimum 16GB recommended)
    local available_ram=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $available_ram -lt 12 ]]; then
        log "${YELLOW}⚠️  Warning: Less than 12GB RAM detected. Platform may run slowly.${NC}"
        log "${YELLOW}   Recommended: 16GB+ RAM for optimal performance${NC}"
    else
        log "${GREEN}✅ Memory check passed: ${available_ram}GB available${NC}"
    fi
    
    # Check disk space (minimum 50GB recommended)
    local available_disk=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $available_disk -lt 30 ]]; then
        log "${RED}❌ Error: Less than 30GB disk space available.${NC}"
        log "${RED}   Need at least 50GB for complete SOC platform.${NC}"
        exit 1
    else
        log "${GREEN}✅ Disk space check passed: ${available_disk}GB available${NC}"
    fi
    
    # Check Docker and Docker Compose
    if ! command -v docker &> /dev/null; then
        log "${RED}❌ Docker not found. Installing...${NC}"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        rm get-docker.sh
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log "${RED}❌ Docker Compose not found. Installing...${NC}"
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    
    log "${GREEN}✅ Requirements check completed${NC}"
}

prepare_environment() {
    log "${BLUE}🔧 Preparing deployment environment...${NC}"
    
    # Clean up any existing containers
    docker-compose down -v --remove-orphans 2>/dev/null || true
    
    # Create necessary directories
    mkdir -p logs
    
    # Download AI model (small model for faster startup)
    log "${BLUE}📥 Pre-downloading AI model for faster startup...${NC}"
    docker pull ollama/ollama:latest
    docker run --rm -d --name ollama-temp ollama/ollama:latest
    sleep 5
    docker exec ollama-temp ollama pull llama3.2:1b 2>/dev/null || true
    docker stop ollama-temp 2>/dev/null || true
    
    log "${GREEN}✅ Environment prepared${NC}"
}

deploy_core_services() {
    log "${BLUE}🚀 Deploying core services (Elasticsearch, Kibana, Wazuh)...${NC}"
    
    # Start Elasticsearch first
    docker-compose up -d elasticsearch
    
    # Wait for Elasticsearch to be ready
    log "${BLUE}⏳ Waiting for Elasticsearch...${NC}"
    local timeout=180
    while ! curl -s http://localhost:9200/_cluster/health &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 5
        timeout=$((timeout - 5))
        echo -n "."
    done
    echo ""
    
    if [[ $timeout -le 0 ]]; then
        log "${RED}❌ Elasticsearch failed to start within timeout${NC}"
        return 1
    fi
    
    log "${GREEN}✅ Elasticsearch is ready${NC}"
    
    # Start Kibana and Wazuh services
    docker-compose up -d kibana wazuh-manager wazuh-dashboard
    
    log "${GREEN}✅ Core services deployed${NC}"
}

deploy_threat_intelligence() {
    log "${BLUE}🧠 Deploying threat intelligence services (MISP)...${NC}"
    
    # Start MISP stack
    docker-compose up -d misp-db misp-redis
    sleep 10  # Wait for database to initialize
    docker-compose up -d misp
    
    log "${GREEN}✅ Threat intelligence services deployed${NC}"
}

deploy_soar_services() {
    log "${BLUE}⚡ Deploying SOAR services (TheHive, Cortex)...${NC}"
    
    # Start SOAR stack
    docker-compose up -d thehive cortex
    
    log "${GREEN}✅ SOAR services deployed${NC}"
}

deploy_ai_services() {
    log "${BLUE}🤖 Deploying AI services (Ollama, AI Chat)...${NC}"
    
    # Start AI services
    docker-compose up -d ollama
    
    # Wait for Ollama to be ready
    log "${BLUE}⏳ Waiting for Ollama AI engine...${NC}"
    local timeout=120
    while ! curl -s http://localhost:11434/api/version &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 3
        timeout=$((timeout - 3))
        echo -n "."
    done
    echo ""
    
    if [[ $timeout -gt 0 ]]; then
        log "${GREEN}✅ Ollama is ready${NC}"
        
        # Load AI model
        log "${BLUE}📥 Loading AI model (this may take a few minutes)...${NC}"
        docker exec -i $(docker-compose ps -q ollama) ollama pull llama3.2:1b 2>/dev/null || {
            log "${YELLOW}⚠️  Using alternative model...${NC}"
            docker exec -i $(docker-compose ps -q ollama) ollama pull llama3.2:3b 2>/dev/null || true
        }
        
        # Start AI Chat interface
        docker-compose up -d ai-chat
        
        log "${GREEN}✅ AI services deployed with chat interface${NC}"
    else
        log "${YELLOW}⚠️  Ollama took longer than expected, continuing...${NC}"
    fi
}

run_health_checks() {
    log "${BLUE}🏥 Running health checks...${NC}"
    
    local services=(
        "elasticsearch:9200/_cluster/health"
        "kibana:5601/api/status"
        "wazuh-manager:55000"
        "misp:8080"
        "thehive:9000"
        "cortex:9001"
        "ollama:11434/api/version"
        "ai-chat:8888/api/health"
    )
    
    local healthy_services=0
    local total_services=${#services[@]}
    
    for service_check in "${services[@]}"; do
        IFS=':' read -r service endpoint <<< "$service_check"
        
        if curl -s "http://localhost:${endpoint}" &>/dev/null; then
            log "${GREEN}✅ ${service}: HEALTHY${NC}"
            ((healthy_services++))
        else
            log "${YELLOW}⚠️  ${service}: NOT READY${NC}"
        fi
    done
    
    log "${BLUE}📊 Health Check Results: ${healthy_services}/${total_services} services healthy${NC}"
    
    if [[ $healthy_services -ge $((total_services * 3 / 4)) ]]; then
        return 0
    else
        return 1
    fi
}

show_access_info() {
    log "${GREEN}🎉 SOC Platform deployment completed!${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}             🛡️  COMPLETE SOC PLATFORM ACCESS 🛡️${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${BLUE}🏢 SIEM (Security Information Event Management):${NC}"
    echo -e "  🧠 Kibana:              ${GREEN}http://localhost:5601${NC}"
    echo -e "  🔍 Elasticsearch:       ${GREEN}http://localhost:9200${NC}"
    echo -e "  🛡️  Wazuh Manager:       ${GREEN}http://localhost:55000${NC}"
    echo -e "  📊 Wazuh Dashboard:     ${GREEN}http://localhost:8443${NC}"
    echo ""
    echo -e "${BLUE}🧠 Threat Intelligence (MISP):${NC}"
    echo -e "  🔬 MISP Platform:       ${GREEN}http://localhost:8080${NC}"
    echo -e "     Default Login:      ${YELLOW}admin@misp.local / admin${NC}"
    echo ""
    echo -e "${BLUE}⚡ SOAR (Security Orchestration):${NC}"
    echo -e "  🎯 TheHive:             ${GREEN}http://localhost:9000${NC}"
    echo -e "  🧪 Cortex:              ${GREEN}http://localhost:9001${NC}"
    echo ""
    echo -e "${BLUE}🤖 AI-Powered Analysis:${NC}"
    echo -e "  💬 AI Chat Interface:   ${GREEN}http://localhost:8888${NC}"
    echo -e "  🦙 Ollama API:          ${GREEN}http://localhost:11434${NC}"
    echo ""
    echo -e "${BLUE}🔧 Management Commands:${NC}"
    echo -e "  📊 View all services:   ${YELLOW}docker-compose ps${NC}"
    echo -e "  📋 View logs:           ${YELLOW}docker-compose logs -f [service]${NC}"
    echo -e "  ⏹️  Stop platform:       ${YELLOW}docker-compose down${NC}"
    echo -e "  🔄 Restart service:     ${YELLOW}docker-compose restart [service]${NC}"
    echo ""
    echo -e "${BLUE}💡 Getting Started:${NC}"
    echo -e "  1. Open AI Chat: ${GREEN}http://localhost:8888${NC}"
    echo -e "  2. Ask: \"What security events happened in the last hour?\""
    echo -e "  3. Explore Kibana SIEM: ${GREEN}http://localhost:5601${NC}"
    echo -e "  4. Check Wazuh Dashboard: ${GREEN}http://localhost:8443${NC}"
    echo -e "  5. Manage cases in TheHive: ${GREEN}http://localhost:9000${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}🎯 Your complete SOC platform is ready for security operations!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

setup_ai_model() {
    log "${BLUE}🤖 Setting up AI model for analysis...${NC}"
    
    # Wait a bit more for Ollama to be fully ready
    sleep 10
    
    # Try to pull a suitable model
    if docker exec -i $(docker-compose ps -q ollama) ollama pull llama3.2:1b 2>/dev/null; then
        log "${GREEN}✅ AI model llama3.2:1b loaded successfully${NC}"
    elif docker exec -i $(docker-compose ps -q ollama) ollama pull phi3:mini 2>/dev/null; then
        log "${GREEN}✅ AI model phi3:mini loaded successfully${NC}"
    else
        log "${YELLOW}⚠️  Could not load AI model, but Ollama is running${NC}"
    fi
}

main() {
    print_banner
    
    log "${PURPLE}🚀 Starting complete SOC platform deployment...${NC}"
    log "${BLUE}📝 Detailed logs: $LOG_FILE${NC}"
    echo ""
    
    # Deployment phases
    check_requirements
    prepare_environment
    deploy_core_services
    deploy_threat_intelligence
    deploy_soar_services 
    deploy_ai_services
    
    # Setup AI model in background
    setup_ai_model &
    
    log "${BLUE}⏳ Final system initialization...${NC}"
    sleep 15
    
    if run_health_checks; then
        show_access_info
    else
        log "${YELLOW}⚠️  Some services are still starting up. Platform is deployed but may need a few more minutes.${NC}"
        show_access_info
        log "${BLUE}💡 Check service status with: docker-compose ps${NC}"
    fi
    
    log "${GREEN}🎉 Complete SOC platform deployment finished!${NC}"
}

# Allow cleanup on exit
cleanup() {
    log "${YELLOW}Deployment interrupted. You can restart with: $0${NC}"
}
trap cleanup INT TERM

# Run deployment
main "$@"
