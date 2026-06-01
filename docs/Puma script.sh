# ============================================
# PORTAIL PUMA — Init PingDirectory
# Exécuter depuis ton terminal macOS
# ============================================

# 1. Créer les fichiers LDIF localement
cat > /tmp/groups.ldif << 'EOF'
dn: cn=COMMERCIAL,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: top
cn: COMMERCIAL
member: uid=dummy,ou=people,dc=example,dc=com

dn: cn=MANAGER,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: top
cn: MANAGER
member: uid=dummy,ou=people,dc=example,dc=com
EOF

cat > /tmp/manager_1.ldif << 'EOF'
dn: uid=thomas.martin,ou=people,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: bankingPerson
objectClass: top
uid: thomas.martin
cn: Thomas Martin
sn: Martin
givenName: Thomas
mail: thomas.martin@example.com
userPassword: Password1234!
EOF

cat > /tmp/commercial_1.ldif << 'EOF'
dn: uid=sophie.bernard,ou=people,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: bankingPerson
objectClass: top
uid: sophie.bernard
cn: Sophie Bernard
sn: Bernard
givenName: Sophie
mail: sophie.bernard@example.com
userPassword: Password1234!
EOF

cat > /tmp/add_manager_group.ldif << 'EOF'
dn: cn=MANAGER,ou=groups,dc=example,dc=com
changetype: modify
add: member
member: uid=thomas.martin,ou=people,dc=example,dc=com
EOF

cat > /tmp/add_commercial_group.ldif << 'EOF'
dn: cn=COMMERCIAL,ou=groups,dc=example,dc=com
changetype: modify
add: member
member: uid=sophie.bernard,ou=people,dc=example,dc=com
EOF

# 2. Copier les fichiers dans le container
docker cp /tmp/groups.ldif             env-pingdirectory-1:/tmp/groups.ldif
docker cp /tmp/manager_1.ldif          env-pingdirectory-1:/tmp/manager_1.ldif
docker cp /tmp/commercial_1.ldif       env-pingdirectory-1:/tmp/commercial_1.ldif
docker cp /tmp/add_manager_group.ldif  env-pingdirectory-1:/tmp/add_manager_group.ldif
docker cp /tmp/add_commercial_group.ldif env-pingdirectory-1:/tmp/add_commercial_group.ldif

# 3. Créer les groupes COMMERCIAL et MANAGER
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapmodify \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -a \
  -f /tmp/groups.ldif

# 4. Créer l'utilisateur Manager : Thomas Martin
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapmodify \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -a \
  -f /tmp/manager_1.ldif

# 5. Créer l'utilisateur Commercial : Sophie Bernard
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapmodify \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -a \
  -f /tmp/commercial_1.ldif

# 6. Ajouter Thomas Martin au groupe MANAGER
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapmodify \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -f /tmp/add_manager_group.ldif

# 7. Ajouter Sophie Bernard au groupe COMMERCIAL
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapmodify \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -f /tmp/add_commercial_group.ldif

# 8. Vérification — membres du groupe MANAGER
echo "\n=== Groupe MANAGER ==="
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapsearch \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -b "cn=MANAGER,ou=groups,dc=example,dc=com" \
  "(objectClass=groupOfNames)" member

# 9. Vérification — membres du groupe COMMERCIAL
echo "\n=== Groupe COMMERCIAL ==="
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapsearch \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -b "cn=COMMERCIAL,ou=groups,dc=example,dc=com" \
  "(objectClass=groupOfNames)" member

# 10. Vérification — utilisateurs créés
echo "\n=== Utilisateurs créés ==="
docker exec env-pingdirectory-1 \
  /opt/out/instance/bin/ldapsearch \
  -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -b "ou=people,dc=example,dc=com" \
  "(|(uid=thomas.martin)(uid=sophie.bernard))" uid cn mail givenName sn
