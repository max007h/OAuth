docker exec env-pingfederate-1 grep -r "puma-portal" /opt/out/instance/server/default/data/ 2>/dev/null

docker exec env-pingfederate-1 cat /opt/out/instance/server/default/data/oauth-clients/0/2faf3053c30c13380aa110ff25e4a87bdfa83996.xml
