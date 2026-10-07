+ "WHERE a.node_id::text IN (SELECT node_id FROM sous_arbre) "
      + "  AND r.application_id::text <> 'A0' "
      + "  AND u.uid <> 'thomas.martin' "
      + "ORDER BY u.uid, ap.name, n.label";




# PUMA : module users-v2, liste des utilisateurs et changement de rôle

Écran volontairement simple : un lien dans la barre de navigation, un tableau des affectations du périmètre du manager, et un bouton pour changer le rôle d'une affectation. L'identité, l'application et le noeud sont affichés en lecture seule. Seul le rôle est modifiable.

Rien d'existant n'est modifié, sauf une route et un lien. Pour revenir en arrière, il suffit de supprimer les nouveaux fichiers, la route et le lien.

## Fonctionnement

1. Le tableau liste les affectations dont le noeud est dans le sous-arbre du noeud de contexte du manager (celui du token). Jamais toute la base.
2. Le nom, le prénom et l'email sont lus dans PingDirectory, en une seule recherche LDAP pour toute la liste. Si l'annuaire ne répond pas, le tableau s'affiche quand même, avec le login seul.
3. Le changement de rôle vérifie que le noeud est dans le sous-arbre du manager (requête SQL, sans appel au PDP dans cette version), que le rôle est global et de la même application, puis met à jour la table assignment. Rien ne change dans PingDirectory.
4. PingAuthorize voit le nouveau rôle immédiatement, puisqu'il lit la base à chaque décision. Le token de l'utilisateur, lui, ne contient le nouveau rôle qu'après une nouvelle connexion.

## Fichiers à créer

```
Backend (package com.poc.banking)
  repository/UserAdminV2Repository.java
  service/LdapIdentityV2Service.java
  controller/UserAdminV2Controller.java

Frontend (src/app)
  core/user-admin-v2.service.ts
  features/users-v2/users-v2.component.ts
  features/users-v2/users-v2.component.html
  features/users-v2/users-v2.component.css
```

Fichiers modifiés : app.routes.ts (une route) et le template du composant principal (un lien).

## Hypothèses à vérifier avant de compiler

Ce module a été écrit sans voir le code actuel de ces fichiers. Chaque point ci-dessous est le seul endroit à adapter s'il diffère.

| Point | Hypothèse | Si ça ne compile pas |
|---|---|---|
| JwtSubject | `isManager(token)`, `node(token)` et `uid(token)` renvoient boolean, String et String | Adapter les trois appels |
| Tables (repository) | application(id, name), node(id, label), node_parent(node_id, parent_id), app_role(id, name, application_id, parent_role_id), puma_user(id, uid), assignment(id, user_id, role_id, node_id) | Adapter les noms de colonnes dans les requêtes SQL |
| LDAP (LdapIdentityV2Service) | Mêmes paramètres que createViaLdap | Renseigner les quatre propriétés puma.ldap.* avec les valeurs déjà utilisées |
| RoleV2Service | `list(applicationId, nodeId)` renvoie des objets avec `id` et `name` | Adapter l'appel dans `edit()` |
| Guard | La route create-user-v2 utilise `managerGuard` | Reprendre le guard de cette route |

Les requêtes SQL ont été testées sur PostgreSQL avec un schéma reproduisant ces colonnes : périmètre limité au sous-arbre, rôle refusé s'il n'est pas global ou pas de la même application, doublon détecté, mise à jour effective.

---

# Backend

Trois classes, une par couche :

```
repository/UserAdminV2Repository.java   requêtes SQL (JdbcTemplate)
service/LdapIdentityV2Service.java      identités lues dans PingDirectory
controller/UserAdminV2Controller.java   orchestration et codes HTTP
```

Le repository utilise JdbcTemplate plutôt que Spring Data JPA : les requêtes renvoient des jointures sur cinq tables, c'est-à-dire une projection et non une entité. Il ne dépend donc ni de l'entité Assignment ni des relations JPA existantes.

## `repository/UserAdminV2Repository.java`

```java
package com.poc.banking.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

/** Accès base du module users-v2 : affectations du périmètre et changement de rôle. */
@Repository
public class UserAdminV2Repository {

    /** Sous-arbre du noeud de contexte, noeud compris. */
    private static final String SOUS_ARBRE =
        "WITH RECURSIVE sous_arbre AS ("
      + "  SELECT CAST(? AS text) AS node_id"
      + "  UNION"
      + "  SELECT np.node_id::text FROM node_parent np"
      + "  JOIN sous_arbre s ON np.parent_id::text = s.node_id"
      + ") ";

    private static final String SQL_LIST = SOUS_ARBRE
      + "SELECT a.id, u.uid, r.application_id::text AS application_id, ap.name AS application_name,"
      + "       a.node_id::text AS node_id, n.label AS node_label,"
      + "       a.role_id::text AS role_id, r.name AS role_name "
      + "FROM assignment a "
      + "JOIN puma_user u    ON u.id = a.user_id "
      + "JOIN app_role r     ON r.id = a.role_id "
      + "JOIN application ap ON ap.id = r.application_id "
      + "JOIN node n         ON n.id = a.node_id "
      + "WHERE a.node_id::text IN (SELECT node_id FROM sous_arbre) "
      + "ORDER BY u.uid, ap.name, n.label";

    private static final String SQL_FIND =
        "SELECT a.id, a.user_id, u.uid, a.node_id::text AS node_id, "
      + "       r.application_id::text AS application_id "
      + "FROM assignment a "
      + "JOIN puma_user u ON u.id = a.user_id "
      + "JOIN app_role r  ON r.id = a.role_id "
      + "WHERE a.id = ?";

    private static final String SQL_IN_SUBTREE = SOUS_ARBRE
      + "SELECT count(*) FROM sous_arbre WHERE node_id = ?";

    /** Le rôle doit être global et appartenir à l'application de l'affectation. */
    private static final String SQL_ROLE_VALID =
        "SELECT count(*) FROM app_role "
      + "WHERE id::text = ? AND application_id::text = ? AND parent_role_id IS NULL";

    private static final String SQL_DUPLICATE =
        "SELECT count(*) FROM assignment "
      + "WHERE user_id = ? AND role_id::text = ? AND node_id::text = ? AND id <> ?";

    private static final String SQL_UPDATE_ROLE =
        "UPDATE assignment SET role_id = ? WHERE id = ?";

    /** Ligne du tableau, sans l'identité qui vient de l'annuaire. */
    public record AssignmentRow(long id, String uid, String applicationId, String applicationName,
                                String nodeId, String nodeLabel, String roleId, String roleName) {}

    /** Affectation ciblée par un changement de rôle. */
    public record AssignmentRef(long id, long userId, String uid, String nodeId, String applicationId) {}

    private final JdbcTemplate jdbc;

    public UserAdminV2Repository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<AssignmentRow> findInSubtree(String contextNode) {
        return jdbc.query(SQL_LIST, (rs, i) -> new AssignmentRow(
            rs.getLong("id"), rs.getString("uid"),
            rs.getString("application_id"), rs.getString("application_name"),
            rs.getString("node_id"), rs.getString("node_label"),
            rs.getString("role_id"), rs.getString("role_name")), contextNode);
    }

    public Optional<AssignmentRef> findById(long id) {
        List<AssignmentRef> rows = jdbc.query(SQL_FIND, (rs, i) -> new AssignmentRef(
            rs.getLong("id"), rs.getLong("user_id"), rs.getString("uid"),
            rs.getString("node_id"), rs.getString("application_id")), id);
        return rows.stream().findFirst();
    }

    public boolean isInSubtree(String contextNode, String nodeId) {
        Integer c = jdbc.queryForObject(SQL_IN_SUBTREE, Integer.class, contextNode, nodeId);
        return c != null && c > 0;
    }

    public boolean isRoleValidForApplication(String roleId, String applicationId) {
        Integer c = jdbc.queryForObject(SQL_ROLE_VALID, Integer.class, roleId, applicationId);
        return c != null && c > 0;
    }

    public boolean existsOther(long userId, String roleId, String nodeId, long excludedId) {
        Integer c = jdbc.queryForObject(SQL_DUPLICATE, Integer.class, userId, roleId, nodeId, excludedId);
        return c != null && c > 0;
    }

    public int updateRole(long assignmentId, String roleId) {
        return jdbc.update(SQL_UPDATE_ROLE, roleId, assignmentId);
    }
}
```

## `service/LdapIdentityV2Service.java`

```java
package com.poc.banking.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.naming.Context;
import javax.naming.NamingEnumeration;
import javax.naming.NamingException;
import javax.naming.directory.Attribute;
import javax.naming.directory.Attributes;
import javax.naming.directory.DirContext;
import javax.naming.directory.InitialDirContext;
import javax.naming.directory.SearchControls;
import javax.naming.directory.SearchResult;
import java.util.Collection;
import java.util.HashMap;
import java.util.Hashtable;
import java.util.Map;
import java.util.Objects;

/** Lecture des identités dans PingDirectory, en une seule recherche pour toute la liste. */
@Service
public class LdapIdentityV2Service {

    private static final Logger LOG = LoggerFactory.getLogger(LdapIdentityV2Service.class);

    public record Identity(String firstName, String lastName, String email) {
        public static final Identity EMPTY = new Identity("", "", "");
    }

    @Value("${puma.ldap.url:ldap://localhost:1389}")
    private String url;

    @Value("${puma.ldap.bind-dn:cn=administrator}")
    private String bindDn;

    @Value("${puma.ldap.password:2FederateM0re}")
    private String password;

    @Value("${puma.ldap.base-dn:ou=people,dc=example,dc=com}")
    private String baseDn;

    /** En cas d'échec, renvoie une map vide : le tableau garde alors le login seul. */
    public Map<String, Identity> findByUids(Collection<String> uids) {
        Map<String, Identity> result = new HashMap<>();
        if (uids == null || uids.isEmpty()) {
            return result;
        }

        Hashtable<String, String> env = new Hashtable<>();
        env.put(Context.INITIAL_CONTEXT_FACTORY, "com.sun.jndi.ldap.LdapCtxFactory");
        env.put(Context.PROVIDER_URL, url);
        env.put(Context.SECURITY_AUTHENTICATION, "simple");
        env.put(Context.SECURITY_PRINCIPAL, bindDn);
        env.put(Context.SECURITY_CREDENTIALS, password);
        env.put("com.sun.jndi.ldap.connect.timeout", "3000");
        env.put("com.sun.jndi.ldap.read.timeout", "3000");

        // Filtre paramétré : les uid ne sont jamais concaténés dans le filtre.
        StringBuilder filter = new StringBuilder("(|");
        Object[] args = new Object[uids.size()];
        int i = 0;
        for (String uid : uids) {
            filter.append("(uid={").append(i).append("})");
            args[i++] = uid;
        }
        filter.append(")");

        SearchControls controls = new SearchControls();
        controls.setSearchScope(SearchControls.SUBTREE_SCOPE);
        controls.setReturningAttributes(new String[] {"uid", "givenName", "sn", "mail"});

        DirContext ctx = null;
        try {
            ctx = new InitialDirContext(env);
            NamingEnumeration<SearchResult> found = ctx.search(baseDn, filter.toString(), args, controls);
            while (found.hasMore()) {
                Attributes attrs = found.next().getAttributes();
                String uid = value(attrs.get("uid"));
                if (uid != null) {
                    result.put(uid.toLowerCase(), new Identity(
                        Objects.toString(value(attrs.get("givenName")), ""),
                        Objects.toString(value(attrs.get("sn")), ""),
                        Objects.toString(value(attrs.get("mail")), "")));
                }
            }
        } catch (NamingException e) {
            LOG.warn("[users-v2] LDAP lookup failed, identities not displayed: {}", e.getMessage());
        } finally {
            if (ctx != null) {
                try { ctx.close(); } catch (NamingException ignored) { }
            }
        }
        return result;
    }

    private static String value(Attribute attr) throws NamingException {
        return attr == null ? null : (String) attr.get();
    }
}
```

## `controller/UserAdminV2Controller.java`

```java
package com.poc.banking.controller;

import com.poc.banking.repository.UserAdminV2Repository;
import com.poc.banking.repository.UserAdminV2Repository.AssignmentRef;
import com.poc.banking.repository.UserAdminV2Repository.AssignmentRow;
import com.poc.banking.service.LdapIdentityV2Service;
import com.poc.banking.service.LdapIdentityV2Service.Identity;
import com.poc.banking.util.JwtSubject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/** Liste des affectations du périmètre du manager et changement de rôle. */
@RestController
@RequestMapping("/api/users-v2")
public class UserAdminV2Controller {

    private static final Logger LOG = LoggerFactory.getLogger(UserAdminV2Controller.class);

    public record UserAssignmentV2(long id, String uid, String firstName, String lastName,
                                   String email, String applicationId, String applicationName,
                                   String nodeId, String nodeLabel, String roleId, String roleName) {}

    public record ChangeRoleRequestV2(String role) {}

    private final UserAdminV2Repository repository;
    private final LdapIdentityV2Service ldap;

    public UserAdminV2Controller(UserAdminV2Repository repository, LdapIdentityV2Service ldap) {
        this.repository = repository;
        this.ldap = ldap;
    }

    @GetMapping("/assignments")
    public ResponseEntity<?> list(JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return ResponseEntity.status(403).body("Manager context required");
        }
        List<AssignmentRow> rows = repository.findInSubtree(JwtSubject.node(token));

        Set<String> uids = new LinkedHashSet<>();
        rows.forEach(r -> uids.add(r.uid()));
        Map<String, Identity> identities = ldap.findByUids(uids);

        List<UserAssignmentV2> result = rows.stream().map(r -> {
            Identity id = identities.getOrDefault(r.uid().toLowerCase(), Identity.EMPTY);
            return new UserAssignmentV2(r.id(), r.uid(), id.firstName(), id.lastName(), id.email(),
                r.applicationId(), r.applicationName(), r.nodeId(), r.nodeLabel(),
                r.roleId(), r.roleName());
        }).toList();

        return ResponseEntity.ok(result);
    }

    @PutMapping("/assignments/{id}")
    @Transactional
    public ResponseEntity<?> changeRole(@PathVariable long id,
                                        @RequestBody ChangeRoleRequestV2 request,
                                        JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return ResponseEntity.status(403).body("Manager context required");
        }
        if (request == null || request.role() == null || request.role().isBlank()) {
            return ResponseEntity.badRequest().body("Role is required");
        }
        String newRole = request.role().trim();
        String contextNode = JwtSubject.node(token);

        Optional<AssignmentRef> found = repository.findById(id);
        if (found.isEmpty()) {
            return ResponseEntity.status(404).body("Assignment not found");
        }
        AssignmentRef a = found.get();

        // Contrôle SQL, pas PDP : le noeud doit être dans le sous-arbre du contexte.
        if (!repository.isInSubtree(contextNode, a.nodeId())) {
            return ResponseEntity.status(403).body("Node outside your scope: " + a.nodeId());
        }
        if (!repository.isRoleValidForApplication(newRole, a.applicationId())) {
            return ResponseEntity.badRequest().body("Role not available for this application: " + newRole);
        }
        if (repository.existsOther(a.userId(), newRole, a.nodeId(), a.id())) {
            return ResponseEntity.status(409).body("The user already has this role on this node");
        }

        repository.updateRole(a.id(), newRole);
        LOG.info("[users-v2] {} changed assignment {} of {} on {} to role {}",
            JwtSubject.uid(token), a.id(), a.uid(), a.nodeId(), newRole);

        return ResponseEntity.ok(Map.of("message", "Role updated"));
    }
}
```

Dans application.yml, si les valeurs par défaut ne correspondent pas, reprendre celles déjà utilisées par createViaLdap :

```yaml
puma:
  ldap:
    url: ldap://localhost:1389
    bind-dn: cn=administrator
    password: 2FederateM0re
    base-dn: ou=people,dc=example,dc=com
```

---

# Frontend

## `core/user-admin-v2.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';

export interface UserAssignmentV2 {
  id: number;
  uid: string;
  firstName: string;
  lastName: string;
  email: string;
  applicationId: string;
  applicationName: string;
  nodeId: string;
  nodeLabel: string;
  roleId: string;
  roleName: string;
}

@Injectable({ providedIn: 'root' })
export class UserAdminV2Service {

  constructor(private auth: AuthService) {}

  async list(): Promise<UserAssignmentV2[]> {
    const resp = await fetch(`${API_BASE_V2}/users-v2/assignments`, {
      headers: { Authorization: 'Bearer ' + this.auth.getToken() }
    });
    if (!resp.ok) {
      throw new Error((await resp.text()) || `Error ${resp.status}`);
    }
    return resp.json();
  }

  async changeRole(assignmentId: number, role: string): Promise<void> {
    const resp = await fetch(`${API_BASE_V2}/users-v2/assignments/${assignmentId}`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.auth.getToken()
      },
      body: JSON.stringify({ role })
    });
    if (!resp.ok) {
      throw new Error((await resp.text()) || `Error ${resp.status}`);
    }
  }
}
```

## `features/users-v2/users-v2.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';

import { UserAdminV2Service, UserAssignmentV2 } from '../../core/user-admin-v2.service';
import { RoleV2Service } from '../../core/role-v2.service';
import { RoleV2 } from '../../core/models/puma-v2.model';

@Component({
  selector: 'app-users-v2',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './users-v2.component.html',
  styleUrls: ['./users-v2.component.css']
})
export class UsersV2Component implements OnInit {

  rows: UserAssignmentV2[] = [];
  loading = false;
  error = '';
  message = '';

  editingId: number | null = null;
  roles: RoleV2[] = [];
  selectedRole = '';
  loadingRoles = false;
  saving = false;
  editError = '';

  constructor(private users: UserAdminV2Service,
              private roleService: RoleV2Service) {}

  async ngOnInit(): Promise<void> {
    await this.load();
  }

  async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      this.rows = await this.users.list();
    } catch (e: any) {
      this.error = e.message;
    } finally {
      this.loading = false;
    }
  }

  fullName(row: UserAssignmentV2): string {
    return `${row.firstName} ${row.lastName}`.trim();
  }

  async edit(row: UserAssignmentV2): Promise<void> {
    this.editingId = row.id;
    this.selectedRole = row.roleId;
    this.editError = '';
    this.message = '';
    this.roles = [];
    this.loadingRoles = true;
    try {
      this.roles = await this.roleService.list(row.applicationId, row.nodeId);
    } catch (e: any) {
      this.editError = e.message;
    } finally {
      this.loadingRoles = false;
    }
  }

  cancel(): void {
    this.editingId = null;
    this.editError = '';
  }

  async save(row: UserAssignmentV2): Promise<void> {
    if (this.selectedRole === row.roleId) {
      this.cancel();
      return;
    }
    this.saving = true;
    this.editError = '';
    try {
      await this.users.changeRole(row.id, this.selectedRole);
      this.message = `Role updated for ${row.uid} on ${row.nodeLabel}.`;
      this.editingId = null;
      await this.load();
    } catch (e: any) {
      this.editError = e.message;
    } finally {
      this.saving = false;
    }
  }
}
```

## `features/users-v2/users-v2.component.html`

```html
<div class="page">
  <h1>Users</h1>
  <p class="subtitle">Assignments in your current scope.</p>

  <p class="info" *ngIf="loading">Loading...</p>
  <p class="alert ko" *ngIf="error">{{ error }}</p>
  <p class="alert ok" *ngIf="message">{{ message }}</p>

  <table *ngIf="!loading && rows.length > 0">
    <thead>
      <tr>
        <th>Login</th>
        <th>Name</th>
        <th>Email</th>
        <th>Application</th>
        <th>Node</th>
        <th>Role</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <ng-container *ngFor="let row of rows">
        <tr>
          <td>{{ row.uid }}</td>
          <td>{{ fullName(row) }}</td>
          <td>{{ row.email }}</td>
          <td>{{ row.applicationName }}</td>
          <td>{{ row.nodeLabel }} <span class="muted">{{ row.nodeId }}</span></td>
          <td>{{ row.roleName }}</td>
          <td>
            <button type="button" (click)="edit(row)" [disabled]="editingId !== null">
              Change role
            </button>
          </td>
        </tr>

        <tr *ngIf="editingId === row.id" class="edit-row">
          <td colspan="7">
            <div class="edit">
              <label>Application
                <input type="text" [value]="row.applicationName" disabled>
              </label>
              <label>Node
                <input type="text" [value]="row.nodeLabel + ' (' + row.nodeId + ')'" disabled>
              </label>
              <label>Role
                <select [(ngModel)]="selectedRole" [disabled]="loadingRoles || saving">
                  <option *ngFor="let role of roles" [value]="role.id">{{ role.name }}</option>
                </select>
              </label>
              <div class="edit-actions">
                <button type="button" (click)="save(row)" [disabled]="saving || loadingRoles">
                  {{ saving ? 'Saving...' : 'Save' }}
                </button>
                <button type="button" class="secondary" (click)="cancel()" [disabled]="saving">
                  Cancel
                </button>
              </div>
            </div>
            <p class="alert ko" *ngIf="editError">{{ editError }}</p>
          </td>
        </tr>
      </ng-container>
    </tbody>
  </table>

  <p class="info" *ngIf="!loading && !error && rows.length === 0">
    No assignment in your scope.
  </p>
</div>
```

## `features/users-v2/users-v2.component.css`

```css
.page {
  max-width: 1100px;
  margin: 24px auto;
  padding: 0 16px;
  font-family: system-ui, sans-serif;
}

h1 {
  margin: 0;
  font-size: 1.4rem;
}

.subtitle {
  margin: 4px 0 16px;
  color: #666;
}

table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.9rem;
}

th,
td {
  padding: 8px;
  border-bottom: 1px solid #ddd;
  text-align: left;
  vertical-align: middle;
}

th {
  background: #f4f4f4;
}

.muted {
  color: #888;
  font-size: 0.8rem;
}

.edit-row td {
  background: #fafafa;
}

.edit {
  display: flex;
  gap: 12px;
  align-items: flex-end;
  flex-wrap: wrap;
}

.edit label {
  display: flex;
  flex-direction: column;
  font-size: 0.8rem;
  font-weight: 600;
}

.edit input,
.edit select {
  margin-top: 4px;
  padding: 6px;
  min-width: 180px;
}

.edit input:disabled {
  background: #eee;
  color: #666;
}

.edit-actions {
  display: flex;
  gap: 8px;
}

button {
  padding: 6px 12px;
  cursor: pointer;
}

button.secondary {
  background: #fff;
}

.info {
  color: #666;
}

.alert {
  padding: 8px 12px;
  margin: 8px 0;
}

.alert.ok {
  background: #e9f4ec;
  color: #1b5e20;
}

.alert.ko {
  background: #fbeaea;
  color: #8a1020;
}
```

---

# Branchement

## La route, dans `app.routes.ts`

```typescript
import { UsersV2Component } from './features/users-v2/users-v2.component';

// à ajouter à côté de la route create-user-v2, avec le même guard
{ path: 'users-v2', component: UsersV2Component, canActivate: [managerGuard] },
```

## Le lien, dans le template du composant principal

Dans le div de la nav existante, à côté des liens actuels :

```html
<a routerLink="/users-v2">Users</a>
```

Si les liens existants utilisent déjà routerLink, il n'y a rien d'autre à faire. Sinon, ajouter RouterLink dans les imports du composant principal :

```typescript
import { RouterLink } from '@angular/router';
// imports: [..., RouterLink]
```

---

# Tests attendus

| Test | Attendu |
|---|---|
| thomas.martin, contexte Roller 5, lien Users | Tableau des affectations des noeuds sous Roller 5 uniquement, avec nom et email |
| PingDirectory arrêté | Tableau affiché quand même, nom et email vides, ligne LDAP lookup failed dans les logs |
| Change role sur l'affectation de julia.weber (Rataweb, 2700013), passage à FINANCING_SUPERVISOR | Message Role updated, tableau rafraîchi avec le nouveau rôle |
| Juste après, julia.weber approuve un contrat dans Rataweb | Décision PingAuthorize PERMIT sans redéploiement. Si Rataweb contrôle aussi les rôles du token, une reconnexion de julia est nécessaire |
| curl PUT sur une affectation hors du sous-arbre | 403 Node outside your scope |
| curl PUT avec un rôle d'une autre application | 400 Role not available for this application |
| Choisir un rôle que l'utilisateur a déjà sur ce noeud | 409 The user already has this role on this node |

Exemple de curl, avec le token de contexte du manager :

```bash
curl -s -X PUT http://localhost:8081/api/users-v2/assignments/123 \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role":"R16"}'
```
