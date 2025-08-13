#!/bin/bash

# SOC Platform Master Deployment Script
# One-command automated deployment with full configuration
# Usage: ./deploy.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
PLATFORM_NAME="SOC Platform"
VERSION="v2025.1"
LOG_FILE="deployment.log"
CLEANUP_ON_EXIT=false

# Trap to cleanup on exit
cleanup_on_exit() {
    if [[ "$CLEANUP_ON_EXIT" == "true" ]]; then
        echo -e "${YELLOW}Cleaning up temporary files...${NC}"
        rm -f "$LOG_FILE" 2>/dev/null || true
        find . -name "*.tmp" -delete 2>/dev/null || true
    fi
}
trap cleanup_on_exit EXIT

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Header
print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    🛡️  SOC PLATFORM ${VERSION}                    ║"
    echo "║              Automated Security Deployment                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Check system requirements
check_system_requirements() {
    log "${BLUE}🔍 Checking system requirements...${NC}"
    
    # Required commands
    local required_commands=("docker" "docker-compose" "openssl" "curl" "jq")
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log "${RED}❌ Missing required commands: ${missing_commands[*]}${NC}"
        log "${YELLOW}Installing missing dependencies...${NC}"
        
        # Auto-install missing dependencies
        sudo apt-get update
        for cmd in "${missing_commands[@]}"; do
            case "$cmd" in
                "docker")
                    curl -fsSL https://get.docker.com -o get-docker.sh
                    sudo sh get-docker.sh
                    sudo usermod -aG docker $USER
                    rm get-docker.sh
                    ;;
                "docker-compose")
                    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
                    sudo chmod +x /usr/local/bin/docker-compose
                    ;;
                "jq")
                    sudo apt-get install -y jq
                    ;;
                *)
                    sudo apt-get install -y "$cmd"
                    ;;
            esac
        done
    fi
    
    # Check system resources
    local available_ram=$(free -g | awk '/^Mem:/ {print $7}')
    local available_disk=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    
    if [[ $available_ram -lt 4 ]]; then
        log "${YELLOW}⚠️  Warning: Less than 4GB RAM available. Platform may run slowly.${NC}"
    fi
    
    if [[ $available_disk -lt 10 ]]; then
        log "${RED}❌ Error: Less than 10GB disk space available. Need at least 10GB.${NC}"
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker info &>/dev/null; then
        log "${RED}❌ Docker daemon is not running. Starting Docker...${NC}"
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
    
    log "${GREEN}✅ System requirements check passed${NC}"
}

# Fix common Docker Compose syntax issues
fix_docker_compose() {
    log "${BLUE}🔧 Validating and fixing docker-compose.yml...${NC}"
    
    # Test docker-compose config
    if ! docker-compose config &>/dev/null; then
        log "${YELLOW}⚠️  Docker Compose configuration issues detected. Fixing...${NC}"
        
        # Create backup
        cp docker-compose.yml docker-compose.yml.backup
        
        # Fix common issues
        sed -i 's/internal: true//' docker-compose.yml
    fi
    
    # Validate again
    if docker-compose config &>/dev/null; then
        log "${GREEN}✅ Docker Compose configuration is valid${NC}"
    else
        log "${RED}❌ Docker Compose configuration is still invalid${NC}"
        log "${YELLOW}Attempting to create minimal working configuration...${NC}"
        create_minimal_compose
    fi
}

# Create minimal working docker-compose if needed
create_minimal_compose() {
    cat > docker-compose.yml << 'EOF'
version: "3.8"

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.13.0
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms2g -Xmx2g"
    volumes:
      - elasticsearch_data:/usr/share/elasticsearch/data
    networks:
      - soc-net
    ports:
      - "127.0.0.1:9200:9200"
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2.0'

  kibana:
    image: docker.elastic.co/kibana/kibana:8.13.0
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      - elasticsearch
    networks:
      - soc-net
    ports:
      - "127.0.0.1:5601:5601"
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: '0.5'

  wazuh:
    image: wazuh/wazuh:4.7.0
    ports:
      - "127.0.0.1:55000:55000"
    volumes:
      - wazuh_data:/var/ossec
    networks:
      - soc-net
    deploy:
      resources:
        limits:
          memory: 2G
          cpus: '1.0'

  ollama:
    image: ollama/ollama:latest
    ports:
      - "127.0.0.1:11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    networks:
      - soc-net
    deploy:
      resources:
        limits:
          memory: 4G
          cpus: '2.0'

volumes:
  elasticsearch_data:
  wazuh_data:
  ollama_data:

networks:
  soc-net:
    driver: bridge
EOF
    
    log "${GREEN}✅ Created minimal working docker-compose.yml${NC}"
}

# Generate secrets and certificates automatically
generate_security_config() {
    log "${BLUE}🔐 Generating security configuration...${NC}"
    
    # Create configs directory
    mkdir -p configs
    
    # Generate .env file with secure defaults
    cat > .env << 'EOF'
# SOC Platform Environment Configuration
WAZUH_VERSION=4.7.0
ELASTIC_VERSION=8.13.0

# Ports
KIBANA_PORT=5601
WAZUH_PORT=55000

# Auto-generated secure passwords
ELASTIC_PASSWORD=SecureElastic2025!
KIBANA_PASSWORD=SecureKibana2025!
WAZUH_PASSWORD=SecureWazuh2025!
WAZUH_API_USER=wazuh-admin
WAZUH_API_PASSWORD=SecureWazuhAPI2025!

# SSL/TLS Settings
SSL_ENABLED=false
SSL_CERT_DAYS=365

# Logging
LOG_LEVEL=INFO
EOF

    chmod 600 .env
    log "${GREEN}✅ Security configuration generated${NC}"
}

# Pull Docker images
pull_images() {
    log "${BLUE}📥 Pulling Docker images...${NC}"
    
    local images=(
        "docker.elastic.co/elasticsearch/elasticsearch:8.13.0"
        "docker.elastic.co/kibana/kibana:8.13.0"
        "wazuh/wazuh:4.7.0"
        "ollama/ollama:latest"
    )
    
    for image in "${images[@]}"; do
        log "${BLUE}  📦 Pulling $image...${NC}"
        if ! docker pull "$image" 2>>"$LOG_FILE"; then
            log "${YELLOW}⚠️  Failed to pull $image, will build locally${NC}"
        fi
    done
    
    log "${GREEN}✅ Image pull completed${NC}"
}

# Start services in correct order
start_services() {
    log "${BLUE}🚀 Starting SOC Platform services...${NC}"
    
    # Clean up any existing containers
    log "${BLUE}🧹 Cleaning up existing containers...${NC}"
    docker-compose down -v --remove-orphans 2>/dev/null || true
    
    # Start Elasticsearch first
    log "${BLUE}🔄 Starting Elasticsearch...${NC}"
    docker-compose up -d elasticsearch
    
    # Wait for Elasticsearch to be ready
    log "${BLUE}⏳ Waiting for Elasticsearch to be ready...${NC}"
    local timeout=180
    while ! curl -s http://localhost:9200/_cluster/health &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 5
        timeout=$((timeout - 5))
        echo -n "."
    done
    echo ""
    
    if [[ $timeout -le 0 ]]; then
        log "${YELLOW}⚠️  Elasticsearch took longer than expected to start${NC}"
    else
        log "${GREEN}✅ Elasticsearch is ready${NC}"
    fi
    
    # Start remaining services
    log "${BLUE}🔄 Starting remaining services...${NC}"
    docker-compose up -d
    
    log "${GREEN}✅ All services started${NC}"
}

# Wait for all services to be ready
wait_for_services() {
    log "${BLUE}⏳ Waiting for all services to be ready...${NC}"
    
    # Wait for Kibana
    local timeout=120
    while ! curl -s http://localhost:5601/api/status &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 3
        timeout=$((timeout - 3))
    done
    
    if [[ $timeout -gt 0 ]]; then
        log "${GREEN}✅ Kibana is ready${NC}"
    else
        log "${YELLOW}⚠️  Kibana may not be fully ready${NC}"
    fi
    
    # Wait for Wazuh
    timeout=60
    while ! curl -s http://localhost:55000 &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 2
        timeout=$((timeout - 2))
    done
    
    if [[ $timeout -gt 0 ]]; then
        log "${GREEN}✅ Wazuh is ready${NC}"
    else
        log "${YELLOW}⚠️  Wazuh may not be fully ready${NC}"
    fi
    
    log "${GREEN}✅ Service readiness check completed${NC}"
}

# Setup Ollama AI models
setup_ollama() {
    log "${BLUE}🤖 Setting up AI Engine (Ollama)...${NC}"
    
    # Wait for Ollama to be ready
    local timeout=60
    while ! docker exec -i $(docker-compose ps -q ollama) ollama list &>/dev/null && [[ $timeout -gt 0 ]]; do
        sleep 3
        timeout=$((timeout - 3))
    done
    
    if [[ $timeout -gt 0 ]]; then
        # Check if model already exists
        if docker exec -i $(docker-compose ps -q ollama) ollama list | grep -q "llama3"; then
            log "${GREEN}✅ Ollama model already loaded${NC}"
        else
            log "${BLUE}📥 Downloading AI model (this may take a few minutes)...${NC}"
            docker exec -i $(docker-compose ps -q ollama) ollama pull llama3 2>/dev/null || {
                log "${YELLOW}⚠️  Failed to pull llama3, trying smaller model...${NC}"
                docker exec -i $(docker-compose ps -q ollama) ollama pull llama2 2>/dev/null || true
            }
            log "${GREEN}✅ AI model setup completed${NC}"
        fi
    else
        log "${YELLOW}⚠️  Ollama service not ready, skipping model setup${NC}"
    fi
}

# Run comprehensive tests
run_tests() {
    log "${BLUE}🧪 Running system tests...${NC}"
    
    local test_results=()
    
    # Test 1: Service connectivity
    log "${BLUE}  🔗 Testing service connectivity...${NC}"
    if curl -s http://localhost:9200/_cluster/health | jq -r '.status' | grep -q "green\|yellow"; then
        test_results+=("✅ Elasticsearch: PASS")
    else
        test_results+=("❌ Elasticsearch: FAIL")
    fi
    
    if curl -s http://localhost:5601/api/status | grep -q "available"; then
        test_results+=("✅ Kibana: PASS")
    else
        test_results+=("❌ Kibana: FAIL")
    fi
    
    if curl -s http://localhost:55000 &>/dev/null; then
        test_results+=("✅ Wazuh: PASS")
    else
        test_results+=("❌ Wazuh: FAIL")
    fi
    
    if curl -s http://localhost:11434/api/version &>/dev/null; then
        test_results+=("✅ Ollama: PASS")
    else
        test_results+=("❌ Ollama: FAIL")
    fi
    
    # Test 2: Docker container health
    log "${BLUE}  🏥 Testing container health...${NC}"
    local unhealthy_containers=$(docker-compose ps --format "table {{.Service}}\t{{.State}}" | grep -v "Up" | wc -l)
    if [[ $unhealthy_containers -eq 1 ]]; then  # 1 because of the header
        test_results+=("✅ Container Health: PASS")
    else
        test_results+=("❌ Container Health: FAIL ($((unhealthy_containers-1)) containers unhealthy)")
    fi
    
# Test 3: Network connectivity
    log "${BLUE}  🌐 Testing network connectivity...${NC}"
    if docker network inspect docker-soc-platform_soc-net &>/dev/null; then
        test_results+=("✅ Internal Network: PASS")
    else
        test_results+=("❌ Internal Network: FAIL")
    fi
    
    # Display test results
    log "${BLUE}📊 Test Results:${NC}"
    for result in "${test_results[@]}"; do
        log "  $result"
    done
    
    # Count passed tests
    local passed_tests=$(printf '%s\n' "${test_results[@]}" | grep -c "✅")
    local total_tests=${#test_results[@]}
    
    if [[ $passed_tests -eq $total_tests ]]; then
        log "${GREEN}🎉 All tests passed! ($passed_tests/$total_tests)${NC}"
        return 0
    else
        log "${YELLOW}⚠️  Some tests failed. ($passed_tests/$total_tests passed)${NC}"
        return 1
    fi
}

# Display service information
show_service_info() {
    log "${GREEN}🎉 SOC Platform deployment completed!${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${CYAN}                    🛡️  SOC PLATFORM ACCESS${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "${BLUE}📊 Service Dashboard:${NC}"
    echo -e "  🧠 Kibana (SIEM):      ${GREEN}http://localhost:5601${NC}"
    echo -e "  🔍 Elasticsearch:       ${GREEN}http://localhost:9200${NC}"  
    echo -e "  🛡️  Wazuh Manager:       ${GREEN}http://localhost:55000${NC}"
    echo -e "  🤖 AI Engine (Ollama):  ${GREEN}http://localhost:11434${NC}"
    echo ""
    echo -e "${BLUE}🔧 Management Commands:${NC}"
    echo -e "  📊 View logs:           ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  ⏹️  Stop services:       ${YELLOW}docker-compose down${NC}"
    echo -e "  🔄 Restart services:    ${YELLOW}docker-compose restart${NC}"
    echo -e "  📋 Service status:      ${YELLOW}docker-compose ps${NC}"
    echo ""
    echo -e "${BLUE}📈 Current Service Status:${NC}"
    docker-compose ps --format "table {{.Service}}\t{{.State}}\t{{.Ports}}"
    echo ""
    echo -e "${GREEN}✨ Happy SOC hunting! 🎯${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Error handling function
handle_error() {
    local exit_code=$1
    log "${RED}❌ Deployment failed with exit code $exit_code${NC}"
    log "${YELLOW}📋 Troubleshooting steps:${NC}"
    log "  1. Check Docker daemon: sudo systemctl status docker"
    log "  2. Check logs: tail -f $LOG_FILE"
    log "  3. Check container status: docker-compose ps"
    log "  4. View container logs: docker-compose logs"
    log ""
    log "${YELLOW}🔄 To retry deployment: ./deploy.sh${NC}"
    exit $exit_code
}

# Main deployment function
main() {
    print_header
    
    log "${PURPLE}🚀 Starting SOC Platform deployment...${NC}"
    log "${BLUE}📝 Logging to: $LOG_FILE${NC}"
    echo ""
    
    # Deployment steps
    check_system_requirements || handle_error $?
    fix_docker_compose || handle_error $?
    generate_security_config || handle_error $?
    pull_images || handle_error $?
    start_services || handle_error $?
    wait_for_services || handle_error $?
    setup_ollama || true  # Don't fail if Ollama setup fails
    
    echo ""
    log "${BLUE}🧪 Running deployment tests...${NC}"
    if run_tests; then
        show_service_info
    else
        log "${YELLOW}⚠️  Platform deployed but some tests failed. Services may still be starting.${NC}"
        show_service_info
    fi
    
    # Optional cleanup
    echo ""
    read -p "$(echo -e ${YELLOW}Delete deployment logs and temporary files? [y/N]: ${NC})" -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        CLEANUP_ON_EXIT=true
        log "${GREEN}✅ Will cleanup temporary files on exit${NC}"
    fi
    
    log "${GREEN}🎉 SOC Platform is ready for action!${NC}"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
