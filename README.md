# 🛡️ Unified SOC Platform (2025 Edition)

An AI-powered open-source Security Operations Center platform combining:

- **SIEM**: Wazuh + Elasticsearch + Kibana
- **SOAR**: TheHive + Cortex
- **Threat Intelligence**: MISP
- **AI Engine**: Local LLM with Ollama

All services are containerized with Docker, orchestrated by Docker Compose, and started with a single `init.sh` script.

> ✅ **This is an open-source project. Contributions are welcome!** Anyone can fork, enhance, or add new features via pull requests or by collaborating through the issue tracker.

---

## 📂 Project Structure

```plaintext
docker-soc-platform/
├── .env                            # Environment variables
├── docker-compose.yml             # Full stack config
├── README.md

├── scripts/
│   ├── init.sh                    # 🔥 One-click installer
│   └── cleanup.sh                 # Teardown script

├── wazuh/
│   ├── Dockerfile
│   └── wazuh.yml

├── elasticsearch/
│   ├── Dockerfile
│   └── elasticsearch.yml

├── kibana/
│   ├── Dockerfile
│   └── kibana.yml

├── logstash/
│   ├── Dockerfile
│   └── logstash.conf

├── ai-engine/
│   ├── Dockerfile
│   ├── model.py
│   ├── requirements.txt
│   └── sample_logs.csv

├── threat-hunting/
│   ├── dashboards.json
│   └── queries.kql

├── threat-intel/
│   ├── docker-compose.override.yml
│   ├── thehive/
│   │   ├── Dockerfile
│   │   └── application.conf
│   ├── cortex/
│   │   ├── Dockerfile
│   │   └── application.conf
│   ├── misp/
│   │   └── docker-compose.override.yml
│   └── analyzers/
│       └── misp-analyzer/

├── configs/
│   ├── alert-rules.yml
│   ├── users.conf
│   └── api-keys.conf

├── ollama/
│   ├── ollama.sh
│   └── ollama-config.json

└── docs/
    ├── architecture-diagram.png
    └── deployment-guide.md
```

---

## 🚀 Getting Started

### 1. Configure Environment
Edit `.env` file:
```env
WAZUH_VERSION=4.7.0
ELASTIC_VERSION=8.13.0
KIBANA_PORT=5601
WAZUH_PORT=55000
```

### 2. Run the Platform
```bash
chmod +x scripts/init.sh
./scripts/init.sh
```

### 3. Access Interfaces
- 🧠 **Wazuh Dashboard**: http://localhost:5601
- 🐝 **TheHive**: http://localhost:9000
- 🧪 **Cortex**: http://localhost:9001
- 🌐 **MISP**: http://localhost:8080
- 🤖 **AI Engine**: http://localhost:11434

---

## 🔍 Features

### ✅ SIEM (Wazuh + Elastic + Kibana)
- Real-time log analysis and visualization
- File integrity monitoring and rootkit detection
- Prebuilt and custom detection rules (Sigma-compatible)
- Agent-based endpoint data collection
- Alert forwarding and external integration support

### ✅ SOAR (TheHive + Cortex)
- Automated case creation and enrichment
- Custom playbooks for incident response
- Cortex analyzers for threat validation (VirusTotal, MISP, etc.)
- Observable analysis and correlation

### ✅ Threat Intel (MISP)
- Threat feed ingestion (community and private)
- IOC sharing, exporting, and correlation
- Cortex analyzer integration for reputation checks
- REST API support for automation

### ✅ AI Engine (Ollama + Python)
- LLM-powered summarization of Wazuh/Elastic alerts
- Custom anomaly detection with scikit-learn
- Auto-tagging and alert classification
- Runs locally using open-source models (LLaMA3, Mistral, etc.)

### ✅ Dashboards + Threat Hunting
- Kibana dashboards for SOC overview
- MITRE ATT&CK mapped detections
- Saved KQL queries and visual filters
- Jupyter-based threat hunting (optional)

### ✅ Automation + Extensibility
- One-command bootstrap with `init.sh`
- Add new analyzers and detection rules easily
- Cortex, MISP, and Elastic all containerized
- Ollama preloaded with language models

---

## 📦 Analyzer Support (Cortex)

Supported analyzers:
- 🔍 VirusTotal
- 🔐 MISP
- 🌍 Shodan
- 🧪 AbuseIPDB
- 🧠 Custom Python models

---

## 🛠️ Maintenance Commands

### Stop & Clean
```bash
./scripts/cleanup.sh
```

### Add new Cortex analyzer:
```bash
cd threat-intel/analyzers
./install-analyzer.sh analyzers/MISP
```

---

## 📚 Documentation
See [docs/deployment-guide.md](docs/deployment-guide.md) for full usage.

> Made with ❤️ for next-gen cyber defenders.

---

## 📅 Version

**Unified SOC Platform** — v2025.1  
Last Updated: August 7, 2025
