#!/bin/bash

echo "🚀 Starting SOC Platform setup..."

# Step 1: Pull/update Docker images
docker-compose pull

# Step 2: Start all services
docker-compose up --build -d

# Step 3: Wait for a few services to boot up
echo "⏳ Waiting for containers to initialize..."
sleep 10

# Step 4: Preload Ollama model
if docker exec ollama ollama list | grep -q llama3; then
    echo "✅ Ollama model already loaded."
else
    echo "📥 Pulling llama3 model into Ollama..."
    docker exec ollama ollama run llama3
fi

echo "✅ SOC Platform is up and running!"
echo "🌐 Access Kibana at http://localhost:5601"
echo "🧠 AI engine (Ollama) is running on http://localhost:11434"
