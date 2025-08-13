const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
const port = 3000;

app.use(cors());
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// SOC Platform Dashboard Routes
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/api/status', (req, res) => {
    res.json({
        status: 'healthy',
        platform: 'SOC Platform v2025.1',
        timestamp: new Date().toISOString(),
        services: {
            elasticsearch: 'http://elasticsearch:9200',
            kibana: 'http://kibana:5601',
            wazuh_manager: 'http://wazuh-manager:55000',
            wazuh_dashboard: 'http://wazuh-dashboard:5601',
            ollama: 'http://ollama:11434'
        }
    });
});

app.listen(port, '0.0.0.0', () => {
    console.log(`🛡️ SOC Platform UI running at http://localhost:${port}`);
});
