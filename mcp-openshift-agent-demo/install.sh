#!/usr/bin/env bash
set -euo pipefail

oc apply -k .
oc rollout status deployment/ocp-mcp-server -n agent-demo
oc get svc ocp-mcp-server -n agent-demo
echo "Endpoint: http://ocp-mcp-server.agent-demo.svc.cluster.local:8080/sse"
