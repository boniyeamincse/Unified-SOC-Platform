FROM docker.elastic.co/elasticsearch/elasticsearch:8.13.0

# Set node type to single-node (for development)
ENV discovery.type=single-node

# Optional: configure JVM heap size (1 GB min)
ENV ES_JAVA_OPTS="-Xms1g -Xmx1g"

# Copy custom configuration if needed (optional)
# COPY elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml
