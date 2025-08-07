#!/bin/bash

echo "🧨 Stopping and removing SOC containers..."
docker-compose down -v --remove-orphans
docker system prune -af

echo "✅ Cleaned all containers and volumes."
