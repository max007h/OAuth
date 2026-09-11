# PUMA — vue d'ensemble de la hierarchie (D3)

Fenetre modale ouverte par un bouton depuis `create-user-v2`. Affiche la hierarchie
complete, avec en rouge les noeuds administres par le manager connecte.

Le `node-picker-v2` du formulaire reste inchange : cette vue est en lecture seule,
elle sert a comprendre et a montrer, pas a selectionner.

---

## Le noeud a plusieurs parents

`d3.hierarchy` exige un arbre strict : il ne sait pas representer un noeud avec deux
parents. Deux options.

**Dupliquer**, retenue ici. 9200004 ROLLER 4 est dessine deux fois, une par chain,
chaque copie portant son propre sous-arbre. Un marqueur `⧉` le signale et la legende
liste les identifiants concernes. C'est honnete, ca ne cache rien, et ca rend
l'anomalie visible en atelier.

**Un graphe en force ou un layout DAG**, ou le noeud est unique avec deux aretes
entrantes. Conceptuellement plus juste, mais illisible a cette taille et beaucoup
plus de code.

Rien a faire cote D3 pour la duplication : le JSON du backend duplique deja, sa
construction etant recursive par parent.

---

## Installation

```bash
cd banking-app
npm install d3
npm install --save-dev @types/d3
```

Puis :

```bash
ng g c features/hierarchy-map-v2 --standalone --skip-tests
```

---

## Le rouge

Deux intensites, pour distinguer deux choses differentes :

| | Signification |
|---|---|
| Rouge vif, point plus gros, gras | noeud porte par un `partnerGrant` du manager |
| Rouge clair, trait rouge | descendant de ces noeuds, donc sous son autorite |
| Gris | hors de son perimetre |

Sur ton jeu de donnees, Thomas Martin donnera 9200005 et 9200002 en rouge vif, leurs
neuf vendors en rouge clair, et tout le reste en gris. Un manager avec plusieurs
grants voit donc plusieurs branches rouges disjointes, ce qui repond a ta question :
le rouge n'est pas une seule branche, c'est l'union de ses perimetres.

---

## Backend : un endpoint a ajouter

Un seul appel rend l'arbre complet et les deux ensembles, pour ne pas avoir a
synchroniser deux reponses cote front.

```java
// ====================================================================
//  A AJOUTER dans controller/HierarchyController.java
// ====================================================================
//  Un seul endpoint pour la vue d'ensemble : l'arbre complet plus les
//  deux ensembles a mettre en rouge. En un appel, pour ne pas avoir a
//  synchroniser deux reponses cote front.

    /** Hierarchie complete + perimetre du manager, pour la vue d'ensemble. */
    @GetMapping("/map")
    public ResponseEntity<Map<String, Object>> map(JwtAuthenticationToken token) {

        if (!JwtSubject.isManager(token)) {
            return ResponseEntity.status(403).build();
        }
        String uid = JwtSubject.uid(token);

        // Noeuds portes par un partnerGrant : le point de depart de la delegation.
        List<String> granted = delegation.managerRootNodes(uid);

        // Ces noeuds plus leurs descendants : tout ce qui est sous son autorite.
        Set<String> scope = new LinkedHashSet<>(granted);
        for (String node : granted) {
            scope.addAll(hierarchy.getDescendants(node));
        }

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("roots", hierarchy.getSubtree(hierarchy.getRootIds()));
        body.put("grantedNodes", granted);
        body.put("scopeNodes", scope);
        return ResponseEntity.ok(body);
    }

// Imports a ajouter :
//   java.util.LinkedHashMap, java.util.LinkedHashSet, java.util.Map, java.util.Set


// ====================================================================
//  A AJOUTER dans service/HierarchyService.java
// ====================================================================

    /** Racines de la foret : les noeuds sans parent. Plusieurs unions existent. */
    List<String> getRootIds();


// ====================================================================
//  A AJOUTER dans service/JpaHierarchyService.java
// ====================================================================

    @Override
    public List<String> getRootIds() {
        // Un noeud est racine s'il n'apparait jamais comme enfant.
        Set<String> children = new HashSet<>();
        edges.findAll().forEach(e -> children.add(e.getNodeId()));

        return nodes.findAll().stream()
                .map(Node::getId)
                .filter(id -> !children.contains(id))
                .toList();
    }
```

---

## Integration dans create-user-v2

```typescript
// ====================================================================
//  A AJOUTER dans create-user-v2.component.ts
// ====================================================================

import { HierarchyMapV2Component } from '../hierarchy-map-v2/hierarchy-map-v2.component';

@Component({
  // ...
  imports: [CommonModule, FormsModule, NodePickerV2Component, HierarchyMapV2Component]
})
export class CreateUserV2Component implements OnInit {

  showMap = false;

  // ... le reste inchange
}


// ====================================================================
//  A AJOUTER dans create-user-v2.component.html
// ====================================================================

<!-- Le bouton, dans l'en-tete a cote de Back -->
<button type="button" class="btn-ghost" (click)="showMap = true">
  View hierarchy
</button>

<!-- La fenetre, a la toute fin du fichier -->
<app-hierarchy-map-v2 *ngIf="showMap" (closed)="showMap = false">
</app-hierarchy-map-v2>
```

---

# Code source

## `src/app/features/hierarchy-map-v2/hierarchy-map-v2.component.ts`

```typescript
import {
  AfterViewInit, Component, ElementRef, EventEmitter, OnInit, Output, ViewChild
} from '@angular/core';
import { CommonModule } from '@angular/common';
import * as d3 from 'd3';

import { AuthService } from '../../core/auth.service';
import { API_BASE_V2 } from '../../core/puma-api-v2';
import { NodeV2 } from '../../core/models/puma-v2.model';

interface HierarchyMapV2 {
  roots: NodeV2[];
  /** Noeuds portes par un partnerGrant du manager. */
  grantedNodes: string[];
  /** Ces noeuds plus tous leurs descendants. */
  scopeNodes: string[];
}

/**
 * Vue d'ensemble de la hierarchie partenaire, en D3.
 *
 * Pourquoi la duplication : d3.hierarchy exige un arbre strict, il ne sait pas
 * representer un noeud a plusieurs parents. 9200004 ROLLER 4 apparait donc deux
 * fois, une par chain, chaque copie avec son sous-arbre. Le backend produit deja
 * ce JSON duplique, D3 n'a rien de particulier a gerer.
 *
 * L'alternative serait un graphe en force ou un layout DAG, ou le noeud est unique
 * avec deux aretes entrantes. Plus juste, mais illisible a cette taille.
 */
@Component({
  selector: 'app-hierarchy-map-v2',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './hierarchy-map-v2.component.html',
  styleUrls: ['./hierarchy-map-v2.component.css']
})
export class HierarchyMapV2Component implements OnInit, AfterViewInit {

  @Output() closed = new EventEmitter<void>();
  @ViewChild('chart', { static: false }) chartRef!: ElementRef<HTMLDivElement>;

  loading = true;
  error = '';
  grantedCount = 0;
  scopeCount = 0;
  duplicatedIds: string[] = [];

  private data: HierarchyMapV2 | null = null;

  constructor(private auth: AuthService) {}

  async ngOnInit(): Promise<void> {
    try {
      const resp = await fetch(`${API_BASE_V2}/hierarchy/map`, {
        headers: { Authorization: 'Bearer ' + this.auth.getToken() }
      });
      if (!resp.ok) {
        throw new Error(`Map error ${resp.status}`);
      }
      this.data = await resp.json();
      this.grantedCount = this.data!.grantedNodes.length;
      this.scopeCount = this.data!.scopeNodes.length;
    } catch (e: any) {
      this.error = e.message;
    } finally {
      this.loading = false;
      // Le SVG ne peut etre dessine qu'une fois le *ngIf du template resolu.
      setTimeout(() => this.draw(), 0);
    }
  }

  ngAfterViewInit(): void {
    // Rien ici : le dessin est declenche apres le chargement des donnees.
  }

  close(): void {
    this.closed.emit();
  }

  private draw(): void {
    if (!this.data || !this.chartRef) {
      return;
    }

    const granted = new Set(this.data.grantedNodes);
    const scope = new Set(this.data.scopeNodes);
    const seen = new Map<string, number>();

    // Racine artificielle : le referentiel est une foret, plusieurs unions.
    const forest: NodeV2 = {
      id: '__root__', label: 'Partner hierarchy',
      level: 'UNION', duplicated: false, children: this.data.roots
    };

    const root = d3.hierarchy<NodeV2>(forest, d => d.children);

    // Compte les occurrences pour signaler les noeuds apparaissant plusieurs fois.
    root.each(d => {
      if (d.data.id !== '__root__') {
        seen.set(d.data.id, (seen.get(d.data.id) ?? 0) + 1);
      }
    });
    this.duplicatedIds = [...seen.entries()]
      .filter(([, n]) => n > 1)
      .map(([id]) => id);

    const rowHeight = 20;
    const colWidth = 190;
    const margin = { top: 20, right: 220, bottom: 20, left: 30 };

    // nodeSize plutot que size : la hauteur s'adapte au nombre de feuilles.
    const layout = d3.tree<NodeV2>().nodeSize([rowHeight, colWidth]);
    layout(root);

    const nodes = root.descendants();
    const xs = nodes.map(d => d.x!);
    const height = Math.max(...xs) - Math.min(...xs) + margin.top + margin.bottom;
    const depth = Math.max(...nodes.map(d => d.depth));
    const width = depth * colWidth + margin.left + margin.right;
    const offsetY = -Math.min(...xs) + margin.top;

    const host = d3.select(this.chartRef.nativeElement);
    host.selectAll('*').remove();

    const svg = host.append('svg')
      .attr('width', width)
      .attr('height', height)
      .attr('class', 'map-svg');

    const g = svg.append('g')
      .attr('transform', `translate(${margin.left},${offsetY})`);

    // --- liens -------------------------------------------------------------
    g.append('g')
      .selectAll('path')
      .data(root.links().filter(l => l.source.data.id !== '__root__'))
      .join('path')
      .attr('class', l => scope.has(l.target.data.id) ? 'link in-scope' : 'link')
      .attr('d', d3.linkHorizontal<any, any>()
        .x(d => d.y)
        .y(d => d.x));

    // --- noeuds ------------------------------------------------------------
    const node = g.append('g')
      .selectAll('g')
      .data(nodes.filter(d => d.data.id !== '__root__'))
      .join('g')
      .attr('transform', d => `translate(${d.y},${d.x})`);

    node.append('circle')
      .attr('r', d => granted.has(d.data.id) ? 5 : 3)
      .attr('class', d =>
        granted.has(d.data.id) ? 'dot granted'
          : scope.has(d.data.id) ? 'dot in-scope'
          : 'dot');

    node.append('text')
      .attr('dy', '0.32em')
      .attr('x', 9)
      .attr('class', d =>
        granted.has(d.data.id) ? 'label granted'
          : scope.has(d.data.id) ? 'label in-scope'
          : 'label')
      .text(d => {
        const dup = (seen.get(d.data.id) ?? 0) > 1 ? ' ⧉' : '';
        return `${d.data.label} · ${d.data.id}${dup}`;
      })
      .append('title')
      .text(d => `${d.data.level} ${d.data.id}`
        + ((seen.get(d.data.id) ?? 0) > 1
          ? ' — appears several times: this node has multiple parents'
          : ''));
  }
}
```

## `src/app/features/hierarchy-map-v2/hierarchy-map-v2.component.html`

```html
<div class="overlay" (click)="close()">

  <!-- stopPropagation : un clic dans la fenetre ne doit pas la fermer -->
  <div class="modal" (click)="$event.stopPropagation()">

    <header class="modal-head">
      <div>
        <h2>Partner hierarchy</h2>
        <p class="sub">
          Full reference hierarchy. Nodes you administer are in red.
        </p>
      </div>
      <button type="button" class="btn-close" (click)="close()">✕</button>
    </header>

    <div class="legend">
      <span class="key"><i class="dot granted"></i> Your granted nodes ({{ grantedCount }})</span>
      <span class="key"><i class="dot in-scope"></i> Within your scope ({{ scopeCount }})</span>
      <span class="key"><i class="dot"></i> Out of scope</span>
      <span class="key" *ngIf="duplicatedIds.length > 0">
        ⧉ appears several times: {{ duplicatedIds.join(', ') }}
      </span>
    </div>

    <p class="state" *ngIf="loading">Loading hierarchy…</p>
    <p class="state error" *ngIf="error">{{ error }}</p>

    <div class="chart-scroll">
      <div #chart></div>
    </div>

    <footer class="modal-foot" *ngIf="duplicatedIds.length > 0">
      A node with several parents is drawn once per parent: a tree layout cannot
      show it as a single node. Each copy carries its own subtree.
    </footer>

  </div>
</div>
```

## `src/app/features/hierarchy-map-v2/hierarchy-map-v2.component.css`

```css
.overlay {
  position: fixed;
  inset: 0;
  background: rgba(18, 22, 34, 0.55);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
  padding: 24px;
}

.modal {
  background: #fff;
  border-radius: 6px;
  width: min(1100px, 96vw);
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 12px 40px rgba(0, 0, 0, 0.28);
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

.modal-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  padding: 18px 20px 12px;
  border-bottom: 1px solid #e8ebf1;
}

.modal-head h2 {
  margin: 0;
  font-size: 1.15rem;
}

.sub {
  margin: 3px 0 0;
  font-size: 0.85rem;
  color: #5c6478;
}

.btn-close {
  border: 0;
  background: transparent;
  font-size: 1.1rem;
  cursor: pointer;
  color: #5c6478;
  padding: 2px 6px;
}

.legend {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  padding: 10px 20px;
  font-size: 0.8rem;
  color: #4a5166;
  border-bottom: 1px solid #eef0f5;
}

.key {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}

.key i.dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: #9aa2b8;
  display: inline-block;
}

.key i.dot.granted  { background: #c62828; }
.key i.dot.in-scope { background: #e88a8a; }

.chart-scroll {
  overflow: auto;
  padding: 12px 20px 20px;
  flex: 1;
}

.state {
  padding: 10px 20px;
  font-size: 0.88rem;
  color: #6b7288;
  font-style: italic;
}

.state.error {
  color: #b00020;
  font-style: normal;
}

.modal-foot {
  padding: 10px 20px 16px;
  font-size: 0.78rem;
  color: #6b7288;
  border-top: 1px solid #eef0f5;
}

/* ---- SVG : classes posees par le composant ---- */

:host ::ng-deep .link {
  fill: none;
  stroke: #ccd2de;
  stroke-width: 1;
}

:host ::ng-deep .link.in-scope {
  stroke: #c62828;
  stroke-width: 1.8;
}

:host ::ng-deep .dot {
  fill: #9aa2b8;
}

:host ::ng-deep .dot.in-scope {
  fill: #e07070;
}

:host ::ng-deep .dot.granted {
  fill: #c62828;
  stroke: #7f1414;
  stroke-width: 1.5;
}

:host ::ng-deep .label {
  font-size: 10.5px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  fill: #5c6478;
}

:host ::ng-deep .label.in-scope {
  fill: #9c2b2b;
}

:host ::ng-deep .label.granted {
  fill: #c62828;
  font-weight: 700;
}
```

---

## Verification

1. Ouvrir `/create-user-v2`, cliquer sur **View hierarchy**.
2. L'arbre doit afficher les quatre unions : 9300001 ROLLER et les trois unions
   Auto Eder, chacune avec sa descendance.
3. 9200005 ROLLER 5 et 9200002 ROLLER 2 en rouge vif, leurs neuf vendors en rouge
   clair, liens rouges.
4. 9200004 ROLLER 4 apparait deux fois, avec `⧉`, et la legende le mentionne.

Si l'arbre est vide, l'endpoint `/api/hierarchy/map` n'est pas en place ou
`getRootIds` rend une liste vide.

## Limite connue

Le rendu est statique : pas de zoom, pas de repli. Sur 40 noeuds c'est confortable.
Sur la volumetrie de production, que tu n'as pas encore, il faudra `d3.zoom` et un
repli par defaut au-dela d'une profondeur donnee. C'est une des raisons pour
lesquelles la question des volumetries reste ouverte.
