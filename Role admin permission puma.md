# PUMA : module role-admin, création des rôles d'application

Critère de succès couvert : "A business admin user can create business application roles and group the sample business application permissions into these roles".

Écran simple : un lien Roles à côté de Users. On choisit une application, on voit ses rôles avec leurs permissions, on crée un rôle (code, nom, permissions cochées) ou on modifie les permissions d'un rôle existant.

Rien d'existant n'est modifié, sauf une route et un lien. Pour revenir en arrière, il suffit de supprimer les nouveaux fichiers, la route et le lien.

## Règles appliquées

1. Un rôle appartient à une seule application. Il ne peut contenir que des permissions de cette application (contrôle dans le service, pas seulement dans l'écran).
2. Au moins une permission par rôle.
3. Le code est unique par application, en majuscules, lettres, chiffres et underscore.
4. L'identifiant suit le format existant : R suivi du numéro suivant (R22, R23...).
5. Seuls les rôles globaux sont listés et modifiables. Les anciennes spécialisations (parent_role_id renseigné) sont ignorées.
6. Une modification des permissions s'applique tout de suite aux utilisateurs qui ont le rôle, puisque PingAuthorize lit la base à chaque décision.

## Fichiers à créer

```
Backend (package com.poc.banking)
  repository/RoleAdminRepository.java   requêtes SQL (JdbcTemplate)
  service/RoleAdminService.java         règles métier et transactions
  controller/RoleAdminController.java   endpoints et codes HTTP

Frontend (src/app)
  core/role-admin.service.ts
  features/role-admin/role-admin.component.ts
  features/role-admin/role-admin.component.html
  features/role-admin/role-admin.component.css
```

Endpoints :

| Méthode | Chemin | Rôle |
|---|---|---|
| GET | /api/role-admin/applications | Liste des applications |
| GET | /api/role-admin/applications/{id}/permissions | Permissions de l'application |
| GET | /api/role-admin/applications/{id}/roles | Rôles globaux avec leurs permissions |
| POST | /api/role-admin/roles | Création d'un rôle avec ses permissions |
| PUT | /api/role-admin/roles/{id}/permissions | Remplacement des permissions d'un rôle |

## Vérifications faites

Les requêtes SQL ont été exécutées sur PostgreSQL 16 avec un schéma reprenant exactement tes colonnes (app_role, permission, role_permission, application) : liste des rôles avec codes de permission, calcul du prochain identifiant, création, contrôle d'application des permissions, exclusion des spécialisations. Le composant Angular passe la compilation en mode strict (strictTemplates). Le Java n'a pas pu être compilé ici faute d'accès à Maven Central : relis les imports si ton IDE signale quelque chose.

## Hypothèses à vérifier avant de lancer

| Point | Hypothèse | Si ce n'est pas le cas |
|---|---|---|
| role_permission.id | Généré automatiquement par la base (comme assignment.id) | Voir la requête ci-dessous |
| JwtSubject | `isManager(token)` et `uid(token)`, comme dans users-v2 | Adapter les appels |
| Frontend | `AuthService.getToken()` et `API_BASE_V2`, comme dans users-v2 | Adapter les imports du service |
| Guard | `managerGuard`, comme la route users-v2 | Reprendre le guard de users-v2 |

Vérifier role_permission.id :

```sql
SELECT column_default, is_identity
FROM information_schema.columns
WHERE table_name = 'role_permission' AND column_name = 'id';
```

Si les deux colonnes sont vides (pas de valeur par défaut), ajouter une séquence une fois :

```sql
CREATE SEQUENCE IF NOT EXISTS role_permission_id_seq;
SELECT setval('role_permission_id_seq', COALESCE((SELECT MAX(id) FROM role_permission), 0) + 1, false);
ALTER TABLE role_permission ALTER COLUMN id SET DEFAULT nextval('role_permission_id_seq');
COMMIT;
```

---

# Backend

## `backend/repository/RoleAdminRepository.java`

```java
package com.poc.banking.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.Arrays;
import java.util.Collection;
import java.util.List;

/** Accès base du module role-admin : applications, permissions, rôles et leur composition. */
@Repository
public class RoleAdminRepository {

    private static final String SQL_APPLICATIONS =
        "SELECT id, name FROM application ORDER BY name";

    private static final String SQL_APPLICATION_EXISTS =
        "SELECT count(*) FROM application WHERE id = ?";

    private static final String SQL_PERMISSIONS =
        "SELECT id, code, label FROM permission WHERE application_id = ? ORDER BY code";

    /** Rôles globaux de l'application (pas les anciennes spécialisations), avec leurs codes de permission. */
    private static final String SQL_ROLES =
        "SELECT r.id, r.code, r.name, "
      + "       COALESCE(string_agg(p.id, ',' ORDER BY p.code) FILTER (WHERE rp.granted IS NOT FALSE), '') AS permission_ids, "
      + "       COALESCE(string_agg(p.code, ',' ORDER BY p.code) FILTER (WHERE rp.granted IS NOT FALSE), '') AS permission_codes "
      + "FROM app_role r "
      + "LEFT JOIN role_permission rp ON rp.role_id = r.id "
      + "LEFT JOIN permission p ON p.id = rp.permission_id "
      + "WHERE r.application_id = ? AND r.parent_role_id IS NULL "
      + "GROUP BY r.id, r.code, r.name "
      + "ORDER BY r.code";

    private static final String SQL_ROLE_APPLICATION =
        "SELECT application_id FROM app_role WHERE id = ? AND parent_role_id IS NULL";

    private static final String SQL_CODE_EXISTS =
        "SELECT count(*) FROM app_role WHERE application_id = ? AND upper(code) = upper(?)";

    private static final String SQL_COUNT_APP_PERMISSIONS =
        "SELECT count(*) FROM permission WHERE application_id = :app AND id IN (:ids)";

    /** Les identifiants existants suivent le format R + nombre (R10, R21...). */
    private static final String SQL_NEXT_ROLE_ID =
        "SELECT 'R' || (COALESCE(MAX(CAST(substring(id FROM '^R([0-9]+)$') AS integer)), 0) + 1) "
      + "FROM app_role WHERE id ~ '^R[0-9]+$'";

    private static final String SQL_INSERT_ROLE =
        "INSERT INTO app_role (id, code, name, application_id, parent_role_id, node_id) "
      + "VALUES (?, ?, ?, ?, NULL, NULL)";

    private static final String SQL_DELETE_ROLE_PERMISSIONS =
        "DELETE FROM role_permission WHERE role_id = ?";

    private static final String SQL_INSERT_ROLE_PERMISSION =
        "INSERT INTO role_permission (role_id, permission_id, granted) VALUES (?, ?, true)";

    public record ApplicationRow(String id, String name) {}

    public record PermissionRow(String id, String code, String label) {}

    public record RoleRow(String id, String code, String name,
                          List<String> permissionIds, List<String> permissionCodes) {}

    private final JdbcTemplate jdbc;
    private final NamedParameterJdbcTemplate named;

    public RoleAdminRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        this.named = new NamedParameterJdbcTemplate(jdbc);
    }

    public List<ApplicationRow> findApplications() {
        return jdbc.query(SQL_APPLICATIONS, (rs, i) -> new ApplicationRow(rs.getString("id"), rs.getString("name")));
    }

    public boolean applicationExists(String applicationId) {
        Integer c = jdbc.queryForObject(SQL_APPLICATION_EXISTS, Integer.class, applicationId);
        return c != null && c > 0;
    }

    public List<PermissionRow> findPermissions(String applicationId) {
        return jdbc.query(SQL_PERMISSIONS, (rs, i) -> new PermissionRow(
            rs.getString("id"), rs.getString("code"), rs.getString("label")), applicationId);
    }

    public List<RoleRow> findRoles(String applicationId) {
        return jdbc.query(SQL_ROLES, (rs, i) -> new RoleRow(
            rs.getString("id"), rs.getString("code"), rs.getString("name"),
            split(rs.getString("permission_ids")), split(rs.getString("permission_codes"))), applicationId);
    }

    /** Application d'un rôle global, ou null si le rôle n'existe pas ou n'est pas global. */
    public String findRoleApplication(String roleId) {
        List<String> rows = jdbc.queryForList(SQL_ROLE_APPLICATION, String.class, roleId);
        return rows.isEmpty() ? null : rows.get(0);
    }

    public boolean codeExists(String applicationId, String code) {
        Integer c = jdbc.queryForObject(SQL_CODE_EXISTS, Integer.class, applicationId, code);
        return c != null && c > 0;
    }

    public int countPermissionsOfApplication(String applicationId, Collection<String> permissionIds) {
        MapSqlParameterSource params = new MapSqlParameterSource()
            .addValue("app", applicationId)
            .addValue("ids", permissionIds);
        Integer c = named.queryForObject(SQL_COUNT_APP_PERMISSIONS, params, Integer.class);
        return c == null ? 0 : c;
    }

    public String nextRoleId() {
        return jdbc.queryForObject(SQL_NEXT_ROLE_ID, String.class);
    }

    public void insertRole(String id, String code, String name, String applicationId) {
        jdbc.update(SQL_INSERT_ROLE, id, code, name, applicationId);
    }

    public void replacePermissions(String roleId, Collection<String> permissionIds) {
        jdbc.update(SQL_DELETE_ROLE_PERMISSIONS, roleId);
        for (String permissionId : permissionIds) {
            jdbc.update(SQL_INSERT_ROLE_PERMISSION, roleId, permissionId);
        }
    }

    private static List<String> split(String csv) {
        return csv == null || csv.isBlank() ? List.of() : Arrays.asList(csv.split(","));
    }
}
```

## `backend/service/RoleAdminService.java`

```java
package com.poc.banking.service;

import com.poc.banking.repository.RoleAdminRepository;
import com.poc.banking.repository.RoleAdminRepository.ApplicationRow;
import com.poc.banking.repository.RoleAdminRepository.PermissionRow;
import com.poc.banking.repository.RoleAdminRepository.RoleRow;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Pattern;

/** Règles métier du module role-admin. */
@Service
public class RoleAdminService {

    private static final Pattern CODE = Pattern.compile("^[A-Z][A-Z0-9_]{1,49}$");

    /** Erreur de validation, renvoyée en 400 par le contrôleur. */
    public static class InvalidRoleException extends RuntimeException {
        public InvalidRoleException(String message) { super(message); }
    }

    /** Ressource absente, renvoyée en 404. */
    public static class NotFoundException extends RuntimeException {
        public NotFoundException(String message) { super(message); }
    }

    /** Doublon, renvoyé en 409. */
    public static class ConflictException extends RuntimeException {
        public ConflictException(String message) { super(message); }
    }

    private final RoleAdminRepository repository;

    public RoleAdminService(RoleAdminRepository repository) {
        this.repository = repository;
    }

    public List<ApplicationRow> applications() {
        return repository.findApplications();
    }

    public List<PermissionRow> permissions(String applicationId) {
        requireApplication(applicationId);
        return repository.findPermissions(applicationId);
    }

    public List<RoleRow> roles(String applicationId) {
        requireApplication(applicationId);
        return repository.findRoles(applicationId);
    }

    @Transactional
    public String create(String applicationId, String code, String name, List<String> permissionIds) {
        requireApplication(applicationId);
        String cleanCode = code == null ? "" : code.trim().toUpperCase();
        String cleanName = name == null ? "" : name.trim();
        if (!CODE.matcher(cleanCode).matches()) {
            throw new InvalidRoleException("Code must use letters, digits and underscores, for example FINANCING_ADVISOR");
        }
        if (cleanName.isEmpty()) {
            throw new InvalidRoleException("Name is required");
        }
        if (repository.codeExists(applicationId, cleanCode)) {
            throw new ConflictException("A role with this code already exists for this application");
        }
        Set<String> permissions = checkPermissions(applicationId, permissionIds);

        String roleId = repository.nextRoleId();
        repository.insertRole(roleId, cleanCode, cleanName, applicationId);
        repository.replacePermissions(roleId, permissions);
        return roleId;
    }

    @Transactional
    public void updatePermissions(String roleId, List<String> permissionIds) {
        String applicationId = repository.findRoleApplication(roleId);
        if (applicationId == null) {
            throw new NotFoundException("Role not found: " + roleId);
        }
        repository.replacePermissions(roleId, checkPermissions(applicationId, permissionIds));
    }

    /** Au moins une permission, et toutes de la même application que le rôle. */
    private Set<String> checkPermissions(String applicationId, List<String> permissionIds) {
        Set<String> unique = new LinkedHashSet<>();
        if (permissionIds != null) {
            permissionIds.stream().filter(p -> p != null && !p.isBlank()).map(String::trim).forEach(unique::add);
        }
        if (unique.isEmpty()) {
            throw new InvalidRoleException("Select at least one permission");
        }
        if (repository.countPermissionsOfApplication(applicationId, unique) != unique.size()) {
            throw new InvalidRoleException("All permissions must belong to the role's application");
        }
        return unique;
    }

    private void requireApplication(String applicationId) {
        if (applicationId == null || !repository.applicationExists(applicationId)) {
            throw new NotFoundException("Application not found: " + applicationId);
        }
    }
}
```

## `backend/controller/RoleAdminController.java`

```java
package com.poc.banking.controller;

import com.poc.banking.service.RoleAdminService;
import com.poc.banking.service.RoleAdminService.ConflictException;
import com.poc.banking.service.RoleAdminService.InvalidRoleException;
import com.poc.banking.service.RoleAdminService.NotFoundException;
import com.poc.banking.util.JwtSubject;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/** Création des rôles d'une application et regroupement de ses permissions. */
@RestController
@RequestMapping("/api/role-admin")
public class RoleAdminController {

    private static final Logger LOG = LoggerFactory.getLogger(RoleAdminController.class);

    public record CreateRoleRequest(String applicationId, String code, String name, List<String> permissionIds) {}

    public record UpdatePermissionsRequest(List<String> permissionIds) {}

    private final RoleAdminService service;

    public RoleAdminController(RoleAdminService service) {
        this.service = service;
    }

    @GetMapping("/applications")
    public ResponseEntity<?> applications(JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return forbidden();
        }
        return ResponseEntity.ok(service.applications());
    }

    @GetMapping("/applications/{applicationId}/permissions")
    public ResponseEntity<?> permissions(@PathVariable String applicationId, JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return forbidden();
        }
        return ResponseEntity.ok(service.permissions(applicationId));
    }

    @GetMapping("/applications/{applicationId}/roles")
    public ResponseEntity<?> roles(@PathVariable String applicationId, JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return forbidden();
        }
        return ResponseEntity.ok(service.roles(applicationId));
    }

    @PostMapping("/roles")
    public ResponseEntity<?> create(@RequestBody CreateRoleRequest request, JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return forbidden();
        }
        if (request == null) {
            return ResponseEntity.badRequest().body("Request body is required");
        }
        String roleId = service.create(request.applicationId(), request.code(), request.name(), request.permissionIds());
        LOG.info("[role-admin] {} created role {} ({}) for application {} with permissions {}",
            JwtSubject.uid(token), roleId, request.code(), request.applicationId(), request.permissionIds());
        return ResponseEntity.status(201).body(Map.of("id", roleId, "message", "Role created"));
    }

    @PutMapping("/roles/{roleId}/permissions")
    public ResponseEntity<?> updatePermissions(@PathVariable String roleId,
                                               @RequestBody UpdatePermissionsRequest request,
                                               JwtAuthenticationToken token) {
        if (!JwtSubject.isManager(token)) {
            return forbidden();
        }
        service.updatePermissions(roleId, request == null ? null : request.permissionIds());
        LOG.info("[role-admin] {} set permissions of role {} to {}",
            JwtSubject.uid(token), roleId, request == null ? null : request.permissionIds());
        return ResponseEntity.ok(Map.of("message", "Permissions updated"));
    }

    @ExceptionHandler(InvalidRoleException.class)
    public ResponseEntity<String> invalid(InvalidRoleException e) {
        return ResponseEntity.badRequest().body(e.getMessage());
    }

    @ExceptionHandler(NotFoundException.class)
    public ResponseEntity<String> notFound(NotFoundException e) {
        return ResponseEntity.status(404).body(e.getMessage());
    }

    @ExceptionHandler(ConflictException.class)
    public ResponseEntity<String> conflict(ConflictException e) {
        return ResponseEntity.status(409).body(e.getMessage());
    }

    private static ResponseEntity<String> forbidden() {
        return ResponseEntity.status(403).body("Manager context required");
    }
}
```

---

# Frontend

## `core/role-admin.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';

export interface AdminApplication {
  id: string;
  name: string;
}

export interface AdminPermission {
  id: string;
  code: string;
  label: string;
}

export interface AdminRole {
  id: string;
  code: string;
  name: string;
  permissionIds: string[];
  permissionCodes: string[];
}

@Injectable({ providedIn: 'root' })
export class RoleAdminService {

  constructor(private auth: AuthService) {}

  applications(): Promise<AdminApplication[]> {
    return this.get('/role-admin/applications');
  }

  permissions(applicationId: string): Promise<AdminPermission[]> {
    return this.get(`/role-admin/applications/${encodeURIComponent(applicationId)}/permissions`);
  }

  roles(applicationId: string): Promise<AdminRole[]> {
    return this.get(`/role-admin/applications/${encodeURIComponent(applicationId)}/roles`);
  }

  async create(applicationId: string, code: string, name: string, permissionIds: string[]): Promise<string> {
    const body = await this.send('POST', '/role-admin/roles', { applicationId, code, name, permissionIds });
    return body.id;
  }

  async updatePermissions(roleId: string, permissionIds: string[]): Promise<void> {
    await this.send('PUT', `/role-admin/roles/${encodeURIComponent(roleId)}/permissions`, { permissionIds });
  }

  private async get<T>(path: string): Promise<T> {
    const resp = await fetch(`${API_BASE_V2}${path}`, {
      headers: { Authorization: 'Bearer ' + this.auth.getToken() }
    });
    if (!resp.ok) {
      throw new Error((await resp.text()) || `Error ${resp.status}`);
    }
    return resp.json();
  }

  private async send(method: string, path: string, payload: unknown): Promise<any> {
    const resp = await fetch(`${API_BASE_V2}${path}`, {
      method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.auth.getToken()
      },
      body: JSON.stringify(payload)
    });
    if (!resp.ok) {
      throw new Error((await resp.text()) || `Error ${resp.status}`);
    }
    return resp.json();
  }
}
```

## `features/role-admin/role-admin.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import {
  AdminApplication, AdminPermission, AdminRole, RoleAdminService
} from '../../core/role-admin.service';

@Component({
  selector: 'app-role-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './role-admin.component.html',
  styleUrls: ['./role-admin.component.css']
})
export class RoleAdminComponent implements OnInit {

  applications: AdminApplication[] = [];
  applicationId = '';
  permissions: AdminPermission[] = [];
  roles: AdminRole[] = [];

  loading = false;
  error = '';
  message = '';

  // Création
  creating = false;
  newCode = '';
  newName = '';
  newPermissions = new Set<string>();

  // Modification des permissions d'un rôle
  editingRoleId: string | null = null;
  editPermissions = new Set<string>();

  saving = false;
  formError = '';

  constructor(private service: RoleAdminService, private router: Router) {}

  async ngOnInit(): Promise<void> {
    try {
      this.applications = await this.service.applications();
      if (this.applications.length > 0) {
        this.applicationId = this.applications[0].id;
        await this.loadApplication();
      }
    } catch (e: any) {
      this.error = e.message;
    }
  }

  back(): void {
    this.router.navigate(['/dashboard']);
  }

  async loadApplication(): Promise<void> {
    this.loading = true;
    this.error = '';
    this.closeForms();
    try {
      [this.permissions, this.roles] = await Promise.all([
        this.service.permissions(this.applicationId),
        this.service.roles(this.applicationId)
      ]);
    } catch (e: any) {
      this.error = e.message;
    } finally {
      this.loading = false;
    }
  }

  startCreate(): void {
    this.closeForms();
    this.message = '';
    this.creating = true;
  }

  startEdit(role: AdminRole): void {
    this.closeForms();
    this.message = '';
    this.editingRoleId = role.id;
    this.editPermissions = new Set(role.permissionIds);
  }

  closeForms(): void {
    this.creating = false;
    this.newCode = '';
    this.newName = '';
    this.newPermissions = new Set();
    this.editingRoleId = null;
    this.editPermissions = new Set();
    this.formError = '';
  }

  toggle(selection: Set<string>, permissionId: string): void {
    if (selection.has(permissionId)) {
      selection.delete(permissionId);
    } else {
      selection.add(permissionId);
    }
  }

  async create(): Promise<void> {
    this.saving = true;
    this.formError = '';
    try {
      const code = this.newCode.trim().toUpperCase();
      await this.service.create(this.applicationId, code, this.newName, [...this.newPermissions]);
      await this.loadApplication();
      this.message = `Role ${code} created.`;
    } catch (e: any) {
      this.formError = e.message;
    } finally {
      this.saving = false;
    }
  }

  async savePermissions(role: AdminRole): Promise<void> {
    this.saving = true;
    this.formError = '';
    try {
      await this.service.updatePermissions(role.id, [...this.editPermissions]);
      await this.loadApplication();
      this.message = `Permissions of ${role.code} updated. Users with this role get the change on their next request.`;
    } catch (e: any) {
      this.formError = e.message;
    } finally {
      this.saving = false;
    }
  }
}
```

## `features/role-admin/role-admin.component.html`

```html
<div class="page">
  <div class="page-header">
    <div>
      <h1>Roles</h1>
      <p class="subtitle">Create application roles and group the application permissions into them.</p>
    </div>
    <button type="button" class="secondary" (click)="back()">Back</button>
  </div>

  <div class="toolbar">
    <label>Application
      <select [(ngModel)]="applicationId" (ngModelChange)="loadApplication()" [disabled]="saving">
        <option *ngFor="let app of applications" [value]="app.id">{{ app.name }}</option>
      </select>
    </label>
    <button type="button" (click)="startCreate()" [disabled]="creating || loading || !applicationId">
      New role
    </button>
  </div>

  <p class="alert ko" *ngIf="error">{{ error }}</p>
  <p class="alert ok" *ngIf="message">{{ message }}</p>

  <!-- Création -->
  <div class="card" *ngIf="creating">
    <h2>New role</h2>
    <div class="fields">
      <label>Code
        <input type="text" [(ngModel)]="newCode" placeholder="FINANCING_SUPERVISOR" [disabled]="saving">
      </label>
      <label>Name
        <input type="text" [(ngModel)]="newName" placeholder="Financing supervisor" [disabled]="saving">
      </label>
    </div>
    <p class="label">Permissions</p>
    <div class="permissions">
      <label class="check" *ngFor="let p of permissions">
        <input type="checkbox" [checked]="newPermissions.has(p.id)"
               (change)="toggle(newPermissions, p.id)" [disabled]="saving">
        <span class="code">{{ p.code }}</span>
        <span class="muted">{{ p.label }}</span>
      </label>
    </div>
    <p class="alert ko" *ngIf="formError">{{ formError }}</p>
    <div class="actions">
      <button type="button" (click)="create()"
              [disabled]="saving || !newCode.trim() || !newName.trim() || newPermissions.size === 0">
        {{ saving ? 'Saving...' : 'Create role' }}
      </button>
      <button type="button" class="secondary" (click)="closeForms()" [disabled]="saving">Cancel</button>
    </div>
  </div>

  <p class="info" *ngIf="loading">Loading...</p>

  <!-- Liste des rôles -->
  <table *ngIf="!loading && roles.length > 0">
    <thead>
      <tr>
        <th>Code</th>
        <th>Name</th>
        <th>Permissions</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <ng-container *ngFor="let role of roles">
        <tr>
          <td class="code">{{ role.code }}</td>
          <td>{{ role.name }}</td>
          <td>
            <span class="chip" *ngFor="let c of role.permissionCodes">{{ c }}</span>
            <span class="muted" *ngIf="role.permissionCodes.length === 0">No permission</span>
          </td>
          <td>
            <button type="button" (click)="startEdit(role)" [disabled]="editingRoleId !== null || creating">
              Edit permissions
            </button>
          </td>
        </tr>
        <tr *ngIf="editingRoleId === role.id" class="edit-row">
          <td colspan="4">
            <div class="permissions">
              <label class="check" *ngFor="let p of permissions">
                <input type="checkbox" [checked]="editPermissions.has(p.id)"
                       (change)="toggle(editPermissions, p.id)" [disabled]="saving">
                <span class="code">{{ p.code }}</span>
                <span class="muted">{{ p.label }}</span>
              </label>
            </div>
            <p class="alert ko" *ngIf="formError">{{ formError }}</p>
            <div class="actions">
              <button type="button" (click)="savePermissions(role)"
                      [disabled]="saving || editPermissions.size === 0">
                {{ saving ? 'Saving...' : 'Save' }}
              </button>
              <button type="button" class="secondary" (click)="closeForms()" [disabled]="saving">Cancel</button>
            </div>
          </td>
        </tr>
      </ng-container>
    </tbody>
  </table>

  <p class="info" *ngIf="!loading && !error && roles.length === 0">No role for this application yet.</p>
</div>
```

## `features/role-admin/role-admin.component.css`

```css
.page {
  max-width: 1100px;
  margin: 24px auto;
  padding: 0 16px;
  font-family: system-ui, sans-serif;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
}

h1 {
  margin: 0;
  font-size: 1.4rem;
}

h2 {
  margin: 0 0 12px;
  font-size: 1.1rem;
}

.subtitle {
  margin: 4px 0 16px;
  color: #666;
}

.toolbar {
  display: flex;
  gap: 12px;
  align-items: flex-end;
  margin-bottom: 16px;
}

label {
  display: flex;
  flex-direction: column;
  font-size: 0.8rem;
  font-weight: 600;
}

input[type="text"],
select {
  margin-top: 4px;
  padding: 6px;
  min-width: 220px;
}

.card {
  border: 1px solid #ddd;
  border-radius: 6px;
  padding: 16px;
  margin-bottom: 16px;
  background: #fafafa;
}

.fields {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}

.label {
  margin: 16px 0 6px;
  font-size: 0.8rem;
  font-weight: 600;
}

.permissions {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 6px 16px;
}

label.check {
  flex-direction: row;
  align-items: center;
  gap: 8px;
  font-weight: normal;
  font-size: 0.9rem;
}

.code {
  font-family: ui-monospace, monospace;
  font-size: 0.85rem;
}

.chip {
  display: inline-block;
  margin: 2px 4px 2px 0;
  padding: 2px 8px;
  border-radius: 10px;
  background: #e6ecf8;
  font-family: ui-monospace, monospace;
  font-size: 0.8rem;
}

.muted {
  color: #888;
  font-size: 0.8rem;
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

.edit-row td {
  background: #fafafa;
}

.actions {
  display: flex;
  gap: 8px;
  margin-top: 12px;
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
import { RoleAdminComponent } from './features/role-admin/role-admin.component';

// à côté de la route users-v2, avec le même guard
{ path: 'role-admin', component: RoleAdminComponent, canActivate: [managerGuard] },
```

## Le lien, dans la barre PUMA, juste après Users

```html
<a routerLink="/users-v2">Users</a>
<a routerLink="/role-admin">Roles</a>
```

RouterLink est déjà importé dans ce composant depuis l'ajout du lien Users.

---

# Tests attendus

| Test | Attendu |
|---|---|
| Lien Roles, application Rataweb | Liste des rôles Rataweb avec leurs permissions en pastilles |
| New role : FINANCING_SUPERVISOR_2, nom, cocher contract.read et contract.approve, Create role | Message Role ... created, le rôle apparaît dans la liste avec un identifiant R suivant |
| Même code une deuxième fois | 409 A role with this code already exists for this application |
| Create role sans permission | Bouton désactivé (et 400 si appelé en curl) |
| curl POST avec une permission d'une autre application | 400 All permissions must belong to the role's application |
| Edit permissions d'un rôle, retirer une permission, Save | Liste mise à jour, l'utilisateur qui a ce rôle perd le droit tout de suite (décision PingAuthorize) |
| Le nouveau rôle dans Users, Change role | Le rôle est proposé si RoleV2Service liste les rôles globaux de l'application |

Exemple de curl, avec le token de contexte du manager :

```bash
curl -s -X POST http://localhost:8081/api/role-admin/roles \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"applicationId":"A3","code":"FINANCING_SUPERVISOR_2","name":"Financing supervisor 2","permissionIds":["P1","P2"]}'
```

# Scénario de démo (2 minutes)

1. Roles, application Rataweb : montrer les rôles existants et leurs permissions.
2. New role, cocher deux ou trois permissions Rataweb, Create role.
3. Users : donner ce nouveau rôle à X1 sur un noeud.
4. Rataweb avec X1 : l'action autorisée par le nouveau rôle passe.
5. Retour dans Roles : retirer une permission, Save. Dans Rataweb, l'action est refusée à la requête suivante, sans reconnexion.
