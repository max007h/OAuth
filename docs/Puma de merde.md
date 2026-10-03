-- =====================================================================
-- PUMA : migration 2026-10 (cas A, sans les vues partenaires)
-- Pour une base où partner_user_node_roles et partner_user_node_permissions
-- n'ont jamais été créées. Elles sont créées ici.
-- puma_user garde uid, status, created_at, created_by : plus aucune donnée
-- d'identité (email, nom). Codes de rôles. Vues recréées.
-- A exécuter une seule fois dans pgAdmin, d'un bloc. Transaction unique :
-- au moindre écart, rien n'est modifié.
-- =====================================================================
BEGIN;

-- 0. Photo des vues avant migration
CREATE TEMP TABLE snap_roles ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, role_id FROM puma_user_node_roles;

-- 1. Les vues sont retirées puis recréées à l'identique (plus role_code)
DROP VIEW IF EXISTS partner_user_node_permissions;
DROP VIEW IF EXISTS partner_user_node_roles;
DROP VIEW puma_user_node_roles;

-- 2. puma_user : plus de données d'identité
ALTER TABLE puma_user DROP COLUMN email;
ALTER TABLE puma_user DROP COLUMN display_name;
ALTER TABLE puma_user ADD COLUMN IF NOT EXISTS created_by varchar(100);

-- Codes des rôles globaux : un mot, sans espace, affiché dans le frontend
-- et émis dans le claim roles (les spécialisations n'ont pas de code)
ALTER TABLE app_role ADD COLUMN IF NOT EXISTS code varchar(50);

UPDATE app_role r SET code = c.code
FROM (VALUES
  ('R20', 'PUMA_ADMIN'),
  ('R21', 'USER_MANAGER'),
  ('R22', 'USER_VIEWER'),
  ('R23', 'CATALOGUE_OWNER'),
  ('R10', 'PARTNER_ADMIN'),
  ('R11', 'TEMPORARY_SELLER'),
  ('R12', 'POINT_OF_SALE_MANAGER'),
  ('R13', 'SELLER'),
  ('R14', 'SALES_MANAGER'),
  ('R15', 'FINANCING_ADVISOR'),
  ('R16', 'FINANCING_SUPERVISOR')
) AS c(id, code)
WHERE r.id = c.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_role_code ON app_role (code) WHERE code IS NOT NULL;

-- Index utiles aux vues et au PDP
CREATE INDEX IF NOT EXISTS idx_node_parent_parent ON node_parent (parent_id);
CREATE INDEX IF NOT EXISTS idx_node_parent_node   ON node_parent (node_id);
CREATE INDEX IF NOT EXISTS idx_assignment_user    ON assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_app_role_parent    ON app_role (parent_role_id);

-- Vues : héritage descendant, rôle global, application disponible sur le noeud
CREATE VIEW puma_user_node_roles AS
WITH RECURSIVE scope AS (
    SELECT a.user_id, a.role_id, a.node_id
    FROM assignment a
  UNION
    SELECT s.user_id, s.role_id, np.node_id
    FROM scope s
    JOIN node_parent np ON np.parent_id = s.node_id
)
SELECT DISTINCT u.uid, s.node_id,
       g.id   AS role_id,
       g.application_id,
       g.code AS role_code
FROM scope s
JOIN puma_user u         ON u.id = s.user_id
JOIN app_role r          ON r.id = s.role_id
JOIN app_role g          ON g.id = COALESCE(r.parent_role_id, r.id)
JOIN node_application na ON na.node_id = s.node_id
                        AND na.application_id = r.application_id
WHERE u.status = 'ACTIVE';

CREATE VIEW partner_user_node_roles AS
SELECT v.uid, v.node_id, v.role_id, r.application_id
FROM puma_user_node_roles v
JOIN app_role r ON r.id = v.role_id;

CREATE VIEW partner_user_node_permissions AS
SELECT DISTINCT v.uid, v.node_id, v.application_id, p.code AS permission_code
FROM partner_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id;

-- Contrôle de non-régression : mêmes lignes qu'avant la migration
DO $$
DECLARE
  diff_roles int;
BEGIN
  SELECT count(*) INTO diff_roles FROM (
    (SELECT uid, node_id, role_id FROM snap_roles
     EXCEPT SELECT uid, node_id, role_id FROM puma_user_node_roles)
    UNION ALL
    (SELECT uid, node_id, role_id FROM puma_user_node_roles
     EXCEPT SELECT uid, node_id, role_id FROM snap_roles)) d;

  IF diff_roles > 0 THEN
    RAISE EXCEPTION 'Migration annulee : % ecarts sur puma_user_node_roles', diff_roles;
  END IF;
  RAISE NOTICE 'Controle OK : puma_user_node_roles identique avant et apres migration';
END $$;

COMMIT;















-- =====================================================================
-- PUMA : migration 2026-10 (cas B : la migration du 30/09 a été lancée)
-- Recrée puma_user sous forme réduite (uid, status, created_at, created_by)
-- et revient à assignment.user_id. Retire les colonnes de décision ajoutées
-- le 30/09 (le workflow catalogue est reporté). Codes de rôles. Vues.
-- A exécuter une seule fois dans pgAdmin, d'un bloc. Transaction unique.
-- =====================================================================
BEGIN;

-- 0. Photo des vues avant migration
CREATE TEMP TABLE snap_roles ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, role_id FROM puma_user_node_roles;
CREATE TEMP TABLE snap_perms ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, application_id, permission_code FROM partner_user_node_permissions;

-- 1. Garde-fou : une affectation suspendue individuellement serait perdue
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM assignment WHERE status <> 'ACTIVE') THEN
    RAISE EXCEPTION 'Migration annulee : des affectations SUSPENDED existent, a traiter avant';
  END IF;
END $$;

DROP VIEW partner_user_node_permissions;
DROP VIEW partner_user_node_roles;
DROP VIEW puma_user_node_roles;

-- 2. puma_user réduite, alimentée par les uid des affectations
CREATE TABLE puma_user (
  id         bigserial    PRIMARY KEY,
  uid        varchar(100) NOT NULL UNIQUE,
  status     varchar(20)  NOT NULL DEFAULT 'ACTIVE',
  created_at timestamptz  NOT NULL DEFAULT now(),
  created_by varchar(100)
);

INSERT INTO puma_user (uid) SELECT DISTINCT uid FROM assignment;

-- 3. assignment revient à user_id
ALTER TABLE assignment ADD COLUMN user_id bigint;
UPDATE assignment a SET user_id = u.id FROM puma_user u WHERE u.uid = a.uid;
ALTER TABLE assignment ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE assignment ADD CONSTRAINT fk_assignment_user
  FOREIGN KEY (user_id) REFERENCES puma_user(id) ON DELETE CASCADE;

ALTER TABLE assignment DROP CONSTRAINT uq_assignment;
DROP INDEX IF EXISTS idx_assignment_uid;
ALTER TABLE assignment DROP COLUMN uid;
ALTER TABLE assignment DROP COLUMN status;
ALTER TABLE assignment ADD CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id);

-- 4. Colonnes de décision du 30/09 retirées
ALTER TABLE role_permission DROP CONSTRAINT IF EXISTS chk_role_permission_decision;
ALTER TABLE role_permission
  DROP COLUMN IF EXISTS decision_status,
  DROP COLUMN IF EXISTS requested_by,
  DROP COLUMN IF EXISTS requested_at,
  DROP COLUMN IF EXISTS decided_by,
  DROP COLUMN IF EXISTS decided_at;

-- Codes des rôles globaux : un mot, sans espace, affiché dans le frontend
-- et émis dans le claim roles (les spécialisations n'ont pas de code)
ALTER TABLE app_role ADD COLUMN IF NOT EXISTS code varchar(50);

UPDATE app_role r SET code = c.code
FROM (VALUES
  ('R20', 'PUMA_ADMIN'),
  ('R21', 'USER_MANAGER'),
  ('R22', 'USER_VIEWER'),
  ('R23', 'CATALOGUE_OWNER'),
  ('R10', 'PARTNER_ADMIN'),
  ('R11', 'TEMPORARY_SELLER'),
  ('R12', 'POINT_OF_SALE_MANAGER'),
  ('R13', 'SELLER'),
  ('R14', 'SALES_MANAGER'),
  ('R15', 'FINANCING_ADVISOR'),
  ('R16', 'FINANCING_SUPERVISOR')
) AS c(id, code)
WHERE r.id = c.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_role_code ON app_role (code) WHERE code IS NOT NULL;

-- Index utiles aux vues et au PDP
CREATE INDEX IF NOT EXISTS idx_node_parent_parent ON node_parent (parent_id);
CREATE INDEX IF NOT EXISTS idx_node_parent_node   ON node_parent (node_id);
CREATE INDEX IF NOT EXISTS idx_assignment_user    ON assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_app_role_parent    ON app_role (parent_role_id);

-- Vues : héritage descendant, rôle global, application disponible sur le noeud
CREATE VIEW puma_user_node_roles AS
WITH RECURSIVE scope AS (
    SELECT a.user_id, a.role_id, a.node_id
    FROM assignment a
  UNION
    SELECT s.user_id, s.role_id, np.node_id
    FROM scope s
    JOIN node_parent np ON np.parent_id = s.node_id
)
SELECT DISTINCT u.uid, s.node_id,
       g.id   AS role_id,
       g.application_id,
       g.code AS role_code
FROM scope s
JOIN puma_user u         ON u.id = s.user_id
JOIN app_role r          ON r.id = s.role_id
JOIN app_role g          ON g.id = COALESCE(r.parent_role_id, r.id)
JOIN node_application na ON na.node_id = s.node_id
                        AND na.application_id = r.application_id
WHERE u.status = 'ACTIVE';

CREATE VIEW partner_user_node_roles AS
SELECT v.uid, v.node_id, v.role_id, r.application_id
FROM puma_user_node_roles v
JOIN app_role r ON r.id = v.role_id;

CREATE VIEW partner_user_node_permissions AS
SELECT DISTINCT v.uid, v.node_id, v.application_id, p.code AS permission_code
FROM partner_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id;

-- Contrôle de non-régression : mêmes lignes qu'avant la migration
DO $$
DECLARE
  diff_roles int;
  diff_perms int;
BEGIN
  SELECT count(*) INTO diff_roles FROM (
    (SELECT uid, node_id, role_id FROM snap_roles
     EXCEPT SELECT uid, node_id, role_id FROM puma_user_node_roles)
    UNION ALL
    (SELECT uid, node_id, role_id FROM puma_user_node_roles
     EXCEPT SELECT uid, node_id, role_id FROM snap_roles)) d;

  SELECT count(*) INTO diff_perms FROM (
    (SELECT * FROM snap_perms
     EXCEPT SELECT uid, node_id, application_id, permission_code FROM partner_user_node_permissions)
    UNION ALL
    (SELECT uid, node_id, application_id, permission_code FROM partner_user_node_permissions
     EXCEPT SELECT * FROM snap_perms)) d;

  IF diff_roles > 0 OR diff_perms > 0 THEN
    RAISE EXCEPTION 'Migration annulee : % ecarts sur puma_user_node_roles, % sur partner_user_node_permissions',
      diff_roles, diff_perms;
  END IF;
  RAISE NOTICE 'Controle OK : vues identiques avant et apres migration';
END $$;

COMMIT;

















# PUMA : plan de travail pour la démo

Version d'octobre 2026. Remplace le document du 30/09 (PUMA-migration-backend-pdp.md).

Ordre d'exécution : étapes 1 à 6, dans l'ordre. Ne passe pas à l'étape suivante tant que les tests de l'étape en cours ne sont pas verts.

Tous les scripts SQL ont été exécutés sur une base PostgreSQL 16 reconstituée à partir du modèle du POC : depuis les deux états possibles de ta base (avec ou sans la migration du 30/09), sur une base neuve, et avec les requêtes PDP sur les scénarios de démo. Les deux chemins de migration et la base neuve donnent exactement le même résultat.

## 0. Notes de Nicolas : ce qui est traité et où

| Note | Traitement | Étape |
|---|---|---|
| Rataweb est l'application métier, le POC c'est PUMA | Titres et diagrammes : PUMA (front + back) d'un côté, Rataweb comme application cliente de démo | 6 |
| Supprimer le consentement après l'authentification | Option sur les clients OAuth | 2.1 |
| Masquer le header du frontend | Frontend PUMA | 4 |
| Retirer isMemberOf du premier token | Contrat de l'ATM | 2.2 |
| Pas d'Access Restricted pendant la démo | Durée de vie des tokens | 2.3 |
| Access token en sessionStorage | Rien pour le POC (Service Worker plus tard) | 7 |
| Le token du token exchange ne doit pas remonter dans la SPA | Fait : il reste dans le backend (modèle BFF) | 3.3 |
| Choix du contexte dans une page PingFederate | Phase 2, voir l'analyse | 2.6 |
| Pas de rôles spécialisés visibles (MANAGER-JLR), seulement des rôles globaux | Déjà le cas : le token et l'IHM ne montrent que des rôles globaux | 2.4 |
| Libellés en un mot sans espace | Colonne code sur app_role, émise dans le token et affichée | 1, 2.4, 4 |
| Uniquement les UUID des utilisateurs dans PostgreSQL | puma_user ne garde que l'entryUUID PingDirectory, plus aucune donnée d'identité | 1, 2.5 |

Une remarque sur l'orthographe : en anglais c'est SUPERVISOR (et non SUPERVISER). Le code proposé est donc FINANCING_SUPERVISOR.

---

## 1. Base de données

### 1.1 Cible

| Table | Contenu |
|---|---|
| puma_user | id, uid (entryUUID PingDirectory), status (accès PUMA), created_at, created_by. Plus d'email ni de nom. |
| assignment | id, user_id (clé étrangère, suppression en cascade), role_id, node_id, created_at, created_by |
| app_role | + colonne code (un mot, sans espace) pour les rôles globaux, vide pour les spécialisations |
| role_permission | inchangée (les colonnes de décision du 30/09 sont retirées, le workflow catalogue est reporté) |
| puma_user_node_roles | + colonne role_code (code du rôle global) |

La table puma_user reste, sans aucune donnée d'identité : elle sert à l'intégrité des affectations, à la suspension de l'accès PUMA et à la réconciliation avec l'annuaire.

### 1.2 Quel est l'état de ta base ?

```sql
SELECT to_regclass('puma_user') AS table_puma_user,
       (SELECT count(*) FROM information_schema.columns
        WHERE table_name = 'puma_user' AND column_name = 'email') AS colonne_email;
```

| Résultat | Cas | Script |
|---|---|---|
| puma_user présente, colonne_email = 1 | A : la migration du 30/09 n'a pas été lancée | puma-migration-A.sql |
| puma_user vide (NULL) | B : la migration du 30/09 a été lancée | puma-migration-B.sql |

### 1.3 Lancer la migration

1. Arrête les backends PUMA et Rataweb.
2. Sauvegarde : `docker exec -t <conteneur_postgres> pg_dump -U <user> -d postgres > puma-avant-migration.sql`
3. Exécute le script de ton cas dans pgAdmin, d'un bloc.

Les deux scripts photographient le contenu des vues avant migration, les recréent, puis comparent ligne à ligne. Au moindre écart, ils s'arrêtent avec "Migration annulee" et rien n'est modifié. Si une erreur apparaît : exécute `ROLLBACK;` et envoie-moi le message.

Le script B refuse aussi de tourner s'il trouve une affectation suspendue individuellement (cette notion disparaît).

Résultat attendu : `Controle OK : vues identiques avant et apres migration`, puis `COMMIT`.

Les deux scripts sont en annexe et livrés à part.

### 1.4 Vérifications

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'puma_user' ORDER BY ordinal_position;
-- attendu : id, uid, status, created_at, created_by

SELECT id, code, name FROM app_role WHERE node_id IS NULL ORDER BY id;
-- attendu : un code pour chaque rôle global

SELECT uid, node_id, role_id, role_code FROM puma_user_node_roles
WHERE node_id = '2672756';
-- attendu : thomas.martin, 2672756, R13, SELLER
```

Si un rôle global n'a pas de code (par exemple un ancien rôle hors jeu de données), donne-lui un code ou supprime-le s'il ne sert plus.

### 1.5 schema.sql

Remplace les blocs `CREATE TABLE IF NOT EXISTS puma_user`, `CREATE TABLE IF NOT EXISTS assignment` et les trois `CREATE OR REPLACE VIEW` par le bloc ci-dessous, placé après les tables app_role, node, node_parent, node_application, permission et role_permission. Retire aussi tout ce qui concerne decision_status s'il y en a.

```sql
-- ---------------------------------------------------------------------
-- Utilisateurs PUMA : aucune donnée d'identité (elles sont dans l'IAM)
-- uid = entryUUID PingDirectory (claim sub du token)
-- status = accès à PUMA, distinct du statut du compte dans l'annuaire
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS puma_user (
  id         bigserial    PRIMARY KEY,
  uid        varchar(100) NOT NULL UNIQUE,
  status     varchar(20)  NOT NULL DEFAULT 'ACTIVE',
  created_at timestamptz  NOT NULL DEFAULT now(),
  created_by varchar(100)
);

CREATE TABLE IF NOT EXISTS assignment (
  id         bigserial    PRIMARY KEY,
  user_id    bigint       NOT NULL REFERENCES puma_user(id) ON DELETE CASCADE,
  role_id    varchar(80)  NOT NULL REFERENCES app_role(id),
  node_id    varchar(20)  NOT NULL REFERENCES node(id),
  created_at timestamptz  NOT NULL DEFAULT now(),
  created_by varchar(100),
  CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id)
);

-- Code des rôles globaux (un mot, sans espace)
ALTER TABLE app_role ADD COLUMN IF NOT EXISTS code varchar(50);
CREATE UNIQUE INDEX IF NOT EXISTS uq_app_role_code ON app_role (code) WHERE code IS NOT NULL;

-- Index
CREATE INDEX IF NOT EXISTS idx_node_parent_parent ON node_parent (parent_id);
CREATE INDEX IF NOT EXISTS idx_node_parent_node   ON node_parent (node_id);
CREATE INDEX IF NOT EXISTS idx_assignment_user    ON assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_app_role_parent    ON app_role (parent_role_id);

-- Vues : héritage descendant, rôle global, application disponible sur le noeud
CREATE OR REPLACE VIEW puma_user_node_roles AS
WITH RECURSIVE scope AS (
    SELECT a.user_id, a.role_id, a.node_id
    FROM assignment a
  UNION
    SELECT s.user_id, s.role_id, np.node_id
    FROM scope s
    JOIN node_parent np ON np.parent_id = s.node_id
)
SELECT DISTINCT u.uid, s.node_id,
       g.id   AS role_id,
       g.application_id,
       g.code AS role_code
FROM scope s
JOIN puma_user u         ON u.id = s.user_id
JOIN app_role r          ON r.id = s.role_id
JOIN app_role g          ON g.id = COALESCE(r.parent_role_id, r.id)
JOIN node_application na ON na.node_id = s.node_id
                        AND na.application_id = r.application_id
WHERE u.status = 'ACTIVE';

CREATE OR REPLACE VIEW partner_user_node_roles AS
SELECT v.uid, v.node_id, v.role_id, r.application_id
FROM puma_user_node_roles v
JOIN app_role r ON r.id = v.role_id;

CREATE OR REPLACE VIEW partner_user_node_permissions AS
SELECT DISTINCT v.uid, v.node_id, v.application_id, p.code AS permission_code
FROM partner_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id;
```

Ce bloc est rejouable à chaque démarrage (testé deux fois de suite sur base neuve et sur les bases migrées). Il ne contient aucun bloc `DO $$`, que le lanceur SQL de Spring découperait mal.

### 1.6 data.sql et jeu de données

Dans data.sql, retire toute mention d'email ou de display_name dans les insertions de puma_user.

Le nouveau `puma-dataset.sql` crée thomas.martin par son entryUUID. Avant de l'exécuter sur une base neuve, remplace `REMPLACER_UUID_THOMAS` (trois occurrences, plus une dans un message d'erreur) par son entryUUID (étape 2.5). S'il n'est pas remplacé, le script s'arrête avec un message explicite à la section 7 : les sections précédentes étant idempotentes, il suffit de corriger et de relancer.

Tu n'as pas besoin de rejouer le jeu de données sur ta base actuelle : la migration conserve les données.

### 1.7 Non-régression

PingFederate et PingAuthorize doivent fonctionner sans modification.

Token exchange avec un token de login de thomas.martin (pris dans le sessionStorage juste après le login) :

```bash
for NODE in 9200005 2700010 2700015; do
  echo "--- $NODE"
  curl -sk -u puma-backend:SECRET_PUMA https://localhost:9031/as/token.oauth2 \
    -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
    -d subject_token=$TOKEN \
    -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
    -d node=$NODE
  echo
done
```

Attendu : un token pour 9200005 et 2700010 (mêmes rôles qu'avant), context_not_allowed pour 2700015. Puis les deux tests canCreateUser habituels : PERMIT sur 2602700, DENY sur 2700015.

---

## 2. PingFederate

### 2.1 Supprimer le consentement

Applications > OAuth > Clients, pour puma-portal et rataweb-portal : coche **Bypass Approval Page**, puis Save.

Test : déconnexion, nouveau login, la page de consentement ne doit plus apparaître.

### 2.2 Retirer isMemberOf du token de login

Applications > OAuth > Access Token Management > JWTAccessToken > Attribute Contract : supprime isMemberOf, puis Save. PingFederate signale les mappings qui l'utilisaient : retire-le aussi de ces mappings.

Avant, vérifie qu'aucun code ne le lit : `grep -rn "isMemberOf" ` dans les quatre projets (backends et frontends PUMA et Rataweb).

Test : décode un token de login, isMemberOf ne doit plus y être.

### 2.3 Durée des tokens pour la démo

Dans la même instance JWTAccessToken, onglet Instance Configuration : passe Token Lifetime à 60 minutes. Le token de login et le token de contexte en héritent ; le cache du backend suit l'expiration du token de contexte.

Si un Access Restricted réapparaît avant 60 minutes, il ne vient pas de la durée du token : note l'heure et l'écran, on cherchera ailleurs (garde du frontend, session PingFederate).

### 2.4 Codes de rôles dans le token

Dans la politique du Token Exchange (puma-context-policy), source d'attributs JDBC pumaRoles :

1. ajoute la colonne role_code aux colonnes lues ;
2. dans le mapping du contrat, alimente roles avec role_code au lieu de role_id ;
3. ne touche pas aux Issuance Criteria (elles testent role_id, toujours présent).

Fais la même chose dans la politique utilisée par rataweb-backend.

Attention : Rataweb compare aujourd'hui les rôles du token à R15 et R16. Après ce changement, ses contrôles échouent jusqu'à l'étape 6. Soit tu fais 2.4 avec l'étape 6, soit tu remplaces en attendant R15 et R16 par FINANCING_ADVISOR et FINANCING_SUPERVISOR dans son ActionController.

Test : le token exchange sur 9200005 renvoie des rôles lisibles (PUMA_ADMIN, USER_MANAGER...).

### 2.5 sub = entryUUID PingDirectory (avec la bascule de la base)

Cette étape change l'identifiant de l'utilisateur partout. PingFederate et la base doivent basculer ensemble, sinon plus aucun contexte n'est accordé. Fais-la d'une traite.

1. Récupère les entryUUID :

```bash
docker exec -it <conteneur_pingdirectory> ldapsearch -h localhost -p 1636 -Z -X \
  -D "cn=administrator" -w <mot_de_passe> -b "<base_dn>" \
  "(|(uid=thomas.martin)(uid=max.walker))" uid entryUUID
```

entryUUID est un attribut opérationnel : il n'apparaît que si on le demande explicitement, comme ici.

2. Dans PingFederate, mapping du token de login (Access Token Mapping, contexte de la politique d'authentification de puma-portal et rataweb-portal) :
   - ajoute une source d'attributs LDAP sur le data store PingDirectory, filtre `(uid=${subject})` (adapte au nom de l'attribut d'identifiant de ton contrat), attribut entryUUID à saisir à la main ;
   - alimente sub (ou l'attribut choisi comme Subject Attribute Name de l'ATM) avec entryUUID ;
   - ajoute un claim name alimenté par displayName ou cn, pour l'affichage dans les frontends.

Le token de contexte reprend le sub du token de login (tepp.subject) : rien à changer dans la politique du Token Exchange, et le filtre JDBC `uid = '${tepp.subject}'` reçoit désormais l'UUID.

3. Dans pgAdmin, remplace les deux valeurs `REMPLACER_UUID_...` de `puma-migration-uuid.sql` par les entryUUID obtenus, puis exécute-le. Il refuse de tourner si une valeur manque ou n'a pas le format d'un UUID, et affiche les éventuels utilisateurs restés sans UUID.

4. Tests : nouveau login, le sub du token est l'UUID ; rejoue les tests de 1.7 et canCreateUser.

### 2.6 Choix du contexte dans PingFederate : analyse

La demande de Nicolas a deux parties qu'il faut séparer.

**Le token du token exchange ne doit pas arriver dans le navigateur.** C'est traité pour la démo par l'étape 3.3 : le backend garde le token de contexte, le navigateur n'envoie que le noeud choisi.

**La page de choix du contexte dans PingFederate.** C'est l'architecture cible la plus propre (un seul token, déjà contextualisé, sans token exchange), mais ce n'est pas une configuration simple. Deux pistes sans écrire de plugin Java, à valider sur ta version de PingFederate :

1. Chaîner après le formulaire de login un adaptateur Reference ID (Agentless Integration Kit). PingFederate redirige vers une petite page hébergée par PUMA, qui récupère l'utilisateur authentifié, lui fait choisir le noeud, renvoie ce choix à PingFederate, qui l'émet dans le token. C'est la piste la plus directe.
2. Passer le noeud dans la requête d'autorisation via RAR (authorization_details), après un premier login. Plus élégant sur le papier, mais le noeud doit être validé côté serveur et le changement de contexte demande un nouvel aller-retour d'autorisation.

Dans les deux cas, changer de contexte impose de repasser par PingFederate (sans ressaisie du mot de passe grâce à la session SSO). Charge estimée pour la piste 1 : deux à trois jours, configuration, page et tests compris. À proposer comme phase 2, après la démo.

---

## 3. Backend PUMA

### 3.1 Entité PumaUser

Dans `entity/PumaUser.java` : supprime les champs email et displayName (et leurs getters et setters), ajoute :

```java
@Column(name = "created_by", length = 100)
private String createdBy;
```

Retire ensuite tout ce qui les utilise :

```bash
grep -rn "getEmail\|setEmail\|DisplayName\|displayName\|email" src/main/java/
```

Dans `entity/AppRole.java`, ajoute :

```java
@Column(name = "code", length = 50)
private String code;
```

avec son getter, et expose-le dans le DTO qui alimente la liste des rôles du frontend.

### 3.2 Création d'un utilisateur : retrouver son entryUUID dans l'annuaire

Le manager saisit un identifiant ou un email. Le backend retrouve l'entryUUID dans PingDirectory, crée l'utilisateur PUMA s'il n'existe pas, puis ses affectations. Pas de nouvelle dépendance : JNDI fait partie du JDK.

`application.yml` :

```yaml
puma:
  ldap:
    url: ldap://localhost:1389
    bind-dn: cn=administrator
    bind-password: <mot_de_passe>
    base-dn: <base_dn>
```

Le port LDAP sans TLS (1389) évite le problème du certificat auto-signé pour le POC. À passer en LDAPS hors POC.

`service/DirectoryService.java` :

```java
package com.poc.banking.service;

import java.util.Hashtable;
import java.util.Optional;
import javax.naming.Context;
import javax.naming.NamingEnumeration;
import javax.naming.NamingException;
import javax.naming.directory.Attribute;
import javax.naming.directory.InitialDirContext;
import javax.naming.directory.SearchControls;
import javax.naming.directory.SearchResult;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

@Service
public class DirectoryService {

    private final String url;
    private final String bindDn;
    private final String bindPassword;
    private final String baseDn;

    public DirectoryService(@Value("${puma.ldap.url}") String url,
                            @Value("${puma.ldap.bind-dn}") String bindDn,
                            @Value("${puma.ldap.bind-password}") String bindPassword,
                            @Value("${puma.ldap.base-dn}") String baseDn) {
        this.url = url;
        this.bindDn = bindDn;
        this.bindPassword = bindPassword;
        this.baseDn = baseDn;
    }

    /** entryUUID du compte dont l'uid ou le mail correspond, vide si aucun. */
    public Optional<String> findEntryUuid(String login) {
        Hashtable<String, String> env = new Hashtable<>();
        env.put(Context.INITIAL_CONTEXT_FACTORY, "com.sun.jndi.ldap.LdapCtxFactory");
        env.put(Context.PROVIDER_URL, url);
        env.put(Context.SECURITY_AUTHENTICATION, "simple");
        env.put(Context.SECURITY_PRINCIPAL, bindDn);
        env.put(Context.SECURITY_CREDENTIALS, bindPassword);

        SearchControls controls = new SearchControls();
        controls.setSearchScope(SearchControls.SUBTREE_SCOPE);
        controls.setReturningAttributes(new String[] {"entryUUID"});
        controls.setCountLimit(2);

        InitialDirContext ctx = null;
        try {
            ctx = new InitialDirContext(env);
            // {0} est échappé par JNDI : pas d'injection LDAP possible
            NamingEnumeration<SearchResult> results = ctx.search(
                    baseDn, "(|(uid={0})(mail={0}))", new Object[] {login.trim()}, controls);
            if (!results.hasMore()) {
                return Optional.empty();
            }
            SearchResult first = results.next();
            if (results.hasMore()) {
                throw new IllegalStateException("Plusieurs comptes correspondent à " + login);
            }
            Attribute uuid = first.getAttributes().get("entryUUID");
            return uuid == null ? Optional.empty() : Optional.of(uuid.get().toString());
        } catch (NamingException e) {
            throw new IllegalStateException("Annuaire indisponible", e);
        } finally {
            if (ctx != null) {
                try { ctx.close(); } catch (NamingException ignored) { }
            }
        }
    }
}
```

`service/UserProvisioningService.java` :

```java
package com.poc.banking.service;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

@Service
public class UserProvisioningService {

    private final JdbcTemplate jdbc;
    private final DirectoryService directory;

    public UserProvisioningService(JdbcTemplate jdbc, DirectoryService directory) {
        this.jdbc = jdbc;
        this.directory = directory;
    }

    /**
     * Inscrit dans PUMA un compte existant de l'annuaire et lui affecte des
     * rôles globaux sur un noeud. Retourne l'entryUUID.
     */
    @Transactional
    public String onboard(String login, List<String> roleIds, String nodeId, String createdBy) {
        String uid = directory.findEntryUuid(login)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "Compte inconnu dans l'annuaire"));

        jdbc.update("""
                INSERT INTO puma_user (uid, created_by) VALUES (?, ?)
                ON CONFLICT (uid) DO NOTHING
                """, uid, createdBy);
        Long userId = jdbc.queryForObject(
                "SELECT id FROM puma_user WHERE uid = ?", Long.class, uid);

        for (String roleId : roleIds) {
            // seuls les rôles globaux sont affectables
            jdbc.update("""
                    INSERT INTO assignment (user_id, role_id, node_id, created_by)
                    SELECT ?, r.id, ?, ?
                    FROM app_role r
                    WHERE r.id = ? AND r.node_id IS NULL
                    ON CONFLICT (user_id, role_id, node_id) DO NOTHING
                    """, userId, nodeId, createdBy, roleId);
        }
        return uid;
    }
}
```

Dans le contrôleur de POST /api/users, après le contrôle PDP user.create qui ne change pas, remplace l'appel à `UserDatabaseService.save()` par `userProvisioningService.onboard(request.login(), request.roleIds(), request.nodeId(), jwt.getSubject())`. createdBy vient toujours du token vérifié, jamais du corps de la requête. Adapte les noms de champs à ton DTO, et retire de celui-ci email et displayName.

Prérequis pour la démo : le compte à inscrire doit exister dans PingDirectory.

### 3.3 Le token de contexte reste côté serveur

Le navigateur garde son token de login et envoie le noeud choisi dans l'en-tête `X-Context-Node`. Le backend fait le token exchange, garde le token de contexte en cache et l'utilise lui-même. Si le noeud n'est pas autorisé, PingFederate refuse et le backend répond 403 comme aujourd'hui.

`service/ContextTokenStore.java` :

```java
package com.poc.banking.service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.stereotype.Service;
import com.poc.banking.exception.ContextForbiddenException;

@Service
public class ContextTokenStore {

    private record Entry(String token, Instant expiresAt) {}

    private final Map<String, Entry> cache = new ConcurrentHashMap<>();
    private final PingFederateService pingFederateService;
    private final JwtDecoder jwtDecoder;

    public ContextTokenStore(PingFederateService pingFederateService, JwtDecoder jwtDecoder) {
        this.pingFederateService = pingFederateService;
        this.jwtDecoder = jwtDecoder;
    }

    /** Token de contexte pour ce login et ce noeud, émis par PingFederate. */
    public Jwt resolve(Jwt loginJwt, String nodeId) {
        String key = key(loginJwt, nodeId);
        Entry entry = cache.get(key);
        if (entry != null && entry.expiresAt().isAfter(Instant.now().plusSeconds(30))) {
            return jwtDecoder.decode(entry.token());
        }

        String token = pingFederateService.exchangeToken(loginJwt.getTokenValue(), nodeId);
        Jwt context = jwtDecoder.decode(token);   // signature et expiration vérifiées

        if (!nodeId.equals(context.getClaimAsString("node"))) {
            throw new ContextForbiddenException();
        }

        Instant expiresAt = context.getExpiresAt() != null
                ? context.getExpiresAt() : Instant.now().plusSeconds(60);
        cache.values().removeIf(e -> e.expiresAt().isBefore(Instant.now()));
        cache.put(key, new Entry(token, expiresAt));
        return context;
    }

    /** Clé liée au token de login : un nouveau login donne un nouveau contexte. */
    private static String key(Jwt loginJwt, String nodeId) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest(loginJwt.getTokenValue().getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hash) + "|" + nodeId;
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
```

Hypothèse : `PingFederateService.exchangeToken(String subjectToken, String nodeId)` renvoie l'access_token et lève `ContextForbiddenException` en cas de refus. Si ta signature diffère, adapte seulement l'appel.

`ContextController.select` ne renvoie plus le token :

```java
public record SelectedContextDto(String node, List<String> roles) {}

@PostMapping("/select")
public SelectedContextDto select(@AuthenticationPrincipal Jwt jwt,
                                 @Valid @RequestBody SelectContextRequest request) {
    Jwt context = contextTokenStore.resolve(jwt, request.nodeId());
    List<String> roles = context.getClaimAsStringList("roles");
    return new SelectedContextDto(context.getClaimAsString("node"),
            roles != null ? roles : List.of());
}
```

Dans chaque endpoint qui a besoin du contexte (POST /api/users, POST /api/decisions, GET /api/hierarchy/subtree, GET /api/me/permissions, GET /api/me/tree) :

```java
@PostMapping("/users")
public ResponseEntity<?> create(@AuthenticationPrincipal Jwt jwt,
        @RequestHeader("X-Context-Node") @Pattern(regexp = "^[A-Za-z0-9_-]{1,20}$") String contextNode,
        @Valid @RequestBody CreateUserRequest request) {
    Jwt context = contextTokenStore.resolve(jwt, contextNode);
    // suite inchangée, en utilisant "context" là où le code utilisait "jwt"
    // (JwtSubject.isManager(context), claim node, claim roles)
}
```

Le `@Pattern` sur un en-tête exige `@Validated` sur la classe du contrôleur.

Dans `CorsFilter`, autorise le nouvel en-tête, sinon le navigateur bloquera les appels :

```java
response.setHeader("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Context-Node");
```

### 3.4 Signature des tokens

Vérifie que le bean `JwtDecoder` actif est bien `NimbusJwtDecoder.withSecretKey(...)` avec la clé de poc-key, puis teste avec un token dont tu modifies un caractère au milieu du payload :

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN_MODIFIE" \
  http://localhost:8081/api/contexts/nodes
```

Attendu : 401.

### 3.5 Tests backend

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8081/api/contexts/nodes

curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"nodeId":"2700010"}' http://localhost:8081/api/contexts/select

curl -s -o /dev/null -w "%{http_code}\n" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"nodeId":"2700015"}' \
  http://localhost:8081/api/contexts/select

curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOKEN" \
  http://localhost:8081/api/me/permissions
```

Attendus : la liste des noeuds ; `{"node":"2700010","roles":["PUMA_ADMIN",...]}` sans token ; 403 ; 400 (en-tête manquant).

---

## 4. Frontend PUMA

1. **Header** : masque le composant d'en-tête (le plus simple : le retirer du template de l'AppComponent).
2. **Nom affiché** : lis le claim name du token de login au lieu de l'identifiant (le sub est désormais un UUID).
3. **Sélection des rôles** : affiche le code (FINANCING_SUPERVISOR) au lieu du libellé.
4. **Contexte** : dans `AuthService` :

```typescript
getContextNode(): string | null {
  return sessionStorage.getItem('context_node');
}

setContextNode(nodeId: string): void {
  sessionStorage.setItem('context_node', nodeId);
}

apiHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Authorization: 'Bearer ' + this.getToken()
  };
  const node = this.getContextNode();
  if (node) {
    headers['X-Context-Node'] = node;
  }
  return headers;
}
```

Et à la déconnexion : `sessionStorage.removeItem('context_node');`.

Dans `ContextV2Service` : `select()` appelle `this.auth.setContextNode(nodeId)` au lieu de stocker un token, et `hasContext()` devient `return !!this.auth.getContextNode();`.

Dans tous les appels au backend : `headers: this.auth.apiHeaders()`. Pour les trouver : `grep -rn "Authorization: 'Bearer '" src/app/`.

5. **Formulaire de création** : un seul champ identifiant ou email (plus de nom ni d'email séparés), la sélection des rôles et le noeud.

Avant le premier test, vide le sessionStorage du navigateur. Ensuite, onglet Application des outils de développement : il ne doit contenir que access_token (le token de login) et context_node.

---
## 5. PingAuthorize : règle générique en trois attributs

### 5.1 Principe

Chaque attribut répond à une question simple, sa valeur apparaît dans les traces de décision, et la combinaison qui donne PERMIT ou DENY est écrite dans le PDP, lisible sans lire le SQL. Coût : trois requêtes de quelques millisecondes sur des tables indexées.

| Attribut | Question |
|---|---|
| targetInContextDB | Le noeud cible est-il le noeud du contexte ou l'un de ses descendants ? |
| grantingRolesDB | Combien de rôles globaux de l'utilisateur, valables sur le noeud cible et pour l'application, accordent la permission ? |
| effectiveRolesDB | Parmi eux, combien l'accordent encore après les retraits des spécialisations qui s'appliquent au noeud cible ou à ses ancêtres ? |

La troisième question est nécessaire : un utilisateur qui a deux rôles accordant la même permission, dont un seul est restreint sur le noeud, doit garder la permission.

La vue puma_user_node_roles fait déjà trois contrôles : utilisateur actif dans PUMA, héritage descendant, application disponible sur le noeud. Ils n'ont pas à être répétés.

### 5.2 Attributs de requête

Toujours fournis par le backend (le PEP), jamais par le navigateur :

| Attribut | Source |
|---|---|
| uid | sub du token de login vérifié (entryUUID) |
| contextNode | claim node du token de contexte gardé côté serveur |
| targetNode | noeud visé par l'action |
| application | application qui appelle : A0 pour PUMA, A3 pour Rataweb |
| permission | code de la permission : user.create, quote.create... |

Réutilise les attributs déjà créés pour canCreateUser et crée ceux qui manquent. Dans les requêtes ci-dessous, remplace `{{uid}}`, `{{contextNode}}`, etc. par la syntaxe de paramètre de ton service canCreateUser.

### 5.3 Les trois services JDBC

Même data store que canCreateUser, même extraction : JSON Path `$[0].total`, type Number.

**targetInContext**

```sql
WITH RECURSIVE down AS (
    SELECT CAST({{contextNode}} AS varchar) AS node_id
  UNION
    SELECT CAST(np.node_id AS varchar)
    FROM node_parent np
    JOIN down d ON np.parent_id = d.node_id
)
SELECT COUNT(*) AS total FROM down WHERE node_id = {{targetNode}}
```

**grantingRoles**

```sql
SELECT COUNT(DISTINCT v.role_id) AS total
FROM puma_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id
WHERE v.uid = {{uid}}
  AND v.node_id = {{targetNode}}
  AND v.application_id = {{application}}
  AND p.code = {{permission}}
```

**effectiveRoles**

```sql
WITH RECURSIVE
granting AS (
    SELECT DISTINCT v.role_id
    FROM puma_user_node_roles v
    JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
    JOIN permission p       ON p.id = rp.permission_id
    WHERE v.uid = {{uid}}
      AND v.node_id = {{targetNode}}
      AND v.application_id = {{application}}
      AND p.code = {{permission}}
),
ancestors AS (
    SELECT CAST({{targetNode}} AS varchar) AS node_id
  UNION
    SELECT CAST(np.parent_id AS varchar)
    FROM node_parent np
    JOIN ancestors a ON np.node_id = a.node_id
),
specs AS (
    SELECT r.id, r.node_id, g.role_id AS root_role
    FROM app_role r
    JOIN granting g ON r.parent_role_id = g.role_id
  UNION
    SELECT r.id, r.node_id, s.root_role
    FROM app_role r
    JOIN specs s ON r.parent_role_id = s.id
)
SELECT COUNT(*) AS total
FROM granting g
WHERE NOT EXISTS (
    SELECT 1
    FROM specs s
    JOIN role_permission rp ON rp.role_id = s.id
                           AND rp.granted = false
    JOIN permission p       ON p.id = rp.permission_id
    WHERE s.root_role = g.role_id
      AND s.node_id IN (SELECT node_id FROM ancestors)
      AND p.code = {{permission}}
)
```

Les `CAST(... AS varchar)` dans les parties récursives sont nécessaires : sans eux, PostgreSQL refuse la récursion quand les deux côtés n'ont pas exactement le même type.

### 5.4 La politique

Policy "Partner permission", ciblée sur le service et l'action que les backends enverront (par exemple service `PUMA.Authorization`, action `check`), algorithme "A single deny will override any permits".

| Règle | Effet | Condition |
|---|---|---|
| Target outside context | Deny | targetInContextDB = 0 |
| Permission removed by specialization | Deny | grantingRolesDB > 0 et effectiveRolesDB = 0 |
| Permission effective | Permit | effectiveRolesDB > 0 |

Si aucun rôle n'accorde la permission, aucune règle ne s'applique et la politique racine (DenyUnlessPermit) refuse.

canCreateUser reste en place tant que la nouvelle politique n'est pas validée. En mode embedded : exporter le .SDP et redéployer après chaque modification.

### 5.5 Tester d'abord dans pgAdmin

Remplace `<UUID de thomas.martin>` par son entryUUID (ou par thomas.martin si l'étape 2.5 n'est pas encore faite) :

```sql
-- Q1 targetInContext
WITH RECURSIVE down AS (
    SELECT CAST('2672756' AS varchar) AS node_id
  UNION
    SELECT CAST(np.node_id AS varchar)
    FROM node_parent np
    JOIN down d ON np.parent_id = d.node_id
)
SELECT 'Q1' q, COUNT(*) AS total FROM down WHERE node_id = '2672756';

-- Q2 grantingRoles
SELECT 'Q2' q, COUNT(DISTINCT v.role_id) AS total
FROM puma_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id
WHERE v.uid = '<UUID de thomas.martin>'
  AND v.node_id = '2672756'
  AND v.application_id = 'A2'
  AND p.code = 'stocklist.download';

-- Q3 effectiveRoles
WITH RECURSIVE
granting AS (
    SELECT DISTINCT v.role_id
    FROM puma_user_node_roles v
    JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
    JOIN permission p       ON p.id = rp.permission_id
    WHERE v.uid = '<UUID de thomas.martin>'
      AND v.node_id = '2672756'
      AND v.application_id = 'A2'
      AND p.code = 'stocklist.download'
),
ancestors AS (
    SELECT CAST('2672756' AS varchar) AS node_id
  UNION
    SELECT CAST(np.parent_id AS varchar)
    FROM node_parent np
    JOIN ancestors a ON np.node_id = a.node_id
),
specs AS (
    SELECT r.id, r.node_id, g.role_id AS root_role
    FROM app_role r
    JOIN granting g ON r.parent_role_id = g.role_id
  UNION
    SELECT r.id, r.node_id, s.root_role
    FROM app_role r
    JOIN specs s ON r.parent_role_id = s.id
)
SELECT 'Q3' q, COUNT(*) AS total
FROM granting g
WHERE NOT EXISTS (
    SELECT 1
    FROM specs s
    JOIN role_permission rp ON rp.role_id = s.id
                           AND rp.granted = false
    JOIN permission p       ON p.id = rp.permission_id
    WHERE s.root_role = g.role_id
      AND s.node_id IN (SELECT node_id FROM ancestors)
      AND p.code = 'stocklist.download'
);
```

Attendu : Q1 = 1, Q2 = 1, Q3 = 0, soit DENY par "Permission removed by specialization".

### 5.6 Scénarios (valeurs obtenues sur la base de test)

| Utilisateur | Contexte | Cible | App | Permission | Q1 | Q2 | Q3 | Décision |
|---|---|---|---|---|---|---|---|---|
| thomas.martin | 9200005 | 2700010 | A0 | user.create | 1 | 2 | 2 | PERMIT |
| thomas.martin | 9200005 | 2700015 | A0 | user.create | 0 | 0 | 0 | DENY (hors contexte) |
| thomas.martin | 2672749 | 2672749 | A2 | stocklist.download | 1 | 1 | 1 | PERMIT |
| thomas.martin | 2672756 | 2672756 | A2 | stocklist.download | 1 | 1 | 0 | DENY (spécialisation) |
| thomas.martin | 2672749 | 2672756 | A2 | stocklist.read | 0 | 1 | 1 | DENY (hors contexte) |
| max.walker | 2700013 | 2700013 | A3 | request.approve | 1 | 1 | 1 | PERMIT |
| compte avec FINANCING_ADVISOR seul | 2700013 | 2700013 | A3 | quote.create | 1 | 1 | 1 | PERMIT |
| compte avec FINANCING_ADVISOR seul | 2700013 | 2700013 | A3 | request.approve | 1 | 0 | 0 | DENY (aucun rôle) |

Le cas de Traunstein reste disponible mais n'a pas à être montré : conformément à la note de Nicolas, la démo ne montre que des rôles globaux.

---

## 6. Rataweb : application cliente de démo

Rataweb est l'application métier pour laquelle le manager PUMA crée des utilisateurs. Elle montre qu'une application tierce délègue entièrement ses décisions à PingFederate et PingAuthorize, sans connaître les rôles.

### 6.1 Backend Rataweb (port 8082)

1. **Token de contexte côté serveur** : copie `ContextTokenStore` de PUMA (3.3), branché sur le `TokenExchangeService` de Rataweb (client rataweb-backend). Même changement sur `ContextController.select`, même en-tête `X-Context-Node`, même ligne dans le filtre CORS (origine localhost:4300).
2. **Décision par permission** : copie `PartnerDecisionService` de PUMA, qui appelle déjà PingAuthorize, et fais-lui envoyer les cinq attributs de 5.2 avec application = A3.
3. **ActionController** : chaque endpoint demande une permission, plus aucune liste de rôles dans le code.

| Action | Permission |
|---|---|
| Consulter un devis | quote.read |
| Créer un devis | quote.create |
| Soumettre une demande | request.submit |
| Approuver une demande | request.approve |

```java
private void require(Jwt login, String contextNode, String permission) {
    Jwt context = contextTokenStore.resolve(login, contextNode);
    String node = context.getClaimAsString("node");
    boolean permitted = decisionService.isPermitted(
            login.getSubject(),   // uid
            node,                 // contextNode
            node,                 // targetNode : l'action porte sur le noeud choisi
            "A3",
            permission);
    if (!permitted) {
        throw new ResponseStatusException(HttpStatus.FORBIDDEN, permission);
    }
}

@PostMapping("/requests/approve")
public ActionResultDto approve(@AuthenticationPrincipal Jwt jwt,
        @RequestHeader("X-Context-Node") String contextNode) {
    require(jwt, contextNode, "request.approve");
    return new ActionResultDto("request.approve", "OK");
}
```

Adapte les chemins et le DTO de retour à tes quatre endpoints existants, et la signature de `isPermitted` à celle de ton PartnerDecisionService.

### 6.2 Frontend Rataweb (port 4300)

Mêmes changements que le frontend PUMA : `X-Context-Node` au lieu du token de contexte, nom affiché depuis le claim name, pas de header. Pour la démo, affiche le résultat de chaque bouton (autorisé, ou refusé avec la permission en cause) : c'est ce que le public doit voir.

### 6.3 Scénario de bout en bout

Prérequis : un compte de démonstration dans PingDirectory, par exemple julia.weber, sans aucune affectation dans PUMA.

1. thomas.martin se connecte à PUMA, choisit Roller 5 (9200005), inscrit julia.weber avec FINANCING_ADVISOR sur le vendor 2700013.
2. julia.weber se connecte à Rataweb, choisit 2700013 : consulter et créer un devis, soumettre une demande sont autorisés ; approuver est refusé.
3. thomas.martin ajoute FINANCING_SUPERVISOR à julia.weber sur 2700013.
4. julia.weber clique de nouveau sur Approuver : c'est autorisé, sans redéploiement ni changement de code, parce que PingAuthorize relit la base à chaque décision.

Ce scénario montre en quelques minutes la délégation (PUMA), le contexte (PingFederate), la décision par permission (PingAuthorize) et l'effet immédiat d'une affectation. Seuls les rôles affichés dans le token de contexte resteront les anciens jusqu'au prochain choix de contexte.

---

## 7. Hors démo (phase 2)

1. **Choix du contexte dans PingFederate** (2.6) : adaptateur Reference ID, deux à trois jours.
2. **Workflow du catalogue** : demandes de modification et validation à quatre yeux, en attente de l'arbitrage sur la spécialisation.
3. **Service Worker** pour le token de login dans le navigateur (note de Nicolas).
4. **Réconciliation avec l'annuaire** : comptes supprimés dans PingDirectory, puma_user à nettoyer.
5. **LDAPS** entre le backend et PingDirectory, et secrets hors de application.yml.
6. **Cache partagé** des tokens de contexte si les backends passent à plusieurs instances.

---

## Annexe A : puma-migration-A.sql (la migration du 30/09 n'a pas été lancée)

```sql
-- =====================================================================
-- PUMA : migration 2026-10 (cas A : la migration du 30/09 n'a PAS été lancée)
-- puma_user garde uid, status, created_at, created_by : plus aucune donnée
-- d'identité (email, nom). Codes de rôles. Vues recréées.
-- A exécuter une seule fois dans pgAdmin, d'un bloc. Transaction unique :
-- au moindre écart, rien n'est modifié.
-- =====================================================================
BEGIN;

-- 0. Photo des vues avant migration
CREATE TEMP TABLE snap_roles ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, role_id FROM puma_user_node_roles;
CREATE TEMP TABLE snap_perms ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, application_id, permission_code FROM partner_user_node_permissions;

-- 1. Les vues sont retirées puis recréées à l'identique (plus role_code)
DROP VIEW partner_user_node_permissions;
DROP VIEW partner_user_node_roles;
DROP VIEW puma_user_node_roles;

-- 2. puma_user : plus de données d'identité
ALTER TABLE puma_user DROP COLUMN email;
ALTER TABLE puma_user DROP COLUMN display_name;
ALTER TABLE puma_user ADD COLUMN IF NOT EXISTS created_by varchar(100);

-- Codes des rôles globaux : un mot, sans espace, affiché dans le frontend
-- et émis dans le claim roles (les spécialisations n'ont pas de code)
ALTER TABLE app_role ADD COLUMN IF NOT EXISTS code varchar(50);

UPDATE app_role r SET code = c.code
FROM (VALUES
  ('R20', 'PUMA_ADMIN'),
  ('R21', 'USER_MANAGER'),
  ('R22', 'USER_VIEWER'),
  ('R23', 'CATALOGUE_OWNER'),
  ('R10', 'PARTNER_ADMIN'),
  ('R11', 'TEMPORARY_SELLER'),
  ('R12', 'POINT_OF_SALE_MANAGER'),
  ('R13', 'SELLER'),
  ('R14', 'SALES_MANAGER'),
  ('R15', 'FINANCING_ADVISOR'),
  ('R16', 'FINANCING_SUPERVISOR')
) AS c(id, code)
WHERE r.id = c.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_role_code ON app_role (code) WHERE code IS NOT NULL;

-- Index utiles aux vues et au PDP
CREATE INDEX IF NOT EXISTS idx_node_parent_parent ON node_parent (parent_id);
CREATE INDEX IF NOT EXISTS idx_node_parent_node   ON node_parent (node_id);
CREATE INDEX IF NOT EXISTS idx_assignment_user    ON assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_app_role_parent    ON app_role (parent_role_id);

-- Vues : héritage descendant, rôle global, application disponible sur le noeud
CREATE VIEW puma_user_node_roles AS
WITH RECURSIVE scope AS (
    SELECT a.user_id, a.role_id, a.node_id
    FROM assignment a
  UNION
    SELECT s.user_id, s.role_id, np.node_id
    FROM scope s
    JOIN node_parent np ON np.parent_id = s.node_id
)
SELECT DISTINCT u.uid, s.node_id,
       g.id   AS role_id,
       g.application_id,
       g.code AS role_code
FROM scope s
JOIN puma_user u         ON u.id = s.user_id
JOIN app_role r          ON r.id = s.role_id
JOIN app_role g          ON g.id = COALESCE(r.parent_role_id, r.id)
JOIN node_application na ON na.node_id = s.node_id
                        AND na.application_id = r.application_id
WHERE u.status = 'ACTIVE';

CREATE VIEW partner_user_node_roles AS
SELECT v.uid, v.node_id, v.role_id, r.application_id
FROM puma_user_node_roles v
JOIN app_role r ON r.id = v.role_id;

CREATE VIEW partner_user_node_permissions AS
SELECT DISTINCT v.uid, v.node_id, v.application_id, p.code AS permission_code
FROM partner_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id;

-- Contrôle de non-régression : mêmes lignes qu'avant la migration
DO $$
DECLARE
  diff_roles int;
  diff_perms int;
BEGIN
  SELECT count(*) INTO diff_roles FROM (
    (SELECT uid, node_id, role_id FROM snap_roles
     EXCEPT SELECT uid, node_id, role_id FROM puma_user_node_roles)
    UNION ALL
    (SELECT uid, node_id, role_id FROM puma_user_node_roles
     EXCEPT SELECT uid, node_id, role_id FROM snap_roles)) d;

  SELECT count(*) INTO diff_perms FROM (
    (SELECT * FROM snap_perms
     EXCEPT SELECT uid, node_id, application_id, permission_code FROM partner_user_node_permissions)
    UNION ALL
    (SELECT uid, node_id, application_id, permission_code FROM partner_user_node_permissions
     EXCEPT SELECT * FROM snap_perms)) d;

  IF diff_roles > 0 OR diff_perms > 0 THEN
    RAISE EXCEPTION 'Migration annulee : % ecarts sur puma_user_node_roles, % sur partner_user_node_permissions',
      diff_roles, diff_perms;
  END IF;
  RAISE NOTICE 'Controle OK : vues identiques avant et apres migration';
END $$;

COMMIT;
```

## Annexe B : puma-migration-B.sql (la migration du 30/09 a été lancée)

```sql
-- =====================================================================
-- PUMA : migration 2026-10 (cas B : la migration du 30/09 a été lancée)
-- Recrée puma_user sous forme réduite (uid, status, created_at, created_by)
-- et revient à assignment.user_id. Retire les colonnes de décision ajoutées
-- le 30/09 (le workflow catalogue est reporté). Codes de rôles. Vues.
-- A exécuter une seule fois dans pgAdmin, d'un bloc. Transaction unique.
-- =====================================================================
BEGIN;

-- 0. Photo des vues avant migration
CREATE TEMP TABLE snap_roles ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, role_id FROM puma_user_node_roles;
CREATE TEMP TABLE snap_perms ON COMMIT DROP AS
  SELECT DISTINCT uid, node_id, application_id, permission_code FROM partner_user_node_permissions;

-- 1. Garde-fou : une affectation suspendue individuellement serait perdue
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM assignment WHERE status <> 'ACTIVE') THEN
    RAISE EXCEPTION 'Migration annulee : des affectations SUSPENDED existent, a traiter avant';
  END IF;
END $$;

DROP VIEW partner_user_node_permissions;
DROP VIEW partner_user_node_roles;
DROP VIEW puma_user_node_roles;

-- 2. puma_user réduite, alimentée par les uid des affectations
CREATE TABLE puma_user (
  id         bigserial    PRIMARY KEY,
  uid        varchar(100) NOT NULL UNIQUE,
  status     varchar(20)  NOT NULL DEFAULT 'ACTIVE',
  created_at timestamptz  NOT NULL DEFAULT now(),
  created_by varchar(100)
);

INSERT INTO puma_user (uid) SELECT DISTINCT uid FROM assignment;

-- 3. assignment revient à user_id
ALTER TABLE assignment ADD COLUMN user_id bigint;
UPDATE assignment a SET user_id = u.id FROM puma_user u WHERE u.uid = a.uid;
ALTER TABLE assignment ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE assignment ADD CONSTRAINT fk_assignment_user
  FOREIGN KEY (user_id) REFERENCES puma_user(id) ON DELETE CASCADE;

ALTER TABLE assignment DROP CONSTRAINT uq_assignment;
DROP INDEX IF EXISTS idx_assignment_uid;
ALTER TABLE assignment DROP COLUMN uid;
ALTER TABLE assignment DROP COLUMN status;
ALTER TABLE assignment ADD CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id);

-- 4. Colonnes de décision du 30/09 retirées
ALTER TABLE role_permission DROP CONSTRAINT IF EXISTS chk_role_permission_decision;
ALTER TABLE role_permission
  DROP COLUMN IF EXISTS decision_status,
  DROP COLUMN IF EXISTS requested_by,
  DROP COLUMN IF EXISTS requested_at,
  DROP COLUMN IF EXISTS decided_by,
  DROP COLUMN IF EXISTS decided_at;

-- Codes des rôles globaux : un mot, sans espace, affiché dans le frontend
-- et émis dans le claim roles (les spécialisations n'ont pas de code)
ALTER TABLE app_role ADD COLUMN IF NOT EXISTS code varchar(50);

UPDATE app_role r SET code = c.code
FROM (VALUES
  ('R20', 'PUMA_ADMIN'),
  ('R21', 'USER_MANAGER'),
  ('R22', 'USER_VIEWER'),
  ('R23', 'CATALOGUE_OWNER'),
  ('R10', 'PARTNER_ADMIN'),
  ('R11', 'TEMPORARY_SELLER'),
  ('R12', 'POINT_OF_SALE_MANAGER'),
  ('R13', 'SELLER'),
  ('R14', 'SALES_MANAGER'),
  ('R15', 'FINANCING_ADVISOR'),
  ('R16', 'FINANCING_SUPERVISOR')
) AS c(id, code)
WHERE r.id = c.id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_app_role_code ON app_role (code) WHERE code IS NOT NULL;

-- Index utiles aux vues et au PDP
CREATE INDEX IF NOT EXISTS idx_node_parent_parent ON node_parent (parent_id);
CREATE INDEX IF NOT EXISTS idx_node_parent_node   ON node_parent (node_id);
CREATE INDEX IF NOT EXISTS idx_assignment_user    ON assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_app_role_parent    ON app_role (parent_role_id);

-- Vues : héritage descendant, rôle global, application disponible sur le noeud
CREATE VIEW puma_user_node_roles AS
WITH RECURSIVE scope AS (
    SELECT a.user_id, a.role_id, a.node_id
    FROM assignment a
  UNION
    SELECT s.user_id, s.role_id, np.node_id
    FROM scope s
    JOIN node_parent np ON np.parent_id = s.node_id
)
SELECT DISTINCT u.uid, s.node_id,
       g.id   AS role_id,
       g.application_id,
       g.code AS role_code
FROM scope s
JOIN puma_user u         ON u.id = s.user_id
JOIN app_role r          ON r.id = s.role_id
JOIN app_role g          ON g.id = COALESCE(r.parent_role_id, r.id)
JOIN node_application na ON na.node_id = s.node_id
                        AND na.application_id = r.application_id
WHERE u.status = 'ACTIVE';

CREATE VIEW partner_user_node_roles AS
SELECT v.uid, v.node_id, v.role_id, r.application_id
FROM puma_user_node_roles v
JOIN app_role r ON r.id = v.role_id;

CREATE VIEW partner_user_node_permissions AS
SELECT DISTINCT v.uid, v.node_id, v.application_id, p.code AS permission_code
FROM partner_user_node_roles v
JOIN role_permission rp ON rp.role_id = v.role_id AND rp.granted = true
JOIN permission p       ON p.id = rp.permission_id;

-- Contrôle de non-régression : mêmes lignes qu'avant la migration
DO $$
DECLARE
  diff_roles int;
  diff_perms int;
BEGIN
  SELECT count(*) INTO diff_roles FROM (
    (SELECT uid, node_id, role_id FROM snap_roles
     EXCEPT SELECT uid, node_id, role_id FROM puma_user_node_roles)
    UNION ALL
    (SELECT uid, node_id, role_id FROM puma_user_node_roles
     EXCEPT SELECT uid, node_id, role_id FROM snap_roles)) d;

  SELECT count(*) INTO diff_perms FROM (
    (SELECT * FROM snap_perms
     EXCEPT SELECT uid, node_id, application_id, permission_code FROM partner_user_node_permissions)
    UNION ALL
    (SELECT uid, node_id, application_id, permission_code FROM partner_user_node_permissions
     EXCEPT SELECT * FROM snap_perms)) d;

  IF diff_roles > 0 OR diff_perms > 0 THEN
    RAISE EXCEPTION 'Migration annulee : % ecarts sur puma_user_node_roles, % sur partner_user_node_permissions',
      diff_roles, diff_perms;
  END IF;
  RAISE NOTICE 'Controle OK : vues identiques avant et apres migration';
END $$;

COMMIT;
```

## Annexe C : puma-migration-uuid.sql (bascule vers les entryUUID, étape 2.5)

```sql
-- =====================================================================
-- PUMA : bascule des uid vers l'entryUUID de PingDirectory
-- A lancer EN MEME TEMPS que le changement du sub dans PingFederate
-- (étape 2.4), sinon plus aucun contexte ne sera accordé.
-- Remplace les deux valeurs REMPLACER_... par les entryUUID obtenus
-- avec ldapsearch. Transaction unique.
-- =====================================================================
BEGIN;

CREATE TEMP TABLE uid_map (
  old_uid varchar(100) PRIMARY KEY,
  new_uid varchar(100) NOT NULL
) ON COMMIT DROP;

INSERT INTO uid_map (old_uid, new_uid) VALUES
  ('thomas.martin', 'REMPLACER_UUID_THOMAS'),
  ('max.walker',    'REMPLACER_UUID_MAX');

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM uid_map
             WHERE new_uid !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') THEN
    RAISE EXCEPTION 'Bascule annulee : un entryUUID est manquant ou mal forme';
  END IF;
END $$;

UPDATE puma_user u
SET uid = m.new_uid
FROM uid_map m
WHERE u.uid = m.old_uid;

-- Utilisateurs restant avec un identifiant non UUID (à traiter à la main)
SELECT uid AS uid_non_converti
FROM puma_user
WHERE uid !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

COMMIT;
```
