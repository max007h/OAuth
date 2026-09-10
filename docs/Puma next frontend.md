# PUMA — module create-user-v2

Module Angular autonome, ajoute **a cote** de l'existant. Aucun fichier actuel n'est
modifie, sauf une ligne de route. Tu peux revenir en arriere en supprimant le dossier
et la route.

Composants standalone, HTML et CSS dans des fichiers separes, `fetch` avec
`async/await` comme dans ton code actuel. Aucune dependance a installer : l'arbre est
ecrit en TypeScript recursif plutot qu'avec `mat-tree`, ce qui evite
`@angular/material` et `@angular/cdk` pour un seul ecran.

---

## Arborescence a creer

```
src/app/
  core/
    puma-api-v2.ts
    hierarchy-v2.service.ts
    application-v2.service.ts
    role-v2.service.ts
    provisioning-v2.service.ts
    models/
      puma-v2.model.ts
  features/
    node-picker-v2/
      node-picker-v2.component.ts
      node-picker-v2.component.html
      node-picker-v2.component.css
    create-user-v2/
      create-user-v2.component.ts
      create-user-v2.component.html
      create-user-v2.component.css
```

Commandes, si tu preferes passer par le CLI. Les fichiers generes sont ensuite a
remplacer par le contenu ci-dessous :

```bash
cd banking-app

ng g s core/hierarchy-v2 --skip-tests
ng g s core/application-v2 --skip-tests
ng g s core/role-v2 --skip-tests
ng g s core/provisioning-v2 --skip-tests

ng g c features/node-picker-v2 --standalone --skip-tests
ng g c features/create-user-v2 --standalone --skip-tests
```

Le CLI nomme les classes `HierarchyV2Service` et `NodePickerV2Component` : c'est
exactement ce qu'attend le code ci-dessous.

---

## La route

Une seule ligne a ajouter dans `app.routes.ts`, a cote de la route existante :

```typescript
import { CreateUserV2Component } from './features/create-user-v2/create-user-v2.component';

export const routes: Routes = [
  // ... routes existantes, dont create-user qui reste en place

  {
    path: 'create-user-v2',
    component: CreateUserV2Component,
    canActivate: [managerGuard]      // le guard existant, si tu veux le reutiliser
  }
];
```

Et le bouton qui y mene, apres authentification :

```html
<button (click)="router.navigate(['/create-user-v2'])">Create user (v2)</button>
```

L'ancien `/create-user` continue de fonctionner. Tu compares les deux ecrans avant
de decider lequel garder.

---

## Trois points de fonctionnement

**AuthService.** Les quatre services appellent `this.auth.getToken()`, la methode de
ton `AuthService` actuel. Si elle porte un autre nom, c'est le seul point a adapter,
et il est identique dans les quatre fichiers.

**L'ordre du formulaire.** Application, puis noeud, puis role. Le role depend du
couple application + noeud, parce que les roles sont specialises par organisation
sans heritage descendant : la liste ne peut pas etre chargee avant que le noeud soit
choisi. Changer d'application remet le noeud et le role a zero, sinon on garderait un
role valide sur l'ancien couple mais pas sur le nouveau.

**Le 403 n'est pas un bug.** Quand le backend refuse un noeud hors perimetre, le
message s'affiche dans le bandeau rouge. C'est le systeme qui fonctionne. Le front
elague l'arbre pour le confort, mais la decision est prise cote serveur : un appel
direct en curl contournerait completement l'IHM.

---

## Ce que l'ecran affiche

Bloc 1, identite, avec `portalRole` en select. Ce champ remplace l'ancien "Role" et
change de sens : il pilote l'appartenance au groupe LDAP, donc `isMemberOf`, donc
l'acces au portail. Les affectations metier viennent en plus, pas a la place.

Bloc 2, les affectations, une carte par ligne. L'arbre marque d'un `⚠ multi-parent`
tout noeud remontant sous plusieurs parents : sur ton jeu de donnees, c'est 9200004
ROLLER 4, qui apparait sous les deux chains. C'est le screenshot a emmener en
atelier.

Une fois le role choisi, les permissions effectives s'affichent en vert et celles
retirees par specialisation en rouge barre. C'est la lecture visuelle du modele
soustractif de Ping.

Bloc 3, les trois perimetres, saisis en identifiants separes par des virgules.

---

# Code source

## `core/models/puma-v2.model.ts`

Interfaces. Suffixe V2 partout, aucun conflit avec les modeles existants.

```typescript
/**
 * Modeles du module create-user-v2.
 * Suffixe V2 sur chaque interface pour ne pas heurter les modeles existants.
 */

export type NodeLevelV2 = 'UNION' | 'CHAIN' | 'REGROUPMENT' | 'VENDOR';

export interface NodeV2 {
  id: string;
  label: string;
  level: NodeLevelV2;
  /** true quand le noeud apparait sous plusieurs parents (9200004 ROLLER 4). */
  duplicated: boolean;
  children: NodeV2[];
}

export interface ApplicationV2 {
  id: string;
  name: string;
}

export interface RoleV2 {
  id: string;
  name: string;
  parentRoleId: string | null;
  nodeId: string | null;
  effectivePermissions: string[];
  removedPermissions: string[];
}

export interface AssignmentV2 {
  application: string;
  node: string;
  role: string;
}

export interface ScopesV2 {
  opScope: string[];
  opScopeExclude: string[];
  reportScope: string[];
}

export interface CreateUserRequestV2 {
  uid: string;
  firstName: string;
  lastName: string;
  email: string;
  /** COMMERCIAL ou MANAGER : acces au portail, distinct des affectations. */
  portalRole: string;
  assignments: AssignmentV2[];
  scopes: ScopesV2;
}

export interface CreateUserResponseV2 {
  message: string;
  passwordResetUrl?: string;
  instruction?: string;
  warning?: string;
}

/** Ligne du formulaire, etat local uniquement : jamais envoyee telle quelle. */
export interface AssignmentRowV2 {
  application: string;
  node: NodeV2 | null;
  nodes: NodeV2[];
  roles: RoleV2[];
  role: string;
  loadingNodes: boolean;
  loadingRoles: boolean;
  error: string;
}
```

## `core/puma-api-v2.ts`

Une constante, pour ne pas repeter l'URL dans quatre services.

```typescript
export const API_BASE_V2 = 'http://localhost:8081/api';
```

## `core/hierarchy-v2.service.ts`

Sous-arbre du manager, elague a l'application.

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';
import { NodeV2 } from './models/puma-v2.model';

@Injectable({ providedIn: 'root' })
export class HierarchyV2Service {

  constructor(private auth: AuthService) {}

  /**
   * Sous-arbre du manager connecte, elague a l'application.
   * Le backend calcule le perimetre a partir du sub du token : le front ne filtre
   * rien, un filtrage cote client serait contournable par un simple curl.
   */
  async getSubtree(applicationId?: string): Promise<NodeV2[]> {
    const query = applicationId
      ? `?application=${encodeURIComponent(applicationId)}`
      : '';

    const resp = await fetch(`${API_BASE_V2}/hierarchy/subtree${query}`, {
      headers: { Authorization: 'Bearer ' + this.auth.getToken() }
    });

    if (resp.status === 403) {
      throw new Error('Access denied: MANAGER role required.');
    }
    if (!resp.ok) {
      throw new Error(`Hierarchy error ${resp.status}`);
    }
    return resp.json();
  }
}
```

## `core/application-v2.service.ts`

Applications attribuables par le manager connecte.

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';
import { ApplicationV2 } from './models/puma-v2.model';

@Injectable({ providedIn: 'root' })
export class ApplicationV2Service {

  constructor(private auth: AuthService) {}

  /**
   * Applications que le manager peut attribuer, c'est-a-dire exposees quelque part
   * dans son sous-arbre. Premiere etape du formulaire : sans elle, il choisirait un
   * noeud puis decouvrirait qu'aucune application n'y est exposee.
   */
  async listForManager(): Promise<ApplicationV2[]> {
    const resp = await fetch(`${API_BASE_V2}/applications`, {
      headers: { Authorization: 'Bearer ' + this.auth.getToken() }
    });
    if (!resp.ok) {
      throw new Error(`Applications error ${resp.status}`);
    }
    return resp.json();
  }
}
```

## `core/role-v2.service.ts`

Roles du couple application + noeud.

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';
import { RoleV2 } from './models/puma-v2.model';

@Injectable({ providedIn: 'root' })
export class RoleV2Service {

  constructor(private auth: AuthService) {}

  /**
   * Les roles dependent du couple application + noeud. Ils sont specialises par
   * organisation et il n'y a pas d'heritage descendant, donc la liste ne peut pas
   * etre chargee avant que le noeud soit choisi.
   */
  async list(applicationId: string, nodeId: string): Promise<RoleV2[]> {
    const url = `${API_BASE_V2}/roles`
      + `?application=${encodeURIComponent(applicationId)}`
      + `&node=${encodeURIComponent(nodeId)}`;

    const resp = await fetch(url, {
      headers: { Authorization: 'Bearer ' + this.auth.getToken() }
    });
    if (!resp.ok) {
      throw new Error(`Roles error ${resp.status}`);
    }
    return resp.json();
  }
}
```

## `core/provisioning-v2.service.ts`

POST de creation. Distingue le 403 metier du 503 technique.

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';
import { CreateUserRequestV2, CreateUserResponseV2 } from './models/puma-v2.model';

@Injectable({ providedIn: 'root' })
export class ProvisioningV2Service {

  constructor(private auth: AuthService) {}

  async createUser(request: CreateUserRequestV2): Promise<CreateUserResponseV2> {
    const resp = await fetch(`${API_BASE_V2}/users`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.auth.getToken()
      },
      body: JSON.stringify(request)
    });

    const text = await resp.text();

    if (!resp.ok) {
      // 403 rend du text/plain : "Noeud hors du perimetre du manager : 2700015".
      // 503 signale un PDP injoignable, pas un refus metier. La distinction compte
      // pour l'utilisateur : dans un cas il n'a pas le droit, dans l'autre le
      // service est indisponible.
      if (resp.status === 503) {
        throw new Error('Authorization service unavailable. Nothing was created.');
      }
      throw new Error(text || `Error ${resp.status}`);
    }
    return JSON.parse(text);
  }
}
```

## `features/node-picker-v2/node-picker-v2.component.ts`

Arbre recursif, sans Angular Material.

```typescript
import { Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { NodeV2 } from '../../core/models/puma-v2.model';

/**
 * Arbre de selection de noeud, sans Angular Material.
 * Recursif par auto-reference du template : un noeud rend ses enfants avec le meme
 * composant. Sur 31 noeuds c'est largement suffisant et ca evite d'installer
 * @angular/material et @angular/cdk pour un seul ecran.
 *
 * Le composant ne charge rien lui-meme : le parent lui passe les noeuds deja
 * elagues par le backend. C'est le parent qui sait quelle application est choisie.
 */
@Component({
  selector: 'app-node-picker-v2',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './node-picker-v2.component.html',
  styleUrls: ['./node-picker-v2.component.css']
})
export class NodePickerV2Component {

  @Input() nodes: NodeV2[] = [];
  @Input() selectedId: string | null = null;

  /** Profondeur, pour l'indentation. Incremente a chaque niveau de recursion. */
  @Input() depth = 0;

  @Output() nodeSelected = new EventEmitter<NodeV2>();

  /** Noeuds replies, par identifiant. Tout est ouvert par defaut. */
  private collapsed = new Set<string>();

  isCollapsed(node: NodeV2): boolean {
    return this.collapsed.has(node.id);
  }

  toggle(node: NodeV2, event: MouseEvent): void {
    // stopPropagation : sans ca, deplier un noeud le selectionnerait aussi.
    event.stopPropagation();
    if (this.collapsed.has(node.id)) {
      this.collapsed.delete(node.id);
    } else {
      this.collapsed.add(node.id);
    }
  }

  select(node: NodeV2): void {
    this.nodeSelected.emit(node);
  }

  /** Remonte la selection d'un enfant vers le parent, sans la reinterpreter. */
  onChildSelected(node: NodeV2): void {
    this.nodeSelected.emit(node);
  }

  hasChildren(node: NodeV2): boolean {
    return !!node.children && node.children.length > 0;
  }

  levelLabel(level: string): string {
    switch (level) {
      case 'UNION':       return 'Union';
      case 'CHAIN':       return 'Chain';
      case 'REGROUPMENT': return 'Regroupment';
      case 'VENDOR':      return 'Vendor';
      default:            return level;
    }
  }
}
```

## `features/node-picker-v2/node-picker-v2.component.html`

```html
<ul class="tree" [class.tree-root]="depth === 0">

  <li *ngFor="let node of nodes" class="tree-item">

    <div class="node-row"
         [class.selected]="node.id === selectedId"
         [style.padding-left.px]="depth * 18"
         (click)="select(node)">

      <button type="button"
              class="toggle"
              *ngIf="hasChildren(node)"
              (click)="toggle(node, $event)"
              [attr.aria-label]="isCollapsed(node) ? 'Expand' : 'Collapse'">
        {{ isCollapsed(node) ? '▸' : '▾' }}
      </button>
      <span class="toggle-spacer" *ngIf="!hasChildren(node)"></span>

      <span class="badge" [attr.data-level]="node.level">
        {{ levelLabel(node.level) }}
      </span>

      <span class="label">{{ node.label }}</span>
      <span class="id">{{ node.id }}</span>

      <!-- Le noeud remonte sous plusieurs parents : il apparait donc plusieurs
           fois dans l'arbre. Cas reel de 9200004 ROLLER 4. -->
      <span class="dup"
            *ngIf="node.duplicated"
            title="This node has several parents and appears more than once">
        ⚠ multi-parent
      </span>
    </div>

    <!-- Recursion : le meme composant rend les enfants, un cran plus loin. -->
    <app-node-picker-v2
      *ngIf="hasChildren(node) && !isCollapsed(node)"
      [nodes]="node.children"
      [selectedId]="selectedId"
      [depth]="depth + 1"
      (nodeSelected)="onChildSelected($event)">
    </app-node-picker-v2>

  </li>
</ul>
```

## `features/node-picker-v2/node-picker-v2.component.css`

```css
.tree {
  list-style: none;
  margin: 0;
  padding: 0;
}

.tree-root {
  max-height: 320px;
  overflow-y: auto;
  border: 1px solid #d8dce5;
  border-radius: 4px;
  background: #fff;
  padding: 6px 0;
}

.tree-item {
  list-style: none;
}

.node-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 5px 10px;
  cursor: pointer;
  font-size: 0.9rem;
  border-left: 3px solid transparent;
}

.node-row:hover {
  background: #f2f5fa;
}

.node-row.selected {
  background: #2b3a67;
  color: #fff;
  border-left-color: #7f95d1;
}

.toggle {
  width: 18px;
  height: 18px;
  padding: 0;
  border: 0;
  background: transparent;
  cursor: pointer;
  color: inherit;
  font-size: 0.8rem;
  line-height: 1;
}

.toggle-spacer {
  display: inline-block;
  width: 18px;
}

.badge {
  font-size: 0.66rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  padding: 2px 6px;
  border-radius: 3px;
  background: #e6eaf2;
  color: #48506b;
  white-space: nowrap;
}

.node-row.selected .badge {
  background: rgba(255, 255, 255, 0.22);
  color: #fff;
}

/* Un ton par niveau : l'oeil situe la profondeur sans compter l'indentation. */
.badge[data-level="UNION"]       { background: #d9e4f5; color: #23406e; }
.badge[data-level="CHAIN"]       { background: #dcece0; color: #24583a; }
.badge[data-level="REGROUPMENT"] { background: #f6e6cc; color: #6d4a11; }
.badge[data-level="VENDOR"]      { background: #ece6f5; color: #4b2d75; }

.label {
  font-weight: 500;
}

.id {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.78rem;
  opacity: 0.65;
}

.dup {
  font-size: 0.72rem;
  color: #8a5b00;
  background: #fff4d6;
  padding: 1px 6px;
  border-radius: 3px;
  white-space: nowrap;
}

.node-row.selected .dup {
  background: rgba(255, 255, 255, 0.22);
  color: #ffe9b0;
}
```

## `features/create-user-v2/create-user-v2.component.ts`

Le formulaire : application, puis noeud, puis role.

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { NodePickerV2Component } from '../node-picker-v2/node-picker-v2.component';
import { HierarchyV2Service } from '../../core/hierarchy-v2.service';
import { ApplicationV2Service } from '../../core/application-v2.service';
import { RoleV2Service } from '../../core/role-v2.service';
import { ProvisioningV2Service } from '../../core/provisioning-v2.service';
import {
  ApplicationV2, AssignmentRowV2, CreateUserRequestV2, NodeV2
} from '../../core/models/puma-v2.model';

/**
 * Ecran de creation d'utilisateur partenaire, version 2.
 *
 * Ordre impose par le metier : APPLICATION, puis NOEUD, puis ROLE.
 *  - l'application d'abord : c'est ainsi que le manager raisonne, et elle permet
 *    d'elaguer l'arbre aux seuls noeuds qui l'exposent
 *  - le role en dernier : il depend du couple application + noeud, les roles etant
 *    specialises par organisation sans heritage descendant
 *
 * Deux dimensions distinctes et non interchangeables :
 *  - portalRole (COMMERCIAL / MANAGER) : groupe LDAP, donc isMemberOf, donc acces
 *    au portail. Controle coarse-grained.
 *  - assignments + scopes : droits sur les noeuds. Controle fine-grained, rendu
 *    par le PDP cote backend.
 */
@Component({
  selector: 'app-create-user-v2',
  standalone: true,
  imports: [CommonModule, FormsModule, NodePickerV2Component],
  templateUrl: './create-user-v2.component.html',
  styleUrls: ['./create-user-v2.component.css']
})
export class CreateUserV2Component implements OnInit {

  identity = { uid: '', firstName: '', lastName: '', email: '' };
  portalRole = 'COMMERCIAL';

  applications: ApplicationV2[] = [];
  rows: AssignmentRowV2[] = [this.emptyRow()];

  /** Saisis en texte libre, separes par des virgules, decoupes a la soumission. */
  opScopeRaw = '';
  opScopeExcludeRaw = '';
  reportScopeRaw = '';

  loadingApplications = false;
  submitting = false;
  successMessage = '';
  warningMessage = '';
  resetUrl = '';
  errorMessage = '';

  constructor(private hierarchy: HierarchyV2Service,
              private applicationService: ApplicationV2Service,
              private roleService: RoleV2Service,
              private provisioning: ProvisioningV2Service,
              private router: Router) {}

  /** Le catalogue ne depend pas de la ligne : une seule fois au chargement. */
  async ngOnInit(): Promise<void> {
    this.loadingApplications = true;
    try {
      this.applications = await this.applicationService.listForManager();
      if (this.applications.length === 0) {
        this.errorMessage =
          'No application is available in your scope. Check that your account '
          + 'carries partnerGrant values matching the loaded hierarchy.';
      }
    } catch (e: any) {
      this.errorMessage = e.message;
    } finally {
      this.loadingApplications = false;
    }
  }

  emptyRow(): AssignmentRowV2 {
    return {
      application: '',
      node: null,
      nodes: [],
      roles: [],
      role: '',
      loadingNodes: false,
      loadingRoles: false,
      error: ''
    };
  }

  addRow(): void {
    this.rows.push(this.emptyRow());
  }

  removeRow(index: number): void {
    this.rows.splice(index, 1);
  }

  /**
   * Changer d'application invalide le noeud et le role : l'arbre elague change,
   * et un role valide sur l'ancien couple ne l'est pas forcement sur le nouveau.
   */
  async onApplicationChange(row: AssignmentRowV2): Promise<void> {
    row.node = null;
    row.role = '';
    row.roles = [];
    row.nodes = [];
    row.error = '';

    if (!row.application) {
      return;
    }

    row.loadingNodes = true;
    try {
      row.nodes = await this.hierarchy.getSubtree(row.application);
      if (row.nodes.length === 0) {
        row.error = 'No node in your scope exposes this application.';
      }
    } catch (e: any) {
      row.error = e.message;
    } finally {
      row.loadingNodes = false;
    }
  }

  async onNodeSelected(row: AssignmentRowV2, node: NodeV2): Promise<void> {
    row.node = node;
    row.role = '';
    row.roles = [];
    row.error = '';

    row.loadingRoles = true;
    try {
      row.roles = await this.roleService.list(row.application, node.id);
      if (row.roles.length === 0) {
        row.error = 'No role defined for this application on this node.';
      }
    } catch (e: any) {
      row.error = e.message;
    } finally {
      row.loadingRoles = false;
    }
  }

  /** Affiche les permissions effectives du role choisi, en lecture seule. */
  selectedRolePermissions(row: AssignmentRowV2): string[] {
    const role = row.roles.find(r => r.id === row.role);
    return role ? role.effectivePermissions : [];
  }

  selectedRoleRemoved(row: AssignmentRowV2): string[] {
    const role = row.roles.find(r => r.id === row.role);
    return role ? role.removedPermissions : [];
  }

  private split(raw: string): string[] {
    return raw.split(',').map(v => v.trim()).filter(v => v.length > 0);
  }

  get completeAssignments() {
    return this.rows
      .filter(r => r.application && r.node && r.role)
      .map(r => ({ application: r.application, node: r.node!.id, role: r.role }));
  }

  get canSubmit(): boolean {
    return !this.submitting
      && !!this.identity.uid
      && !!this.identity.firstName
      && !!this.identity.lastName
      && !!this.identity.email
      && this.completeAssignments.length > 0;
  }

  async submit(): Promise<void> {
    this.submitting = true;
    this.successMessage = '';
    this.warningMessage = '';
    this.resetUrl = '';
    this.errorMessage = '';

    const request: CreateUserRequestV2 = {
      ...this.identity,
      portalRole: this.portalRole,
      assignments: this.completeAssignments,
      scopes: {
        opScope: this.split(this.opScopeRaw),
        opScopeExclude: this.split(this.opScopeExcludeRaw),
        reportScope: this.split(this.reportScopeRaw)
      }
    };

    try {
      const response = await this.provisioning.createUser(request);
      this.successMessage = response.message;
      this.warningMessage = response.warning ?? '';
      this.resetUrl = response.passwordResetUrl ?? '';
    } catch (e: any) {
      // Un 403 arrive ici : le backend a refuse un noeud hors perimetre. C'est
      // une reponse normale du systeme, pas un bug du formulaire.
      this.errorMessage = e.message;
    } finally {
      this.submitting = false;
    }
  }

  reset(): void {
    this.identity = { uid: '', firstName: '', lastName: '', email: '' };
    this.portalRole = 'COMMERCIAL';
    this.rows = [this.emptyRow()];
    this.opScopeRaw = '';
    this.opScopeExcludeRaw = '';
    this.reportScopeRaw = '';
    this.successMessage = '';
    this.warningMessage = '';
    this.resetUrl = '';
    this.errorMessage = '';
  }

  back(): void {
    this.router.navigate(['/dashboard']);
  }
}
```

## `features/create-user-v2/create-user-v2.component.html`

```html
<div class="page">

  <header class="page-header">
    <div>
      <h1>Create partner user</h1>
      <p class="subtitle">
        Provision a user in PingDirectory and grant assignments on the partner
        hierarchy.
      </p>
    </div>
    <button type="button" class="btn-ghost" (click)="back()">← Back</button>
  </header>

  <!-- ============================ IDENTITE ============================ -->
  <section class="card">
    <h2><span class="step">1</span> Identity</h2>

    <div class="grid-2">
      <label>
        Login (uid)
        <input type="text" name="uid" placeholder="jean.dupont"
               [(ngModel)]="identity.uid">
      </label>

      <label>
        Email
        <input type="email" name="email" placeholder="jean.dupont@example.com"
               [(ngModel)]="identity.email">
      </label>

      <label>
        First name
        <input type="text" name="firstName" placeholder="Jean"
               [(ngModel)]="identity.firstName">
      </label>

      <label>
        Last name
        <input type="text" name="lastName" placeholder="Dupont"
               [(ngModel)]="identity.lastName">
      </label>
    </div>

    <label class="portal-role">
      Portal access
      <select name="portalRole" [(ngModel)]="portalRole">
        <option value="COMMERCIAL">Commercial</option>
        <option value="MANAGER">Manager</option>
      </select>
      <small>
        LDAP group membership. Drives access to PUMA itself, not the business
        permissions below.
      </small>
    </label>
  </section>

  <!-- =========================== AFFECTATIONS ========================== -->
  <section class="card">
    <h2><span class="step">2</span> Assignments</h2>
    <p class="hint">
      Pick an application, then a node in your scope, then a role. The role list
      depends on both: roles are specialised per organisation.
    </p>

    <p class="loading" *ngIf="loadingApplications">Loading applications…</p>

    <div class="assignment" *ngFor="let row of rows; let i = index">

      <div class="assignment-head">
        <span class="assignment-index">Assignment {{ i + 1 }}</span>
        <button type="button" class="btn-remove"
                (click)="removeRow(i)"
                [disabled]="rows.length === 1">Remove</button>
      </div>

      <!-- Etape a : application -->
      <label class="field">
        <span class="field-label">a. Application</span>
        <select [(ngModel)]="row.application"
                name="application-{{ i }}"
                (ngModelChange)="onApplicationChange(row)">
          <option value="">Select an application…</option>
          <option *ngFor="let app of applications" [value]="app.id">
            {{ app.name }}
          </option>
        </select>
      </label>

      <!-- Etape b : noeud -->
      <div class="field">
        <span class="field-label">b. Node</span>

        <p class="placeholder" *ngIf="!row.application">
          Select an application first.
        </p>
        <p class="loading" *ngIf="row.loadingNodes">Loading hierarchy…</p>

        <app-node-picker-v2
          *ngIf="row.application && !row.loadingNodes && row.nodes.length > 0"
          [nodes]="row.nodes"
          [selectedId]="row.node?.id ?? null"
          (nodeSelected)="onNodeSelected(row, $event)">
        </app-node-picker-v2>

        <p class="chosen" *ngIf="row.node">
          Selected: <strong>{{ row.node.label }}</strong>
          <code>{{ row.node.id }}</code>
          <span class="chip">{{ row.node.level }}</span>
        </p>
      </div>

      <!-- Etape c : role -->
      <label class="field">
        <span class="field-label">c. Role</span>
        <select [(ngModel)]="row.role"
                name="role-{{ i }}"
                [disabled]="!row.node || row.loadingRoles">
          <option value="">
            {{ row.loadingRoles ? 'Loading roles…' : 'Select a role…' }}
          </option>
          <option *ngFor="let role of row.roles" [value]="role.id">
            {{ role.name }}
          </option>
        </select>
      </label>

      <!-- Lecture seule : ce que le role accorde reellement une fois specialise -->
      <div class="permissions" *ngIf="row.role">
        <div class="perm-block">
          <span class="perm-title">Effective permissions</span>
          <span class="perm-tag granted"
                *ngFor="let p of selectedRolePermissions(row)">{{ p }}</span>
        </div>
        <div class="perm-block" *ngIf="selectedRoleRemoved(row).length > 0">
          <span class="perm-title">Removed by specialisation</span>
          <span class="perm-tag removed"
                *ngFor="let p of selectedRoleRemoved(row)">{{ p }}</span>
        </div>
      </div>

      <p class="row-error" *ngIf="row.error">{{ row.error }}</p>
    </div>

    <button type="button" class="btn-secondary" (click)="addRow()">
      + Add assignment
    </button>
  </section>

  <!-- ============================= SCOPES ============================= -->
  <section class="card">
    <h2><span class="step">3</span> Scopes</h2>
    <p class="hint">
      Comma-separated node identifiers. Exclusions take precedence over the
      operational scope. Reporting is often granted at a higher level.
    </p>

    <label class="field">
      <span class="field-label">Operational (opScope)</span>
      <input type="text" name="opScope" placeholder="2700010, 2700011"
             [(ngModel)]="opScopeRaw">
    </label>

    <label class="field">
      <span class="field-label">Excluded (opScopeExclude)</span>
      <input type="text" name="opScopeExclude" placeholder="2700012"
             [(ngModel)]="opScopeExcludeRaw">
    </label>

    <label class="field">
      <span class="field-label">Reporting (reportScope)</span>
      <input type="text" name="reportScope" placeholder="9200005"
             [(ngModel)]="reportScopeRaw">
    </label>
  </section>

  <!-- ============================ ACTIONS ============================= -->
  <div class="actions">
    <button type="button" class="btn-primary"
            (click)="submit()" [disabled]="!canSubmit">
      {{ submitting ? 'Creating…' : 'Create user' }}
    </button>
    <button type="button" class="btn-ghost" (click)="reset()">Reset</button>
  </div>

  <!-- ============================ RETOURS ============================= -->
  <div class="alert ok" *ngIf="successMessage">
    <strong>{{ successMessage }}</strong>
    <p *ngIf="resetUrl">
      Password initialisation link:
      <a [href]="resetUrl" target="_blank" rel="noopener">{{ resetUrl }}</a>
    </p>
  </div>

  <div class="alert warn" *ngIf="warningMessage">{{ warningMessage }}</div>
  <div class="alert ko" *ngIf="errorMessage">{{ errorMessage }}</div>

</div>
```

## `features/create-user-v2/create-user-v2.component.css`

```css
.page {
  max-width: 860px;
  margin: 24px auto 60px;
  padding: 0 16px;
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  color: #1c2233;
}

/* ------------------------------- header ------------------------------- */

.page-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 20px;
}

.page-header h1 {
  margin: 0;
  font-size: 1.5rem;
}

.subtitle {
  margin: 4px 0 0;
  color: #5c6478;
  font-size: 0.9rem;
}

/* -------------------------------- cards ------------------------------- */

.card {
  background: #fff;
  border: 1px solid #e2e6ee;
  border-radius: 6px;
  padding: 20px;
  margin-bottom: 18px;
}

.card h2 {
  display: flex;
  align-items: center;
  gap: 10px;
  margin: 0 0 4px;
  font-size: 1.05rem;
}

.step {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: #2b3a67;
  color: #fff;
  font-size: 0.82rem;
}

.hint {
  margin: 0 0 16px;
  color: #5c6478;
  font-size: 0.85rem;
}

/* -------------------------------- champs ------------------------------ */

.grid-2 {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}

label {
  display: block;
  font-size: 0.85rem;
  font-weight: 600;
}

input,
select {
  display: block;
  width: 100%;
  margin-top: 5px;
  padding: 9px 10px;
  border: 1px solid #ccd2de;
  border-radius: 4px;
  font-size: 0.92rem;
  font-family: inherit;
  font-weight: 400;
  background: #fff;
  box-sizing: border-box;
}

input:focus,
select:focus {
  outline: none;
  border-color: #2b3a67;
  box-shadow: 0 0 0 2px rgba(43, 58, 103, 0.12);
}

select:disabled {
  background: #f3f4f7;
  color: #8b91a1;
}

.portal-role {
  margin-top: 16px;
}

.portal-role small {
  display: block;
  margin-top: 5px;
  font-weight: 400;
  color: #5c6478;
  font-size: 0.78rem;
}

.field {
  margin-bottom: 14px;
}

.field-label {
  display: block;
  margin-bottom: 5px;
  font-size: 0.82rem;
  font-weight: 600;
  color: #3a4257;
}

/* ----------------------------- affectations --------------------------- */

.assignment {
  border: 1px solid #e6e9f0;
  border-left: 3px solid #2b3a67;
  border-radius: 4px;
  padding: 16px;
  margin-bottom: 14px;
  background: #fafbfd;
}

.assignment-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}

.assignment-index {
  font-size: 0.78rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #6b7288;
  font-weight: 600;
}

.chosen {
  margin: 8px 0 0;
  font-size: 0.85rem;
}

.chosen code {
  margin: 0 6px;
  padding: 1px 5px;
  background: #eef1f6;
  border-radius: 3px;
  font-size: 0.8rem;
}

.chip {
  font-size: 0.68rem;
  text-transform: uppercase;
  padding: 2px 6px;
  border-radius: 3px;
  background: #e6eaf2;
  color: #48506b;
}

/* ------------------------------ permissions --------------------------- */

.permissions {
  margin-top: 10px;
  padding: 10px 12px;
  background: #fff;
  border: 1px dashed #d8dce5;
  border-radius: 4px;
}

.perm-block + .perm-block {
  margin-top: 8px;
}

.perm-title {
  display: block;
  margin-bottom: 5px;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #6b7288;
  font-weight: 600;
}

.perm-tag {
  display: inline-block;
  margin: 0 5px 5px 0;
  padding: 2px 7px;
  border-radius: 3px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.75rem;
}

.perm-tag.granted {
  background: #e4f0e6;
  color: #24583a;
}

/* Retire par specialisation : barre, car le role generique le portait. */
.perm-tag.removed {
  background: #f7e2e2;
  color: #8a2020;
  text-decoration: line-through;
}

/* -------------------------------- boutons ----------------------------- */

.actions {
  display: flex;
  gap: 10px;
  align-items: center;
}

.btn-primary,
.btn-secondary,
.btn-ghost,
.btn-remove {
  font-family: inherit;
  font-size: 0.9rem;
  border-radius: 4px;
  cursor: pointer;
}

.btn-primary {
  flex: 1;
  padding: 12px 18px;
  border: 0;
  background: #2b3a67;
  color: #fff;
  font-weight: 600;
}

.btn-primary:disabled {
  background: #aeb4c4;
  cursor: not-allowed;
}

.btn-secondary {
  padding: 8px 14px;
  border: 1px dashed #9aa2b8;
  background: #fff;
  color: #2b3a67;
}

.btn-ghost {
  padding: 10px 16px;
  border: 1px solid #ccd2de;
  background: #fff;
  color: #3a4257;
}

.btn-remove {
  padding: 4px 10px;
  border: 1px solid #e0c4c4;
  background: #fff;
  color: #8a2020;
  font-size: 0.78rem;
}

.btn-remove:disabled {
  border-color: #e6e9f0;
  color: #b5bac7;
  cursor: not-allowed;
}

/* -------------------------------- etats ------------------------------- */

.loading,
.placeholder {
  margin: 6px 0;
  font-size: 0.85rem;
  color: #6b7288;
  font-style: italic;
}

.row-error {
  margin: 8px 0 0;
  font-size: 0.85rem;
  color: #8a2020;
}

.alert {
  margin-top: 16px;
  padding: 12px 14px;
  border-radius: 4px;
  font-size: 0.9rem;
  border-left: 3px solid;
}

.alert p {
  margin: 6px 0 0;
}

.alert.ok {
  background: #e9f4ec;
  border-color: #2e7d4f;
  color: #1b5e20;
}

.alert.warn {
  background: #fdf4e3;
  border-color: #c78a1a;
  color: #7a5410;
}

.alert.ko {
  background: #fbeaea;
  border-color: #b00020;
  color: #8a1020;
}

.alert a {
  color: inherit;
  word-break: break-all;
}

@media (max-width: 640px) {
  .grid-2 {
    grid-template-columns: 1fr;
  }
}
```

---

## Verification apres integration

1. `ng serve`, puis authentification, puis le bouton vers `/create-user-v2`.
2. Le select Application doit proposer Contract Management et Reporting Portal.
   S'il est vide, le compte connecte n'a pas de `partnerGrant` correspondant a la
   hierarchie chargee.
3. Choisir Contract Management : l'arbre doit afficher ROLLER 5 avec ses six
   vendors et ROLLER 2 avec ses trois. Pas ROLLER 6.
4. Choisir 2700010, puis un role, puis creer. Attendu : bandeau vert.
5. Le test qui compte : refaire avec un noeud hors perimetre. Le backend rend un
   403 et le bandeau rouge affiche `Noeud hors du perimetre du manager`.

Le point 5 n'est pas atteignable depuis l'IHM, puisque l'arbre est deja elague.
C'est voulu : pour le demontrer, il faut passer par curl, ce qui prouve justement
que la protection ne depend pas du front.
