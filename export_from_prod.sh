#!/bin/bash
# Export workflows and credentials from PROD

CONTAINER=$(docker ps --format "{{.Names}}" | grep n8n | head -1)
echo "Found container: $CONTAINER"

echo "Exporting workflows..."
docker exec $CONTAINER n8n export:workflow --all --output=/tmp/workflows.json

echo "Exporting credentials..."
docker exec $CONTAINER n8n export:credentials --all --output=/tmp/credentials.json --decrypted

echo "Copying files..."
mkdir -p /srv/n8n/exports
docker exec $CONTAINER cat /tmp/workflows.json > /srv/n8n/exports/workflows.json
docker exec $CONTAINER cat /tmp/credentials.json > /srv/n8n/exports/credentials.json

echo "Export complete. Files:"
ls -lh /srv/n8n/exports/

