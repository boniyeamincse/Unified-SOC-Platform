from flask import Flask, render_template, request, jsonify
from flask_cors import CORS
import requests
import json
import os
from datetime import datetime, timedelta
from elasticsearch import Elasticsearch
import re

app = Flask(__name__)
CORS(app)

# Configuration
ELASTICSEARCH_URL = os.getenv('ELASTICSEARCH_URL', 'http://localhost:9200')
MISP_URL = os.getenv('MISP_URL', 'http://localhost:8080')
WAZUH_URL = os.getenv('WAZUH_URL', 'http://localhost:55000')

# Initialize Elasticsearch client
try:
    es = Elasticsearch([ELASTICSEARCH_URL])
except Exception as e:
    print(f"Failed to connect to Elasticsearch: {e}")
    es = None

class ThreatHunter:
    def __init__(self):
        self.es = es
        
        # MITRE ATT&CK TTPs mapped to search queries
        self.attack_patterns = {
            'T1078': {  # Valid Accounts
                'name': 'Valid Accounts',
                'query': 'event.category:authentication AND event.outcome:success AND user.name:("admin" OR "administrator" OR "root")',
                'description': 'Detect use of valid accounts for unauthorized access'
            },
            'T1110': {  # Brute Force
                'name': 'Brute Force',
                'query': 'event.category:authentication AND event.outcome:failure',
                'description': 'Multiple failed authentication attempts'
            },
            'T1059': {  # Command and Scripting Interpreter
                'name': 'Command and Scripting Interpreter',
                'query': 'process.name:("cmd.exe" OR "powershell.exe" OR "bash" OR "sh") AND process.args:*',
                'description': 'Suspicious command line activity'
            },
            'T1055': {  # Process Injection
                'name': 'Process Injection',
                'query': 'event.category:process AND process.name:("svchost.exe" OR "winlogon.exe" OR "lsass.exe")',
                'description': 'Potential process injection activity'
            },
            'T1071': {  # Application Layer Protocol
                'name': 'Application Layer Protocol',
                'query': 'network.protocol:("http" OR "https" OR "dns") AND destination.port:(80 OR 443 OR 53)',
                'description': 'Suspicious network protocol usage'
            },
            'T1105': {  # Ingress Tool Transfer
                'name': 'Ingress Tool Transfer',
                'query': 'file.extension:("exe" OR "dll" OR "bat" OR "ps1" OR "sh") AND file.path:*',
                'description': 'File transfers and tool deployment'
            }
        }
        
        # IOC patterns
        self.ioc_patterns = {
            'ip': r'^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
            'domain': r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$',
            'md5': r'^[a-fA-F0-9]{32}$',
            'sha1': r'^[a-fA-F0-9]{40}$',
            'sha256': r'^[a-fA-F0-9]{64}$',
            'email': r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
            'url': r'^https?://[^\s/$.?#].[^\s]*$'
        }
        
    def hunt_mitre_attack(self, technique_id, time_range='24h'):
        """Hunt for specific MITRE ATT&CK techniques"""
        if not self.es:
            return {"error": "Elasticsearch not connected"}
            
        if technique_id not in self.attack_patterns:
            return {"error": f"Unknown MITRE ATT&CK technique: {technique_id}"}
            
        technique = self.attack_patterns[technique_id]
        
        try:
            # Calculate time range
            now = datetime.utcnow()
            if time_range == '1h':
                start_time = now - timedelta(hours=1)
            elif time_range == '24h':
                start_time = now - timedelta(hours=24)
            elif time_range == '7d':
                start_time = now - timedelta(days=7)
            else:
                start_time = now - timedelta(hours=24)
            
            search_body = {
                "query": {
                    "bool": {
                        "must": [
                            {"query_string": {"query": technique['query']}},
                            {"range": {"@timestamp": {"gte": start_time.isoformat()}}}
                        ]
                    }
                },
                "size": 100,
                "sort": [{"@timestamp": {"order": "desc"}}],
                "aggs": {
                    "hosts": {
                        "terms": {"field": "host.name.keyword", "size": 10}
                    },
                    "users": {
                        "terms": {"field": "user.name.keyword", "size": 10}
                    }
                }
            }
            
            result = self.es.search(index="*", body=search_body)
            return {
                "technique": technique,
                "results": result,
                "timeline": self._create_timeline(result['hits']['hits'])
            }
        except Exception as e:
            return {"error": str(e)}
    
    def hunt_iocs(self, iocs, time_range='24h'):
        """Hunt for Indicators of Compromise"""
        if not self.es:
            return {"error": "Elasticsearch not connected"}
            
        results = {}
        
        for ioc in iocs:
            ioc_type = self._detect_ioc_type(ioc)
            query = self._build_ioc_query(ioc, ioc_type)
            
            if query:
                try:
                    # Calculate time range
                    now = datetime.utcnow()
                    if time_range == '1h':
                        start_time = now - timedelta(hours=1)
                    elif time_range == '24h':
                        start_time = now - timedelta(hours=24)
                    elif time_range == '7d':
                        start_time = now - timedelta(days=7)
                    else:
                        start_time = now - timedelta(hours=24)
                    
                    search_body = {
                        "query": {
                            "bool": {
                                "must": [
                                    {"query_string": {"query": query}},
                                    {"range": {"@timestamp": {"gte": start_time.isoformat()}}}
                                ]
                            }
                        },
                        "size": 50,
                        "sort": [{"@timestamp": {"order": "desc"}}]
                    }
                    
                    result = self.es.search(index="*", body=search_body)
                    results[ioc] = {
                        "type": ioc_type,
                        "matches": result['hits']['total']['value'],
                        "hits": result['hits']['hits']
                    }
                except Exception as e:
                    results[ioc] = {"error": str(e)}
        
        return results
    
    def hunt_anomalies(self, time_range='24h'):
        """Hunt for behavioral anomalies"""
        if not self.es:
            return {"error": "Elasticsearch not connected"}
            
        anomalies = {}
        
        # Hunt for unusual login times
        anomalies['unusual_logins'] = self._hunt_unusual_login_times(time_range)
        
        # Hunt for privilege escalation
        anomalies['privilege_escalation'] = self._hunt_privilege_escalation(time_range)
        
        # Hunt for data exfiltration
        anomalies['data_exfiltration'] = self._hunt_data_exfiltration(time_range)
        
        # Hunt for lateral movement
        anomalies['lateral_movement'] = self._hunt_lateral_movement(time_range)
        
        return anomalies
    
    def _detect_ioc_type(self, ioc):
        """Detect the type of IOC"""
        for ioc_type, pattern in self.ioc_patterns.items():
            if re.match(pattern, ioc):
                return ioc_type
        return 'unknown'
    
    def _build_ioc_query(self, ioc, ioc_type):
        """Build Elasticsearch query for IOC"""
        if ioc_type == 'ip':
            return f'(source.ip:"{ioc}" OR destination.ip:"{ioc}" OR client.ip:"{ioc}" OR server.ip:"{ioc}")'
        elif ioc_type == 'domain':
            return f'(domain:"{ioc}" OR url.domain:"{ioc}" OR dns.question.name:"{ioc}")'
        elif ioc_type in ['md5', 'sha1', 'sha256']:
            return f'(file.hash.md5:"{ioc}" OR file.hash.sha1:"{ioc}" OR file.hash.sha256:"{ioc}")'
        elif ioc_type == 'email':
            return f'(email.from.address:"{ioc}" OR email.to.address:"{ioc}" OR user.email:"{ioc}")'
        elif ioc_type == 'url':
            return f'(url.original:"{ioc}" OR url.full:"{ioc}")'
        else:
            return f'"{ioc}"'
    
    def _hunt_unusual_login_times(self, time_range):
        """Hunt for logins outside business hours"""
        try:
            search_body = {
                "query": {
                    "bool": {
                        "must": [
                            {"term": {"event.category": "authentication"}},
                            {"term": {"event.outcome": "success"}},
                            {"range": {"@timestamp": {"gte": f"now-{time_range}"}}}
                        ],
                        "should": [
                            {"range": {"@timestamp": {"time_zone": "UTC", "format": "hour", "gte": "22"}}},
                            {"range": {"@timestamp": {"time_zone": "UTC", "format": "hour", "lt": "06"}}}
                        ]
                    }
                },
                "size": 20,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            result = self.es.search(index="*", body=search_body)
            return result
        except Exception as e:
            return {"error": str(e)}
    
    def _hunt_privilege_escalation(self, time_range):
        """Hunt for potential privilege escalation"""
        try:
            search_body = {
                "query": {
                    "bool": {
                        "must": [
                            {"query_string": {"query": 'process.args:("runas" OR "sudo" OR "su" OR "net user" OR "net group")'}},
                            {"range": {"@timestamp": {"gte": f"now-{time_range}"}}}
                        ]
                    }
                },
                "size": 20,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            result = self.es.search(index="*", body=search_body)
            return result
        except Exception as e:
            return {"error": str(e)}
    
    def _hunt_data_exfiltration(self, time_range):
        """Hunt for potential data exfiltration"""
        try:
            search_body = {
                "query": {
                    "bool": {
                        "must": [
                            {"range": {"network.bytes": {"gte": 10485760}}},  # 10MB+
                            {"term": {"network.direction": "outbound"}},
                            {"range": {"@timestamp": {"gte": f"now-{time_range}"}}}
                        ]
                    }
                },
                "size": 20,
                "sort": [{"network.bytes": {"order": "desc"}}]
            }
            
            result = self.es.search(index="*", body=search_body)
            return result
        except Exception as e:
            return {"error": str(e)}
    
    def _hunt_lateral_movement(self, time_range):
        """Hunt for lateral movement indicators"""
        try:
            search_body = {
                "query": {
                    "bool": {
                        "must": [
                            {"query_string": {"query": 'process.name:("net.exe" OR "psexec.exe" OR "wmic.exe" OR "ssh.exe")'}},
                            {"range": {"@timestamp": {"gte": f"now-{time_range}"}}}
                        ]
                    }
                },
                "size": 20,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            result = self.es.search(index="*", body=search_body)
            return result
        except Exception as e:
            return {"error": str(e)}
    
    def _create_timeline(self, hits):
        """Create timeline from search hits"""
        timeline = {}
        for hit in hits:
            timestamp = hit['_source'].get('@timestamp', 'Unknown')
            if timestamp != 'Unknown':
                date_key = timestamp[:10]  # YYYY-MM-DD
                if date_key not in timeline:
                    timeline[date_key] = 0
                timeline[date_key] += 1
        return timeline

# Initialize threat hunter
threat_hunter = ThreatHunter()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/health')
def health():
    return jsonify({
        "status": "healthy",
        "services": {
            "elasticsearch": "connected" if es else "disconnected"
        }
    })

@app.route('/api/hunt/mitre/<technique_id>')
def hunt_mitre_technique(technique_id):
    time_range = request.args.get('time_range', '24h')
    result = threat_hunter.hunt_mitre_attack(technique_id, time_range)
    return jsonify(result)

@app.route('/api/hunt/iocs', methods=['POST'])
def hunt_iocs():
    data = request.get_json()
    iocs = data.get('iocs', [])
    time_range = data.get('time_range', '24h')
    
    result = threat_hunter.hunt_iocs(iocs, time_range)
    return jsonify(result)

@app.route('/api/hunt/anomalies')
def hunt_anomalies():
    time_range = request.args.get('time_range', '24h')
    result = threat_hunter.hunt_anomalies(time_range)
    return jsonify(result)

@app.route('/api/attack/patterns')
def get_attack_patterns():
    return jsonify(threat_hunter.attack_patterns)

if __name__ == '__main__':
    print("🔍 Starting Threat Hunting Interface...")
    print(f"Elasticsearch: {ELASTICSEARCH_URL}")
    print(f"MISP: {MISP_URL}")
    app.run(host='0.0.0.0', port=7777, debug=False)
