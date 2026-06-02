docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapsearch \
  --hostname localhost \
  --port 1636 \
  --useSSL \
  --trustAll \
  --bindDN "cn=administrator" \
  --bindPassword "2FederateM0re" \
  --baseDN "ou=people,dc=example,dc=com" \
  "(uid=thomas.martin)" \
  uid isMemberOf
