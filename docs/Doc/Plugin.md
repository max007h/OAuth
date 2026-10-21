# Plugin PingFederate : PUMA Node Selection Adapter

Ce projet (`poc-par-validation-adapter`, package `com.poc.adapter`) est un **plugin PingFederate**, pas un composant PingAuthorize. Il contient deux adapters d'authentification (IdP Adapters) :

- `ParValidationAdapter` : l'adapter existant du POC banking (PAR) ;
- `NodeSelectionAdapter` : l'adapter PUMA. Après la saisie du login et du mot de passe, il lit en base les noeuds sur lesquels l'utilisateur a un rôle, lui affiche la page "Select your context", vérifie côté serveur le noeud choisi, puis transmet `subject` et `node` à PingFederate.

Les deux adapters sont déclarés dans `PF-INF/idp-authn-adapters`.

## Prérequis

- **PingFederate** démarré (conteneur Docker du POC), avec accès à la console d'administration (par défaut `https://localhost:9999/pingfederate/app`)
- **PostgreSQL** avec la base du POC importée : l'adapter lit la vue `puma_user_node_roles` et la table `node`
- Le **driver JDBC PostgreSQL** présent dans PingFederate, et un data store JDBC vers la base PUMA (`puma-postgres`) déclaré dans PingFederate
- **Java 17** et **Maven 3.9** ou plus pour compiler
- Les bibliothèques du SDK PingFederate (notamment `pf-protocolengine.jar`), déclarées dans `pom.xml`. Le plugin doit être compilé avec la même version de PingFederate que celle du conteneur

## 1. Compiler

À la racine du projet :

```bash
mvn clean package
```

Le jar est produit dans `target/`. Vérifier qu'il contient bien le fichier de déclaration des adapters :

```bash
jar tf target/*.jar | grep PF-INF
```

La sortie doit afficher `PF-INF/idp-authn-adapters`.

## 2. Déployer dans le conteneur PingFederate

Repérer le nom du conteneur PingFederate :

```bash
docker ps
```

Copier le jar dans le dossier de déploiement de PingFederate :

```bash
docker cp target/<nom-du-jar>.jar <conteneur-pingfederate>:/opt/out/instance/server/default/deploy/
```

Redémarrer PingFederate pour qu'il charge le plugin :

```bash
docker restart <conteneur-pingfederate>
```

Suivre le démarrage dans les logs :

```bash
docker logs -f <conteneur-pingfederate>
```

En cas d'erreur de chargement du plugin, le détail se trouve dans `/opt/out/instance/log/server.log` à l'intérieur du conteneur.

À chaque nouvelle version du plugin, supprimer l'ancien jar du dossier `deploy` avant de copier le nouveau, pour ne pas avoir deux versions chargées.

## 3. Configurer PingFederate

Après le redémarrage, l'adapter apparaît dans la liste des types d'IdP Adapter. La configuration du POC est la suivante.

### 3.1 Instance de l'adapter

Dans **Authentication > Integration > IdP Adapters**, créer une instance :

- Nom : `PUMANodeSelection`
- Type : PUMA Node Selection Adapter
- Renseigner les paramètres de connexion à la base demandés par l'adapter

### 3.2 Policy contract

Dans **Authentication > Policies > Policy Contracts**, créer le contrat `PumaContractContext` avec les attributs `subject` et `node`.

### 3.3 Selector

Créer le selector `PumaPortalSelector`, basé sur le `client_id` OAuth, avec la valeur `puma-portal`.

### 3.4 Authentication policy

Créer la policy `PumaContextNode`, placée **au-dessus** de la policy existante du POC banking, et déclenchée par `PumaPortalSelector` :

1. HTML Form Adapter (login et mot de passe, vérifiés dans PingDirectory)
2. En cas de succès : `PUMANodeSelection`
3. En cas de succès : contrat `PumaContractContext`, avec `subject` et `node` provenant de l'adapter

Penser à activer les policies, sinon le contrat n'est pas proposé dans les mappings.

### 3.5 Grant mapping

Dans **Applications > OAuth > Authentication Policy Contract Grant Mapping**, mapper `PumaContractContext` : `USER_KEY` et `USER_NAME` à partir de `subject`.

### 3.6 Access Token Mapping

Dans **Applications > OAuth > Access Token Mappings**, créer le mapping `PumaContractContext` vers le gestionnaire de token JWT du POC :

- Source JDBC : data store `puma-postgres`, table `public.puma_user_node_roles`, colonne `role_id`
- Filtre :

```
lower(uid) = lower('${apc.subject}') AND node_id = '${apc.node}'
```

- Mapping des attributs : `sub` et `node` depuis le contrat, `roles` depuis la source JDBC

Cliquer sur **Save** à la fin de l'assistant : sans ce dernier enregistrement, le mapping n'est pas conservé.

## 4. Vérifier

Ouvrir le frontend PUMA et se connecter avec un compte manager :

1. le formulaire de login PingFederate s'affiche ;
2. après connexion, la page "Select your context" liste les noeuds de l'utilisateur ;
3. après le choix d'un noeud, le token reçu par le frontend contient `sub`, `node` et `roles`.

Si la liste des noeuds est vide, vérifier que l'utilisateur a un rôle de l'application PUMA (`A0`) : l'adapter ne liste que les noeuds de cette application.

## Points d'attention

- L'identifiant de l'application PUMA (`A0`) est fixé dans le code de l'adapter.
- Le filtre `lower(...)` de l'Access Token Mapping évite les refus dus à une différence de majuscules entre le login saisi et l'`uid` stocké en base.
