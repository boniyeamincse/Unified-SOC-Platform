#!/bin/bash

# SOC Platform Security Secret Generation Script
# This script generates cryptographically secure passwords and API keys

set -euo pipefail

echo "🔐 SOC Platform Security Setup - Secret Generation"
echo "=================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if required tools are available
check_dependencies() {
    local deps=("openssl" "head" "tr")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo -e "${RED}Error: $dep is not installed. Please install it first.${NC}"
            exit 1
        fi
    done
}

# Generate random password with specified length and character set
generate_password() {
    local length=${1:-32}
    local charset=${2:-'A-Za-z0-9!@#$%^&*()_+-=[]{}|;:,.<>?'}
    
    # Use /dev/urandom for cryptographically secure randomness
    LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$length"
}

# Generate API key (base64 encoded random string)
generate_api_key() {
    local length=${1:-32}
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length"
}

# Generate UUID v4
generate_uuid() {
    openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/'
}

# Create backup of original .env file
backup_env_file() {
    local env_file="../.env"
    if [[ -f "$env_file" ]]; then
        local backup_file="../.env.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$env_file" "$backup_file"
        echo -e "${GREEN}✓ Backed up existing .env to $(basename "$backup_file")${NC}"
    fi
}

# Update .env file with new secrets
update_env_file() {
    local env_file="../.env"
    local temp_file=$(mktemp)
    
    # Generate all the secrets
    local elastic_password=$(generate_password 24 'A-Za-z0-9!@#$%^&*')
    local kibana_password=$(generate_password 24 'A-Za-z0-9!@#$%^&*')
    local wazuh_password=$(generate_password 24 'A-Za-z0-9!@#$%^&*')
    local wazuh_api_password=$(generate_password 24 'A-Za-z0-9!@#$%^&*')
    local cortex_api_key=$(generate_api_key 32)
    local cortex_secret=$(generate_password 32)
    local ai_engine_api_key=$(generate_api_key 32)
    local kibana_encryption_key=$(generate_password 32 'A-Za-z0-9')
    local session_secret=$(generate_password 32 'A-Za-z0-9')
    local backup_key=$(generate_password 32 'A-Za-z0-9')
    
    # Read existing .env and update with new secrets
    while IFS= read -r line; do
        case "$line" in
            ELASTIC_PASSWORD=*)
                echo "ELASTIC_PASSWORD=$elastic_password" >> "$temp_file"
                ;;
            KIBANA_PASSWORD=*)
                echo "KIBANA_PASSWORD=$kibana_password" >> "$temp_file"
                ;;
            WAZUH_PASSWORD=*)
                echo "WAZUH_PASSWORD=$wazuh_password" >> "$temp_file"
                ;;
            WAZUH_API_PASSWORD=*)
                echo "WAZUH_API_PASSWORD=$wazuh_api_password" >> "$temp_file"
                ;;
            CORTEX_API_KEY=*)
                echo "CORTEX_API_KEY=$cortex_api_key" >> "$temp_file"
                ;;
            CORTEX_SECRET=*)
                echo "CORTEX_SECRET=$cortex_secret" >> "$temp_file"
                ;;
            AI_ENGINE_API_KEY=*)
                echo "AI_ENGINE_API_KEY=$ai_engine_api_key" >> "$temp_file"
                ;;
            KIBANA_ENCRYPTION_KEY=*)
                echo "KIBANA_ENCRYPTION_KEY=$kibana_encryption_key" >> "$temp_file"
                ;;
            SESSION_SECRET=*)
                echo "SESSION_SECRET=$session_secret" >> "$temp_file"
                ;;
            BACKUP_ENCRYPTION_KEY=*)
                echo "BACKUP_ENCRYPTION_KEY=$backup_key" >> "$temp_file"
                ;;
            *)
                echo "$line" >> "$temp_file"
                ;;
        esac
    done < "$env_file"
    
    # Replace the original file
    mv "$temp_file" "$env_file"
    chmod 600 "$env_file"  # Secure permissions
    
    echo -e "${GREEN}✓ Updated .env file with new secure secrets${NC}"
    
    # Display summary (without showing actual secrets)
    echo ""
    echo -e "${BLUE}Generated Secrets Summary:${NC}"
    echo -e "  • Elasticsearch Password: ${GREEN}✓ Generated (24 chars)${NC}"
    echo -e "  • Kibana Password: ${GREEN}✓ Generated (24 chars)${NC}"
    echo -e "  • Wazuh Password: ${GREEN}✓ Generated (24 chars)${NC}"
    echo -e "  • Wazuh API Password: ${GREEN}✓ Generated (24 chars)${NC}"
    echo -e "  • Cortex API Key: ${GREEN}✓ Generated (32 chars)${NC}"
    echo -e "  • Cortex Secret: ${GREEN}✓ Generated (32 chars)${NC}"
    echo -e "  • AI Engine API Key: ${GREEN}✓ Generated (32 chars)${NC}"
    echo -e "  • Kibana Encryption Key: ${GREEN}✓ Generated (32 chars)${NC}"
    echo -e "  • Session Secret: ${GREEN}✓ Generated (32 chars)${NC}"
    echo -e "  • Backup Encryption Key: ${GREEN}✓ Generated (32 chars)${NC}"
}

# Generate SSL certificates
generate_ssl_certificates() {
    echo ""
    echo -e "${BLUE}Generating SSL/TLS certificates...${NC}"
    
    # Create certificate directories
    local cert_dirs=(
        "../configs/elasticsearch-certs"
        "../configs/kibana-certs"
        "../configs/wazuh-certs"
        "../configs/logstash-certs"
        "../configs/nginx-certs"
    )
    
    for dir in "${cert_dirs[@]}"; do
        mkdir -p "$dir"
    done
    
    # Generate CA private key
    openssl genrsa -out "../configs/ca-key.pem" 4096
    
    # Generate CA certificate
    openssl req -new -x509 -days 365 -key "../configs/ca-key.pem" \
        -sha256 -out "../configs/ca.crt" -subj \
        "/C=US/ST=Security/L=SOC/O=SOC Platform/CN=SOC-CA"
    
    # Generate certificates for each service
    local services=("elasticsearch" "kibana" "wazuh" "logstash" "nginx")
    
    for service in "${services[@]}"; do
        local key_file="../configs/${service}-certs/${service}.key"
        local csr_file="../configs/${service}-certs/${service}.csr"
        local cert_file="../configs/${service}-certs/${service}.crt"
        local ca_file="../configs/${service}-certs/ca.crt"
        
        # Generate private key
        openssl genrsa -out "$key_file" 2048
        
        # Generate certificate signing request
        openssl req -subj "/C=US/ST=Security/L=SOC/O=SOC Platform/CN=${service}" \
            -new -key "$key_file" -out "$csr_file"
        
        # Generate certificate signed by CA
        openssl x509 -req -in "$csr_file" -CA "../configs/ca.crt" \
            -CAkey "../configs/ca-key.pem" -CAcreateserial \
            -out "$cert_file" -days 365 -sha256
        
        # Copy CA certificate
        cp "../configs/ca.crt" "$ca_file"
        
        # Set appropriate permissions
        chmod 600 "$key_file"
        chmod 644 "$cert_file" "$ca_file"
        
        # Clean up CSR file
        rm "$csr_file"
        
        echo -e "  • ${service}: ${GREEN}✓ Certificate generated${NC}"
    done
    
    # Secure the CA private key
    chmod 600 "../configs/ca-key.pem"
    
    echo -e "${GREEN}✓ SSL/TLS certificates generated successfully${NC}"
}

# Generate API keys for external services
generate_api_keys() {
    echo ""
    echo -e "${BLUE}Generating API keys for services...${NC}"
    
    local api_keys_file="../configs/api-keys.conf.secure"
    local temp_file=$(mktemp)
    
    # Generate secure API keys
    local elasticsearch_api_key=$(generate_api_key 48)
    local kibana_api_key=$(generate_api_key 48)
    local wazuh_api_key=$(generate_api_key 48)
    local cortex_api_key=$(generate_api_key 48)
    local ai_engine_api_key=$(generate_api_key 48)
    local jwt_secret=$(generate_password 48 'A-Za-z0-9')
    local backup_encryption_key=$(generate_password 48 'A-Za-z0-9')
    
    # Create secure API keys file
    cat > "$api_keys_file" << EOF
# SOC Platform Secure API Keys - $(date)
# Generated by generate-secrets.sh
# WARNING: Keep this file secure and never commit to version control!

[internal_services]
elasticsearch_api_key = \"$elasticsearch_api_key\"
kibana_api_key = \"$kibana_api_key\"
wazuh_api_key = \"$wazuh_api_key\"
cortex_api_key = \"$cortex_api_key\"
ai_engine_api_key = \"$ai_engine_api_key\"

[authentication]
jwt_secret_key = \"$jwt_secret\"

[backup]
backup_encryption_key = \"$backup_encryption_key\"

# External service API keys - Replace with your actual keys
[external_integrations]
virustotal_api_key = \"REPLACE_WITH_YOUR_VIRUSTOTAL_KEY\"
shodan_api_key = \"REPLACE_WITH_YOUR_SHODAN_KEY\"
abuseipdb_api_key = \"REPLACE_WITH_YOUR_ABUSEIPDB_KEY\"

# Generated on: $(date)
# Valid until: $(date -d '+90 days')
EOF
    
    chmod 600 "$api_keys_file"
    echo -e "${GREEN}✓ Secure API keys generated and saved to configs/api-keys.conf.secure${NC}"
}

# Create security hardening file
create_security_hardening() {
    local hardening_file="../configs/security-hardening.sh"
    
    cat > "$hardening_file" << 'EOF'
#!/bin/bash

# SOC Platform Security Hardening Script
# Run this script to apply additional security measures

set -euo pipefail

echo "🔒 Applying security hardening measures..."

# Set strict file permissions
find ../configs -type f -name "*.conf" -exec chmod 600 {} \;
find ../configs -type f -name "*.yml" -exec chmod 600 {} \;
find ../configs -type f -name "*.key" -exec chmod 600 {} \;
find ../configs -type f -name "*.pem" -exec chmod 600 {} \;

# Secure certificate directories
find ../configs -type d -name "*-certs" -exec chmod 700 {} \;

# Secure environment file
chmod 600 ../.env

# Create security audit log directory
mkdir -p ../logs/security
chmod 750 ../logs/security

# Set up log rotation for security logs
if command -v logrotate &> /dev/null; then
    cat > ../configs/logrotate.conf << 'EOL'
../logs/security/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 640 root root
}
EOL
fi

echo "✅ Security hardening applied successfully"
EOF
    
    chmod +x "$hardening_file"
    echo -e "${GREEN}✓ Security hardening script created${NC}"
}

# Main execution
main() {
    echo -e "${YELLOW}This script will generate secure secrets for your SOC platform.${NC}"
    echo -e "${YELLOW}It will replace existing passwords and API keys with new secure ones.${NC}"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Operation cancelled."
        exit 0
    fi
    
    check_dependencies
    backup_env_file
    update_env_file
    generate_ssl_certificates
    generate_api_keys
    create_security_hardening
    
    echo ""
    echo -e "${GREEN}🎉 Security setup completed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT SECURITY NOTES:${NC}"
    echo -e "  1. ${RED}Change any remaining default passwords immediately${NC}"
    echo -e "  2. ${RED}Backup your certificates and keys securely${NC}"
    echo -e "  3. ${RED}Never commit .env or *.secure files to version control${NC}"
    echo -e "  4. ${BLUE}Run './configs/security-hardening.sh' for additional hardening${NC}"
    echo -e "  5. ${BLUE}Review and update the user configurations in configs/users.conf${NC}"
    echo ""
    echo -e "${GREEN}Your SOC platform is now configured with enterprise-grade security!${NC}"
}

# Change to scripts directory
cd "$(dirname "$0")"

# Run main function
main "$@"
