docker exec env-pingfederate-1 find /opt/out/instance -name "*.xml" | xargs grep -l "puma-portal" 2>/dev/null
