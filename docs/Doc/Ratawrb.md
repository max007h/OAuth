# Application partenaire (Rataweb), backend

API de l'application partenaire Rataweb : consultation et approbation des contrats, avec décision d'autorisation par PingAuthorize.

## Prérequis

- Java 17 (version définie dans `pom.xml`)
- Maven 3.9 ou plus
- La base du POC importée (schéma `rataweb`, fournie dans le dépôt PUMA backend : `db/puma-poc.sql`)
- PingFederate et PingAuthorize démarrés

## 1. Vérifier la configuration

Dans `src/main/resources/application.yml`, vérifier :

- la connexion PostgreSQL (schéma `rataweb`)
- l'URL du PDP PingAuthorize (par défaut `https://localhost:7443/governance-engine`)
- l'émetteur et la clé de vérification des tokens PingFederate

## 2. Démarrer

```bash
mvn clean spring-boot:run
```

Le port d'écoute est défini par `server.port` dans `application.yml`.

## 3. Réinitialiser les contrats de démonstration

Pour remettre les contrats d'un noeud dans leur état initial (non approuvés) avant une démonstration :

```sql
UPDATE rataweb.contract
SET status = 'PENDING', approved_by = NULL, approved_at = NULL
WHERE node_id = '2700012';
COMMIT;
```

Remplacer `2700012` par le noeud utilisé. Sans clause `WHERE`, tous les contrats sont réinitialisés.

## 4. Vérifier

Avec un compte conseiller, les contrats du noeud s'affichent mais l'approbation est refusée. Avec un compte superviseur, un contrat de moins de 20 000 euros est approuvé, un contrat au-dessus est refusé.
