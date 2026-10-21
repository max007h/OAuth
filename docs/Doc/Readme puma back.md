# PUMA, backend

API Spring Boot du portail d'administration PUMA : utilisateurs, affectations, rôles et appels au PDP PingAuthorize.

## Prérequis

- Java 17 (version définie dans `pom.xml`)
- Maven 3.9 ou plus
- PostgreSQL 14 ou plus
- La stack Ping démarrée : PingDirectory, PingFederate et PingAuthorize (voir la page Confluence du POC)

## Ordre de démarrage

1. PostgreSQL, avec la base importée (voir ci-dessous)
2. PingDirectory, PingFederate, PingAuthorize
3. Ce backend
4. Le frontend PUMA

## 1. Importer la base de données

La base complète du POC (schéma `public` pour PUMA, schéma `rataweb` pour l'application partenaire, vues et données de démonstration) est fournie dans `db/puma-poc.sql`. Elle doit être importée **avant** le premier démarrage.

```bash
psql -h localhost -U postgres -d postgres -f db/puma-poc.sql
```

Cette base contient notamment la vue `puma_user_node_roles`, qui calcule l'héritage des rôles dans la hiérarchie. Elle est utilisée par PingFederate et PingAuthorize : sans elle, le login et les décisions d'autorisation ne fonctionnent pas.

## 2. Vérifier la configuration

Dans `src/main/resources/application.yml`, vérifier :

- `spring.datasource.url`, `username`, `password` : la base importée à l'étape 1
- `spring.jpa.hibernate.ddl-auto` : doit valoir `validate` ou `none`, pour que l'application ne modifie pas la base au démarrage
- `spring.sql.init.mode` : doit valoir `never`, la base étant déjà importée
- les paramètres LDAP `puma.ldap.*` : l'instance PingDirectory
- l'URL du PDP PingAuthorize (par défaut `https://localhost:7443/governance-engine`)
- l'émetteur et la clé de vérification des tokens PingFederate

## 3. Démarrer

```bash
mvn clean spring-boot:run
```

Ou en construisant le jar :

```bash
mvn clean package
java -jar target/*.jar
```

Le backend écoute sur le port **8081**. Le démarrage est réussi quand les logs affichent `Started ... in ... seconds`.

## 4. Vérifier

Se connecter au frontend PUMA avec un compte manager (comptes de test listés sur la page Confluence), choisir un noeud, puis ouvrir la page Users : la liste des affectations du périmètre doit s'afficher.

Les appels au PDP sont tracés dans les logs avec la ligne `Preparing Data for PDP`.
