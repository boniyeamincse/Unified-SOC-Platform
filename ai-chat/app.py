from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import requests
import json
import os
from datetime import datetime, timedelta
from elasticsearch import Elasticsearch
import re

app = Flask(__name__)
app.config['SECRET_KEY'] = 'soc-ai-chat-secret'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration
OLLAMA_URL = os.getenv('OLLAMA_URL', 'http://localhost:11434')
ELASTICSEARCH_URL = os.getenv('ELASTICSEARCH_URL', 'http://localhost:9200')
WAZUH_API_URL = os.getenv('WAZUH_API_URL', 'http://localhost:55000')

# Initialize Elasticsearch client
try:
    es = Elasticsearch([ELASTICSEARCH_URL])
except Exception as e:
    print(f"Failed to connect to Elasticsearch: {e}")
    es = None

class SOCAnalyzer:
    def __init__(self):
        self.es = es
        
    def search_logs(self, query, time_range='1h', index_pattern='*'):
        """Search logs in Elasticsearch"""
        if not self.es:
            return {"error": "Elasticsearch not connected"}
            
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
                start_time = now - timedelta(hours=1)
            
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
            
            result = self.es.search(index=index_pattern, body=search_body)
            return result
        except Exception as e:
            return {"error": str(e)}
    
    def get_security_alerts(self, severity='medium', limit=20):
        """Get recent security alerts"""
        if not self.es:
            return {"error": "Elasticsearch not connected"}
            
        try:
            search_body = {
                "query": {
                    "bool": {
                        "must": [
                            {"term": {"event.category": "security"}},
                            {"range": {"@timestamp": {"gte": "now-24h"}}}
                        ],
                        "should": [
                            {"term": {"event.severity": severity}}
                        ]
                    }
                },
                "size": limit,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            result = self.es.search(index="wazuh-alerts-*", body=search_body)
            return result
        except Exception as e:
            return {"error": str(e)}
    
    def analyze_with_ai(self, logs_data, question):
        """Analyze logs using Ollama AI"""
        try:
            # Prepare context from logs
            log_context = ""
            if 'hits' in logs_data and 'hits' in logs_data['hits']:
                for hit in logs_data['hits']['hits'][:10]:  # Limit to 10 logs for context
                    source = hit['_source']
                    timestamp = source.get('@timestamp', 'Unknown')
                    message = source.get('message', source.get('event', {}).get('original', 'No message'))
                    log_context += f"Time: {timestamp}\nLog: {message}\n\n"
            
            # Create prompt for AI analysis
            prompt = f"""
You are a cybersecurity expert analyzing SOC logs. Based on the following log data, answer the user's question.

LOG DATA:
{log_context[:2000]}  # Limit context length

USER QUESTION: {question}

Please provide:
1. A clear analysis of the logs
2. Any security concerns or patterns identified
3. Recommended actions if applicable
4. Risk assessment (Low/Medium/High)

Keep your response focused and actionable for SOC analysts.
"""

            # Call Ollama API
            response = requests.post(
                f"{OLLAMA_URL}/api/generate",
                json={
                    "model": "llama3",
                    "prompt": prompt,
                    "stream": False
                },
                timeout=30
            )
            
            if response.status_code == 200:
                result = response.json()
                return result.get('response', 'No response from AI model')
            else:
                return f"AI model error: {response.status_code}"
                
        except Exception as e:
            return f"AI analysis error: {str(e)}"

# Initialize analyzer
soc_analyzer = SOCAnalyzer()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/health')
def health():
    return jsonify({
        "status": "healthy",
        "services": {
            "elasticsearch": "connected" if es else "disconnected",
            "ollama": "available"
        }
    })

@socketio.on('connect')
def handle_connect():
    print('Client connected')
    emit('status', {'msg': 'Connected to SOC AI Assistant'})

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')

@socketio.on('analyze_logs')
def handle_log_analysis(data):
    question = data.get('question', '')
    query = data.get('query', '*')
    time_range = data.get('time_range', '1h')
    
    emit('status', {'msg': 'Searching logs...'})
    
    # Search logs
    logs = soc_analyzer.search_logs(query, time_range)
    
    if 'error' in logs:
        emit('response', {'error': logs['error']})
        return
    
    emit('status', {'msg': 'Analyzing with AI...'})
    
    # Analyze with AI
    analysis = soc_analyzer.analyze_with_ai(logs, question)
    
    # Send response
    emit('response', {
        'analysis': analysis,
        'logs_found': logs.get('hits', {}).get('total', {}).get('value', 0),
        'query': query,
        'time_range': time_range
    })

@socketio.on('get_alerts')
def handle_get_alerts(data):
    severity = data.get('severity', 'medium')
    limit = data.get('limit', 20)
    
    emit('status', {'msg': 'Retrieving security alerts...'})
    
    alerts = soc_analyzer.get_security_alerts(severity, limit)
    
    if 'error' in alerts:
        emit('response', {'error': alerts['error']})
        return
    
    # Format alerts for display
    formatted_alerts = []
    if 'hits' in alerts and 'hits' in alerts['hits']:
        for hit in alerts['hits']['hits']:
            source = hit['_source']
            formatted_alerts.append({
                'timestamp': source.get('@timestamp'),
                'rule': source.get('rule', {}).get('description', 'Unknown rule'),
                'level': source.get('rule', {}).get('level', 0),
                'agent': source.get('agent', {}).get('name', 'Unknown'),
                'location': source.get('location', 'Unknown'),
                'description': source.get('full_log', 'No description')
            })
    
    emit('alerts', {
        'alerts': formatted_alerts,
        'total': alerts.get('hits', {}).get('total', {}).get('value', 0)
    })

@socketio.on('threat_hunt')
def handle_threat_hunt(data):
    indicators = data.get('indicators', [])
    
    emit('status', {'msg': 'Starting threat hunt...'})
    
    hunt_results = []
    
    for indicator in indicators:
        if indicator.get('type') == 'ip':
            query = f"source.ip:{indicator['value']} OR destination.ip:{indicator['value']}"
        elif indicator.get('type') == 'domain':
            query = f"domain:{indicator['value']} OR url.domain:{indicator['value']}"
        elif indicator.get('type') == 'hash':
            query = f"file.hash.md5:{indicator['value']} OR file.hash.sha1:{indicator['value']} OR file.hash.sha256:{indicator['value']}"
        else:
            query = indicator.get('value', '')
        
        logs = soc_analyzer.search_logs(query, '24h')
        
        hunt_results.append({
            'indicator': indicator,
            'matches': logs.get('hits', {}).get('total', {}).get('value', 0),
            'logs': logs.get('hits', {}).get('hits', [])[:5]  # First 5 matches
        })
    
    emit('hunt_results', {'results': hunt_results})

if __name__ == '__main__':
    print("🤖 Starting SOC AI Chat Interface...")
    print(f"Elasticsearch: {ELASTICSEARCH_URL}")
    print(f"Ollama: {OLLAMA_URL}")
    socketio.run(app, host='0.0.0.0', port=8888, debug=False)
