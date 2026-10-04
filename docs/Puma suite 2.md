# PUMA : étape 3.2 sans UUID, création d'un utilisateur

Version du 04/10/2026. Remplace la section 3.2 de PUMA-plan-etapes-3-a-6.md et l'ancienne version de ce fichier, qui ne correspondait pas au code existant.

L'identifiant reste le login (uid) en minuscules. Aucune dépendance à l'entryUUID.

---

## 1. Pourquoi cette étape est urgente

Depuis la migration du 03/10, puma_user n'a plus de colonnes email ni display_name. Or `UserDatabaseService.save()` les renseigne encore : **la création d'utilisateur est cassée** tant que ce n'est pas corrigé.

## 2. Ce qui ne change pas

Le flux existant reste tel quel :

1. POST /api/users avec `CreateUserRequest` (uid, firstName, lastName, email, assignments) ;
2. `UserProvisioningService` : `validate(req)`, puis `checkDelegation(...)` (décision PingAuthorize), puis `userDatabaseService.save(req, managerUid)`, puis `if (!exists(req.uid())) createViaLdap(req)` ;
3. `createViaLdap` écrit dans PingDirectory l'uid, le prénom, le nom, l'email et le mot de passe initial.

C'est PUMA qui crée le compte dans l'annuaire. Prénom, nom et email restent donc dans `CreateUserRequest` et dans le formulaire : ils partent dans PingDirectory, plus dans PostgreSQL. C'est exactement la note de Nicolas.

Ne touche pas non plus à l'ordre : la base d'abord, l'annuaire ensuite. Si la base refuse, aucun compte LDAP n'est créé pour rien.

## 3. Entité PumaUser

Supprime les champs `email` et `displayName`, ainsi que leurs getters et setters. Ajoute :

```java
@Column(name = "created_by", length = 100)
private String createdBy;

public String getCreatedBy() { return createdBy; }
public void setCreatedBy(String createdBy) { this.createdBy = createdBy; }
```

Puis vérifie que rien d'autre ne les utilise :

```bash
grep -rn "getEmail\|setEmail\|getDisplayName\|setDisplayName" src/main/java/
```

Seuls des appels sur `req` (le `CreateUserRequest`) doivent rester, par exemple `req.email()` dans `createViaLdap`. Tout appel sur une entité PumaUser doit disparaître.

## 4. UserDatabaseService.save

Seul le bloc de création de l'utilisateur change. Version complète de la méthode :

```java
/** Crée l'utilisateur PUMA s'il n'existe pas, puis ajoute les affectations manquantes. */
@Transactional
public PumaUser save(CreateUserRequest req, String managerUid) {
    String uid = req.uid().trim().toLowerCase(Locale.ROOT);

    // Seuls les rôles globaux sont affectables : une spécialisation
    // s'applique d'elle-même par le noeud, elle ne s'affecte jamais.
    for (AssignmentDto a : req.assignments()) {
        Number globalRoles = (Number) entityManager.createNativeQuery(
                        "SELECT count(*) FROM app_role WHERE id = ?1 AND node_id IS NULL")
                .setParameter(1, a.role())
                .getSingleResult();
        if (globalRoles.intValue() == 0) {
            throw new IllegalArgumentException(
                    "Rôle non affectable (inconnu ou spécialisé) : " + a.role());
        }
    }

    PumaUser user = users.findByUid(uid).orElseGet(() -> {
        PumaUser u = new PumaUser();
        u.setUid(uid);
        u.setCreatedBy(managerUid);   // plus d'email ni de nom en base
        return users.save(u);
    });

    for (AssignmentDto a : req.assignments()) {
        if (!assignments.existsByUser_UidAndRole_IdAndNodeId(uid, a.role(), a.node())) {
            Assignment assignment = new Assignment();
            assignment.setUser(user);
            assignment.setRole(entityManager.getReference(AppRole.class, a.role()));
            assignment.setNodeId(a.node());
            assignment.setCreatedBy(managerUid);
            assignments.save(assignment);
        }
    }
    return user;
}
```

Par rapport à ton code actuel :

- **supprimé** : `u.setEmail(req.email());` et `u.setDisplayName(req.firstName() + " " + req.lastName());` ;
- **ajouté** : `u.setCreatedBy(managerUid);` ;
- **ajouté** : la vérification que chaque rôle est global. Elle est faite avant toute écriture, donc un rôle refusé ne laisse rien en base. Elle passe par une requête native pour ne dépendre d'aucun champ des entités Role ou AppRole.

Si tes accesseurs ont un autre nom (`req.getUid()`, `a.getRole()`...), adapte-les. Les imports restent ceux de la classe actuelle : `java.util.Locale`, `jakarta.persistence.EntityManager`, `AppRole`, `Assignment`, `PumaUser`, `AssignmentDto`, `CreateUserRequest`.

Le contrôleur traduit déjà `IllegalArgumentException` en réponse 400. Si ce n'est plus le cas dans ta version, ajoute le catch correspondant dans `UserController`.

## 5. RoleController : ne proposer que les rôles globaux

Même raison : le manager ne doit jamais voir de spécialisation dans la liste. Dans `RoleController.list`, garde seulement les rôles globaux :

```java
@GetMapping
public List<RoleDto> list(@RequestParam String application,
                          @RequestParam(required = false) String node) {
    // Rôles globaux uniquement : la spécialisation éventuelle du noeud
    // est appliquée par le PDP, elle n'est ni visible ni affectable.
    return roles.findByApplicationIdAndNodeIdIsNull(application).stream()
            .map(this::toDto)
            .toList();
}
```

Le paramètre `node` reste accepté, pour ne rien casser côté frontend, mais il n'est plus utilisé.

Dans `toDto`, passe le code du rôle au record `RoleDto`, à la position où tu as ajouté le champ :

```java
role.getCode()
```

## 6. Tests

**1. Démarrage** : le backend démarre sans erreur SQL ni erreur Hibernate.

**2. Création dans l'IHM** : thomas.martin, contexte 9200005, crée julia.weber (prénom, nom, email) avec FINANCING_ADVISOR (R15) sur 2700013. Bandeau vert attendu. Puis vérifie la base :

```sql
SELECT u.uid, u.created_by, a.role_id, a.node_id, a.created_by
FROM puma_user u
JOIN assignment a ON a.user_id = u.id
WHERE u.uid = 'julia.weber';
```

Attendu : une ligne, R15 sur 2700013, created_by = thomas.martin dans les deux colonnes.

Puis l'annuaire :

```bash
docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword "<mot_de_passe>" \
  --baseDN "ou=people,dc=example,dc=com" \
  "(uid=julia.weber)" uid givenName sn mail
```

Attendu : l'entrée avec prénom, nom et email.

**3. Idempotence** : recrée julia.weber avec la même affectation. Aucune erreur, aucune ligne en double.

**4. Liste des rôles** : sur Auto Eder Traunstein (2672756) avec Mobility Hub, la liste ne propose que les rôles globaux, avec leur code (SELLER...). Aucune ligne R17 ou R18.

**5. Refus d'une spécialisation par l'API** (l'IHM ne la propose plus, le test passe donc par curl, avec le token de contexte de thomas.martin) :

```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:8081/api/users \
  -H "Authorization: Bearer $TOKEN_CONTEXTE" -H "Content-Type: application/json" \
  -d '{"uid":"test.speciale","firstName":"Test","lastName":"Speciale","email":"test@example.com",
       "assignments":[{"application":"A2","node":"2672756","role":"R18"}]}'
```

Attendu : 400 si PingAuthorize accepte le noeud, ou 403 si le noeud est hors du périmètre de thomas.martin. Dans les deux cas, ni ligne en base ni compte LDAP pour test.speciale.

**6. Le test qui valide tout** : connecte-toi avec julia.weber et le mot de passe initial. La pop-up doit proposer 2700013, et le token de contexte contenir `node: 2700013` et `roles: ["R15"]`.

## 7. Plus tard (après la démo)

- Bascule vers l'entryUUID : il faudra créer le compte LDAP avant l'écriture en base, pour lire son entryUUID et l'enregistrer à la place du login.
- Mot de passe initial : aujourd'hui une constante commune à tous les comptes. Cible : le parcours "mot de passe oublié" de PingFederate, avec un serveur SMTP.
- Retirer le bloc portalRole / addToGroup de `createViaLdap` en même temps que isMemberOf (étape 2.2).
