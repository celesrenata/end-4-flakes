#!/usr/bin/env bash

# Query Ollama API for models with metadata (context length)
# Output: JSON array of objects with "name" and "context_length" fields

response=$(curl -s --connect-timeout 5 http://localhost:11434/api/tags 2>/dev/null)

if [ -z "$response" ] || echo "$response" | grep -q '"error"'; then
    # Fallback: just output empty array
    echo "[]"
    exit 0
fi

# Use python3 to extract model names and context lengths
echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    models = data.get('models', [])
    result = []
    for m in models:
        entry = {
            'name': m.get('name', ''),
            'context_length': m.get('details', {}).get('context_length', 0)
        }
        result.append(entry)
    print(json.dumps(result))
except Exception:
    print('[]')
" 2>/dev/null || echo "[]"
