#!/bin/bash
# =============================================================================
#  PUMA - PATCH PingDirectory
# =============================================================================
#  A executer APRES init-directory.sh et puma-groups-users.sh.
#  Ce script ne recree rien : il complete l'existant.
#
#  Ce qu'il fait :
#    1. enregistre 4 attributs + 1 objectClass auxiliaire pumaPartnerUser
#    2. cree les index sur ces attributs, puis les reconstruit
#    3. ajoute pumaPartnerUser et les grants aux entrees DEJA CREEES
#       (thomas.martin, sophie.bernard) - modify, pas add
#    4. verifie
#
#  Idempotent : relancable. Les etapes deja faites rendent une erreur 20
#  (attribute or value exists) qui est ignoree.
# =============================================================================
set -u

CONTAINER="env-pingdirectory-1"
HOST="localhost"
PORT="1636"
BIND_DN="cn=administrator"
BIND_PW="2FederateM0re"

LDAPMODIFY="/opt/out/instance/bin/ldapmodify"
LDAPSEARCH="/opt/out/instance/bin/ldapsearch"
DSCONFIG="/opt/out/instance/bin/dsconfig"
REBUILD="/opt/out/instance/bin/rebuild-index"

echo "=============================================================="
echo " PUMA - Patch PingDirectory"
echo " Schema + Index + Grants sur les entrees existantes"
echo "=============================================================="

# -----------------------------------------------------------------------------
echo ""
echo "[1/4] Enregistrement du schema PUMA..."
# OID : arc 1.3.6.1.4.1.99999.3, pour ne PAS entrer en collision avec
#   99999.1 = ibanAccount   et   99999.2 = bankingPerson
# deja enregistres par init-directory.sh.
# 99999 reste un placeholder de test : en cible, l'arc enregistre de BNP.
#
# Les 4 attributs sont MULTIVALUES (pas de SINGLE-VALUE) : un utilisateur porte
# plusieurs affectations et plusieurs noeuds de perimetre.
# SUBSTR sur partnerGrant : necessaire pour les filtres par prefixe
#   (partnerGrant=BusinessApp1|*)
docker exec -i $CONTAINER $LDAPMODIFY \
  --hostname $HOST --port $PORT --useSSL --trustAll \
  --bindDN "$BIND_DN" --bindPassword "$BIND_PW" << 'SCHEMA'
dn: cn=schema
changetype: modify
add: attributeTypes
attributeTypes: ( 1.3.6.1.4.1.99999.3.1 NAME 'partnerGrant' DESC 'Affectation atomique application|noeud|role - format produit par IDM' EQUALITY caseIgnoreMatch SUBSTR caseIgnoreSubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 X-ORIGIN 'PUMA' )
-
add: attributeTypes
attributeTypes: ( 1.3.6.1.4.1.99999.3.2 NAME 'opScope' DESC 'Perimetre operationnel - noeuds autorises' EQUALITY caseIgnoreMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 X-ORIGIN 'PUMA' )
-
add: attributeTypes
attributeTypes: ( 1.3.6.1.4.1.99999.3.3 NAME 'opScopeExclude' DESC 'Exclusions du perimetre operationnel - prevalent sur opScope' EQUALITY caseIgnoreMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 X-ORIGIN 'PUMA' )
-
add: attributeTypes
attributeTypes: ( 1.3.6.1.4.1.99999.3.4 NAME 'reportScope' DESC 'Perimetre de reporting - souvent a un niveau superieur a opScope' EQUALITY caseIgnoreMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 X-ORIGIN 'PUMA' )
-
add: objectClasses
objectClasses: ( 1.3.6.1.4.1.99999.3.10 NAME 'pumaPartnerUser' DESC 'Classe auxiliaire portant les affectations et perimetres PUMA' SUP top AUXILIARY MAY ( partnerGrant $ opScope $ opScopeExclude $ reportScope ) X-ORIGIN 'PUMA' )
SCHEMA

if [ $? -eq 0 ]; then
  echo "  Schema enregistre."
else
  echo "  Deja enregistre ou erreur : voir le message ci-dessus."
fi

# -----------------------------------------------------------------------------
echo ""
echo "[2/4] Index..."
# Sans index, tout filtre sur partnerGrant declenche un parcours complet et
# PingDirectory refuse la requete au-dela de la limite de recherche.
for IDX in partnerGrant opScope opScopeExclude reportScope; do
  if [ "$IDX" = "partnerGrant" ]; then
    TYPES="--set index-type:equality --set index-type:substring"
  else
    TYPES="--set index-type:equality"
  fi
  docker exec $CONTAINER $DSCONFIG --no-prompt \
    --hostname $HOST --port $PORT --useSSL --trustAll \
    --bindDN "$BIND_DN" --bindPassword "$BIND_PW" \
    create-local-db-index \
    --backend-name userRoot --index-name $IDX $TYPES \
    2>&1 | grep -v "^$" || true
done

# Obligatoire : sans rebuild, l'index existe mais est marque degrade et
# n'est pas utilise par le serveur.
echo "  Reconstruction des index..."
docker exec $CONTAINER $REBUILD --task \
  --hostname $HOST --port $PORT --useSSL --trustAll \
  --bindDN "$BIND_DN" --bindPassword "$BIND_PW" \
  --baseDN "dc=example,dc=com" \
  --index partnerGrant --index opScope \
  --index opScopeExclude --index reportScope

# -----------------------------------------------------------------------------
echo ""
echo "[3/4] Grants sur les entrees existantes..."
# MODIFY et non ADD : thomas.martin et sophie.bernard sont deja crees par
# puma-groups-users.sh. Un changetype: add rendrait erreur 68, entry already exists.
#
# POINT BLOQUANT : sans partnerGrant sur thomas.martin, DelegationService lit une
# liste vide, son sous-arbre est vide, et l'ecran de creation n'affiche aucune
# application ni aucun noeud, SANS message d'erreur.
#
# Les identifiants doivent correspondre au jeu ROLLER charge dans PostgreSQL :
#   9200005 = ROLLER 5, vendors 2700009 a 2700014
#   9200002 = ROLLER 2, vendors 2480004, 2602700, 2700001
# Un grant sur un noeud inconnu de PostgreSQL ne leve rien, il donne juste un
# sous-arbre vide.
docker exec -i $CONTAINER $LDAPMODIFY \
  --hostname $HOST --port $PORT --useSSL --trustAll \
  --bindDN "$BIND_DN" --bindPassword "$BIND_PW" \
  --continueOnError << 'GRANTS'
dn: uid=thomas.martin,ou=people,dc=example,dc=com
changetype: modify
add: objectClass
objectClass: pumaPartnerUser

dn: uid=thomas.martin,ou=people,dc=example,dc=com
changetype: modify
add: partnerGrant
partnerGrant: BusinessApp1|9200005|ShopAdmin
partnerGrant: BusinessApp1|9200002|ShopAdmin
partnerGrant: BusinessApp2|9200005|ShopAdmin

dn: uid=thomas.martin,ou=people,dc=example,dc=com
changetype: modify
add: opScope
opScope: 9200005
opScope: 9200002

dn: uid=thomas.martin,ou=people,dc=example,dc=com
changetype: modify
add: reportScope
reportScope: 9100002

dn: uid=sophie.bernard,ou=people,dc=example,dc=com
changetype: modify
add: objectClass
objectClass: pumaPartnerUser

dn: uid=sophie.bernard,ou=people,dc=example,dc=com
changetype: modify
add: partnerGrant
partnerGrant: BusinessApp1|9200005|Salesman

dn: uid=sophie.bernard,ou=people,dc=example,dc=com
changetype: modify
add: opScope
opScope: 2700010
opScope: 2700011

dn: uid=sophie.bernard,ou=people,dc=example,dc=com
changetype: modify
add: opScopeExclude
opScopeExclude: 2700012

dn: uid=sophie.bernard,ou=people,dc=example,dc=com
changetype: modify
add: reportScope
reportScope: 9200005
GRANTS
echo "  Grants poses. Les erreurs 20 (value exists) sont normales en relance."

# -----------------------------------------------------------------------------
echo ""
echo "[4/4] Verifications"

echo ""
echo "-- partnerGrant est-il dans le schema ?"
docker exec $CONTAINER $LDAPSEARCH \
  --hostname $HOST --port $PORT --useSSL --trustAll \
  --bindDN "$BIND_DN" --bindPassword "$BIND_PW" \
  --baseDN "cn=schema" --searchScope base \
  "(objectClass=*)" attributeTypes 2>/dev/null \
  | grep -i "partnerGrant" \
  || echo "  ECHEC : partnerGrant absent du schema"

echo ""
echo "-- Grants du manager (attendu : 3 partnerGrant, 2 opScope, 1 reportScope)"
docker exec $CONTAINER $LDAPSEARCH \
  --hostname $HOST --port $PORT --useSSL --trustAll \
  --bindDN "$BIND_DN" --bindPassword "$BIND_PW" \
  --baseDN "ou=people,dc=example,dc=com" \
  "(uid=thomas.martin)" \
  objectClass partnerGrant opScope reportScope isMemberOf

echo ""
echo "-- Recherche par index (ne doit pas signaler unindexed)"
docker exec $CONTAINER $LDAPSEARCH \
  --hostname $HOST --port $PORT --useSSL --trustAll \
  --bindDN "$BIND_DN" --bindPassword "$BIND_PW" \
  --baseDN "ou=people,dc=example,dc=com" \
  "(partnerGrant=BusinessApp1|9200005|ShopAdmin)" uid

echo ""
echo "=============================================================="
echo " Patch termine."
echo ""
echo " Reste a faire hors de ce script :"
echo "   - application.yml : admin-dn: cn=administrator  (sans dc=example,dc=com)"
echo "   - createViaLdap   : oc.add(\"pumaPartnerUser\")"
echo "   - PumaJWTToken    : ajouter le claim sub"
echo "=============================================================="
