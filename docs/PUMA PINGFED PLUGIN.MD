# PUMA phase 2 : choix du noeud dans PingFederate, sans token exchange

Le noeud est choisi dans le parcours PingFederate, sur une page affichée juste après le login. Le token final émis au client puma-portal contient directement sub, node et roles. Le flux actuel par token exchange reste en place tant que celui-ci n'est pas validé.

## 0. Avant de commencer

1. Exporter la configuration PingFederate (System, Configuration Archive).
2. Travailler sur une branche Git pour le front.

## 1. Code

### 1.1 Ajouter la classe

Copier NodeSelectionAdapter.java dans src/main/java/com/poc/adapter/.

Les imports ont été écrits sans voir ceux de ParValidationAdapter. Avant de compiler, remplacer le bloc d'imports de NodeSelectionAdapter par celui de ParValidationAdapter pour les classes communes : HttpServletRequest, HttpServletResponse (javax ou jakarta selon la version), AuthnAdapterException, AuthnPolicy, Configuration, IdpAuthnAdapterDescriptor, AuthnAdapterResponse, IdpAuthenticationAdapterV2. Ajouter HttpSession dans le même package que HttpServletRequest.

Reprendre aussi exactement la forme de l'appel new IdpAuthnAdapterDescriptor(...) de ParValidationAdapter, en remplaçant seulement le nom par "PUMA Node Selection Adapter" et le contrat par Set.of("subject", "node").

### 1.2 Renseigner la connexion à la base

Dans NodeSelectionAdapter, remplacer les trois valeurs A_COMPLETER par celles du data store puma-postgres de PingFederate (URL JDBC, compte, mot de passe). Elles peuvent aussi être passées par les variables d'environnement PUMA_DB_URL, PUMA_DB_USER et PUMA_DB_PASSWORD du conteneur.

### 1.3 Déclarer le plugin

Dans le dossier PF-INF, ouvrir le fichier qui contient déjà com.poc.adapter.ParValidationAdapter et ajouter la ligne :

```
com.poc.adapter.NodeSelectionAdapter
```

### 1.4 Construire et vérifier le jar

```
mvn clean package
unzip -l target/poc-par-validation-adapter.jar | grep -E "NodeSelectionAdapter|PF-INF"
unzip -p target/poc-par-validation-adapter.jar PF-INF/* | grep NodeSelection
```

Attendu : la classe est présente, et le descripteur PF-INF contient les deux adapters.

## 2. Déploiement

```
docker cp target/poc-par-validation-adapter.jar env-pingfederate-1:/opt/out/instance/server/default/deploy/
docker exec env-pingfederate-1 ls -l /opt/out/instance/server/default/lib | grep postgresql
docker restart env-pingfederate-1
```

Le driver postgresql-42.7.3.jar doit être présent dans lib. Attendre la fin du démarrage, puis vérifier dans Authentication, IdP Adapters, Create New Instance, que le type PUMA Node Selection Adapter apparaît.

## 3. Configuration PingFederate

1. Créer l'instance de l'adapter : id NodeSelection, type PUMA Node Selection Adapter. Le contrat contient subject et node.
2. Dans le contrat de politique utilisé par puma-portal (PumaContract), ajouter l'attribut node.
3. Dans PumaAuthPolicy, construire la chaîne : HTMLFormAdapter, puis sur Success NodeSelection, puis sur Success PumaContract. Les branches Fail se terminent sans contrat. Contract Fulfillment : subject et node depuis NodeSelection.
4. Dans l'Access Token Mapping de PumaContract vers l'ATM de puma-portal :
   1. ajouter une source JDBC sur puma_user_node_roles avec le filtre `uid = '${subject}' AND node_id = '${node}'` ;
   2. mapper node depuis le contrat et roles depuis cette source ;
   3. ajouter l'Issuance Criteria sur role_id non vide, avec le message node_not_assigned.
5. Vérifier que l'ATM de puma-portal signe avec la même clé poc-key que JWTAccessToken. Sinon, le backend rejettera le token.

## 4. Frontend PUMA

1. Ne plus ouvrir la pop-up ContextPickerV2 quand le token contient déjà node et roles.
2. Corriger ContextV2Service.hasContext : tester la présence de node et roles dans le token, et non client_id === 'puma-backend'.
3. Changer de contexte revient à relancer une demande d'autorisation. La session PingFederate évite de ressaisir le mot de passe.

## 5. Tests attendus

| Test | Attendu |
|---|---|
| Login thomas.martin | La page de choix s'affiche avec les mêmes noeuds que la requête pgAdmin |
| Choix de Roller 5 | Le token contient node 9200005 et les rôles de thomas sur ce noeud |
| Valeur du select modifiée en 2700015 dans les outils du navigateur | Échec, message Contexte non autorisé, ligne Noeud refuse dans les logs |
| Formulaire renvoyé sans le champ puma_csrf | Échec, message Requete invalide |
| Utilisateur sans aucun rôle sur PUMA | Échec, message Aucun contexte disponible |
| Création d'utilisateur sur 9200005 puis sur 2700015 | PERMIT puis DENY, comme avec le flux actuel |

Logs utiles :

```
docker logs env-pingfederate-1 2>&1 | grep NodeSelectionAdapter
```

Si l'adapter signale qu'aucun utilisateur n'est présent dans les attributs chaînés, la ligne de log affiche les clés reçues : il suffit alors d'ajuster le nom de l'attribut lu dans chainedUid.

## 6. Points d'attention

1. Le token final arrive dans la SPA avec le noeud et les rôles. C'est un écart par rapport à l'engagement pris avec David, sauf si l'échange du code passe par le backend.
2. Le déploiement du jar est perdu si le conteneur est recréé, faute de volume persistant sur /opt/out.
3. Les identifiants de la base sont dans le code ou l'environnement du conteneur : acceptable pour le POC, à remplacer par le data store de PingFederate ou un coffre en cible.
