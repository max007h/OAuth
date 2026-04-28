#!/bin/bash

echo "======================================================"
echo " PingDirectory Init Script"
echo " Schema + Users + Groups"
echo "======================================================"

CONTAINER="env-pingdirectory-1"
HOST="localhost"
PORT="1636"
BIND_DN="cn=administrator"
BIND_PW="2FederateM0re"

# -------------------------------------------------------
echo ""
echo "[1/3] Waiting for PingDirectory to be ready..."
until docker exec $CONTAINER ldapsearch \
  --hostname $HOST --port $PORT \
  --useSSL --trustAll \
  --bindDN "$BIND_DN" \
  --bindPassword "$BIND_PW" \
  --baseDN "dc=example,dc=com" \
  --searchScope base "(objectClass=*)" > /dev/null 2>&1; do
  echo "  ... not ready yet, retrying in 5s"
  sleep 5
done
echo "  PingDirectory is ready!"

# -------------------------------------------------------
echo ""
echo "[2/3] Registering custom schema (bankingPerson + ibanAccount)..."
docker exec -i $CONTAINER ldapmodify \
  --hostname $HOST --port $PORT \
  --useSSL --trustAll \
  --bindDN "$BIND_DN" \
  --bindPassword "$BIND_PW" << 'SCHEMA'
dn: cn=schema
changetype: modify
add: attributeTypes
attributeTypes: ( 1.3.6.1.4.1.99999.1 NAME 'ibanAccount' SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 SINGLE-VALUE )
-
add: objectClasses
objectClasses: ( 1.3.6.1.4.1.99999.2 NAME 'bankingPerson' SUP top AUXILIARY MAY ( ibanAccount ) )
SCHEMA
echo "  Schema registered!"

# -------------------------------------------------------
echo ""
echo "[3/3] Injecting users and groups..."

cat > /tmp/init-directory.ldif << 'LDIF'
dn: ou=People,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: People

dn: ou=groups,dc=example,dc=com
changetype: add
objectClass: organizationalUnit
ou: groups

dn: uid=Customer_1,ou=People,dc=example,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: person
objectClass: bankingPerson
cn: Customer_1
sn: Customer
uid: Customer_1
userPassword: Password1234!
ibanAccount: FR7630006000011234567890189

dn: uid=Approbateur_1,ou=People,dc=example,dc=com
changetype: add
objectClass: inetOrgPerson
objectClass: person
objectClass: bankingPerson
cn: Approbateur_1
sn: Approbateur
uid: Approbateur_1
userPassword: Password1234!
ibanAccount: FR7630004000031234567890143

dn: cn=CUSTOMERS,ou=groups,dc=example,dc=com
changetype: add
objectClass: groupOfNames
cn: CUSTOMERS
member: uid=Customer_1,ou=People,dc=example,dc=com

dn: cn=APPROVERS,ou=groups,dc=example,dc=com
changetype: add
objectClass: groupOfNames
cn: APPROVERS
member: uid=Approbateur_1,ou=People,dc=example,dc=com
LDIF

docker cp /tmp/init-directory.ldif $CONTAINER:/tmp/init-directory.ldif

docker exec $CONTAINER ldapmodify \
  --hostname $HOST --port $PORT \
  --useSSL --trustAll \
  --bindDN "$BIND_DN" \
  --bindPassword "$BIND_PW" \
  --continueOnError \
  --filename /tmp/init-directory.ldif

echo ""
echo "======================================================"
echo " Verification..."
echo "======================================================"
docker exec $CONTAINER ldapsearch \
  --hostname $HOST --port $PORT \
  --useSSL --trustAll \
  --bindDN "$BIND_DN" \
  --bindPassword "$BIND_PW" \
  --baseDN "dc=example,dc=com" \
  --searchScope sub "(objectClass=inetOrgPerson)" uid ibanAccount

echo ""
echo " Done! PingDirectory is initialized."
echo "======================================================"
