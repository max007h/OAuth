# PUMA : choix du contexte après authentification

Objectif : juste après le login, une pop-up propose au manager la liste des noeuds sur lesquels il a des droits. Il en choisit un. Le backend demande alors à PingFederate un nouveau token (token exchange) qui contient `sub`, `node` et `roles`.

Ce qui est déjà fait côté PingFederate : client `puma-backend`, processeur, Processor Policy, data store `puma-postgres`, mapping avec `roles` lus en base et Issuance Criteria `node_not_assigned`.

Ordre : base, backend, frontend.

---

## 0. Base de données

Une seule vue, utilisée à la fois par PingFederate et par le backend. Chaque rôle d'un assignment est propagé à tous les descendants du noeud. Ajouter à la fin de `schema.sql` :

```sql
CREATE OR REPLACE VIEW puma_user_node_roles AS
WITH RECURSIVE scope AS (
    SELECT a.user_id, a.role_id, a.node_id
    FROM assignment a
  UNION
    SELECT s.user_id, s.role_id, np.node_id
    FROM scope s
    JOIN node_parent np ON np.parent_id = s.node_id
)
SELECT DISTINCT u.uid, s.node_id, COALESCE(r.parent_role_id, r.id) AS role_id
FROM scope s
JOIN puma_user u ON u.id = s.user_id
JOIN app_role r  ON r.id = s.role_id
WHERE u.status = 'ACTIVE';
```

A vérifier avant : les colonnes de `node_parent` s'appellent bien `node_id` et `parent_id`.

Contrôle :

```sql
SELECT * FROM puma_user_node_roles WHERE uid = 'thomas.martin';
```

On doit voir 9200005 et 9200002, plus leurs descendants (dont 2700010 avec R1 et R4).

---

## 1. Backend

### 1.1 `application.yml`

```yaml
puma:
  pingfederate:
    token-url: https://localhost:9031/as/token.oauth2
    client-id: ${PUMA_PF_CLIENT_ID:puma-backend}
    client-secret: ${PUMA_PF_CLIENT_SECRET}
  jwt:
    secret-hex: ${PUMA_JWT_SECRET_HEX}
```

Les deux secrets se déclarent en variables d'environnement dans la configuration de lancement IntelliJ. Le client `puma-portal` (SPA) n'a rien à faire ici.

### 1.2 `config/PingFederateProperties.java`

```java
package com.poc.banking.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "puma.pingfederate")
public record PingFederateProperties(String tokenUrl, String clientId, String clientSecret) {}
```

Ajouter `@ConfigurationPropertiesScan` sur `DemoApplication`.

### 1.3 DTO (package `dto`)

```java
public record NodeContextDto(String nodeId, String label) {}
```

```java
public record SelectContextRequest(
        @NotBlank @Pattern(regexp = "^[A-Za-z0-9_-]{1,20}$") String nodeId) {}
```

```java
public record TokenResponse(@JsonProperty("access_token") String accessToken) {}
```

`spring-boot-starter-validation` doit être présent dans le `pom.xml`.

### 1.4 Exceptions (package `exception`)

```java
public class ContextForbiddenException extends RuntimeException {
    public ContextForbiddenException() { super("Context not allowed"); }
}
```

```java
public class TokenExchangeException extends RuntimeException {
    public TokenExchangeException(String message, Throwable cause) { super(message, cause); }
}
```

### 1.5 Repository : ajout dans `AssignmentRepository`

```java
interface NodeContextView {
    String getNodeId();
    String getLabel();
}

@Query(value = """
    SELECT DISTINCT v.node_id AS "nodeId", n.label AS "label"
    FROM puma_user_node_roles v
    JOIN node n ON n.id = v.node_id
    WHERE v.uid = :uid
    ORDER BY v.node_id
    """, nativeQuery = true)
List<NodeContextView> findContextNodes(@Param("uid") String uid);
```

La pop-up lit la même vue que PingFederate : ce qui est proposé est forcément accepté.

### 1.6 `PingFederateService` : ajout d'une méthode

Injecter `PingFederateProperties properties`, le `RestTemplate` déjà utilisé (celui qui accepte le certificat auto-signé) et un `ObjectMapper`.

```java
public String exchangeToken(String subjectToken, String nodeId) {
    MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
    form.add("grant_type", "urn:ietf:params:oauth:grant-type:token-exchange");
    form.add("subject_token", subjectToken);
    form.add("subject_token_type", "urn:ietf:params:oauth:token-type:access_token");
    form.add("node", nodeId);

    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_FORM_URLENCODED);
    headers.setBasicAuth(properties.clientId(), properties.clientSecret());

    try {
        String body = restTemplate.postForObject(properties.tokenUrl(),
                new HttpEntity<>(form, headers), String.class);
        return objectMapper.readTree(body).path("access_token").asText();
    } catch (HttpClientErrorException e) {
        if (e.getResponseBodyAsString().contains("node_not_assigned")) {
            throw new ContextForbiddenException();
        }
        throw new TokenExchangeException("Token exchange rejected", e);
    } catch (RestClientException | JsonProcessingException e) {
        throw new TokenExchangeException("Token exchange failed", e);
    }
}
```

### 1.7 `service/UserContextService.java`

```java
@Service
@Transactional(readOnly = true)
public class UserContextService {

    private final AssignmentRepository assignmentRepository;
    private final PingFederateService pingFederateService;

    public UserContextService(AssignmentRepository assignmentRepository,
                              PingFederateService pingFederateService) {
        this.assignmentRepository = assignmentRepository;
        this.pingFederateService = pingFederateService;
    }

    public List<NodeContextDto> getContextNodes(String uid) {
        return assignmentRepository.findContextNodes(uid.toLowerCase(Locale.ROOT)).stream()
                .map(v -> new NodeContextDto(v.getNodeId(), v.getLabel()))
                .toList();
    }

    public String selectContext(String subjectToken, String nodeId) {
        return pingFederateService.exchangeToken(subjectToken, nodeId);
    }
}
```

Pas de contrôle du noeud ici : PingFederate le fait déjà (Issuance Criteria).

### 1.8 `controller/ContextController.java`

```java
@RestController
@RequestMapping("/api/contexts")
public class ContextController {

    private final UserContextService userContextService;
    private final JwtClaimsExtractor claims;

    public ContextController(UserContextService userContextService, JwtClaimsExtractor claims) {
        this.userContextService = userContextService;
        this.claims = claims;
    }

    @GetMapping("/nodes")
    public List<NodeContextDto> nodes(@AuthenticationPrincipal Jwt jwt) {
        return userContextService.getContextNodes(claims.getSub(jwt));
    }

    @PostMapping("/select")
    public TokenResponse select(@AuthenticationPrincipal Jwt jwt,
                                @Valid @RequestBody SelectContextRequest request) {
        return new TokenResponse(
                userContextService.selectContext(jwt.getTokenValue(), request.nodeId()));
    }
}
```

### 1.9 `config/ContextExceptionHandler.java`

```java
@RestControllerAdvice
public class ContextExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ContextExceptionHandler.class);

    @ExceptionHandler(ContextForbiddenException.class)
    public ResponseEntity<Map<String, String>> forbidden() {
        return ResponseEntity.status(HttpStatus.FORBIDDEN).body(Map.of(
                "error", "context_forbidden",
                "message", "You have no rights on this business entity."));
    }

    @ExceptionHandler(TokenExchangeException.class)
    public ResponseEntity<Map<String, String>> exchangeFailed(TokenExchangeException e) {
        log.error("Token exchange failed", e);
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of(
                "error", "token_exchange_failed",
                "message", "Service temporarily unavailable, please retry."));
    }
}
```

### 1.10 `SecurityConfig` : vérifier la signature

Remplacer le `jwtDecoder()` actuel (qui parse sans vérifier) :

```java
@Bean
public JwtDecoder jwtDecoder(@Value("${puma.jwt.secret-hex}") String secretHex) {
    SecretKey key = new SecretKeySpec(HexFormat.of().parseHex(secretHex), "HmacSHA256");
    return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
}
```

`PUMA_JWT_SECRET_HEX` = la valeur hex de `poc-key` dans PingFederate. Vérifier que `/api/contexts/**` est en `authenticated()`.

### 1.11 `JwtClaimsExtractor` : pour les écrans métier

```java
public String getNode(Jwt jwt) {
    return jwt.getClaimAsString("node");
}

public List<String> getRoles(Jwt jwt) {
    List<String> roles = jwt.getClaimAsStringList("roles");
    return roles != null ? roles : List.of();
}
```

Dans `UserController.createUser` : refuser (403) si `getNode(jwt)` est null.

### 1.12 Tests backend

```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8081/api/contexts/nodes

curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"nodeId":"2700010"}' http://localhost:8081/api/contexts/select

curl -s -o /dev/null -w "%{http_code}\n" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -d '{"nodeId":"2700015"}' \
  http://localhost:8081/api/contexts/select
```

Attendus : la liste des noeuds, puis un token avec `node: 2700010` et `roles: ["R1","R4"]`, puis `403`.

---

## 2. Frontend

Trois fichiers de composant, un service, une interface, une méthode dans `AuthService`, une ligne dans le dashboard.

### 2.1 Modèle : ajout dans `core/models/puma-v2.model.ts`

```typescript
export interface NodeContextV2 {
  nodeId: string;
  label: string;
}
```

### 2.2 `AuthService` : ajout d'une méthode

Elle doit écrire au même endroit que celui où `getToken()` lit. Exemple si c'est `sessionStorage` :

```typescript
setToken(token: string): void {
  sessionStorage.setItem('access_token', token);
}
```

### 2.3 `core/context-v2.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { API_BASE_V2 } from './puma-api-v2';
import { NodeContextV2 } from './models/puma-v2.model';

@Injectable({ providedIn: 'root' })
export class ContextV2Service {

  constructor(private auth: AuthService) {}

  async listNodes(): Promise<NodeContextV2[]> {
    const resp = await fetch(`${API_BASE_V2}/contexts/nodes`, {
      headers: { Authorization: 'Bearer ' + this.auth.getToken() }
    });
    if (!resp.ok) {
      throw new Error(`Contexts error ${resp.status}`);
    }
    return resp.json();
  }

  async select(nodeId: string): Promise<void> {
    const resp = await fetch(`${API_BASE_V2}/contexts/select`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.auth.getToken()
      },
      body: JSON.stringify({ nodeId })
    });
    const body = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      throw new Error(body.message ?? `Error ${resp.status}`);
    }
    this.auth.setToken(body.access_token);
  }

  /** Affichage uniquement : la vraie verification est cote serveur. */
  hasContext(): boolean {
    const token = this.auth.getToken();
    if (!token) {
      return false;
    }
    try {
      const part = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      return !!JSON.parse(atob(part)).node;
    } catch {
      return false;
    }
  }
}
```

### 2.4 `features/context-picker-v2/context-picker-v2.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ContextV2Service } from '../../core/context-v2.service';
import { NodeContextV2 } from '../../core/models/puma-v2.model';

@Component({
  selector: 'app-context-picker-v2',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './context-picker-v2.component.html',
  styleUrls: ['./context-picker-v2.component.css']
})
export class ContextPickerV2Component implements OnInit {

  visible = false;
  nodes: NodeContextV2[] = [];
  selected = '';
  busy = false;
  error = '';

  constructor(private contextService: ContextV2Service) {}

  async ngOnInit(): Promise<void> {
    if (this.contextService.hasContext()) {
      return;
    }
    this.visible = true;
    try {
      this.nodes = await this.contextService.listNodes();
      if (this.nodes.length === 0) {
        this.error = 'No business entity is assigned to your account.';
      }
    } catch (e: any) {
      this.error = e.message;
    }
  }

  async confirm(): Promise<void> {
    this.busy = true;
    this.error = '';
    try {
      await this.contextService.select(this.selected);
      this.visible = false;
    } catch (e: any) {
      this.error = e.message;
    } finally {
      this.busy = false;
    }
  }
}
```

### 2.5 `context-picker-v2.component.html`

```html
<div class="overlay" *ngIf="visible">
  <div class="dialog">
    <h2>Select your business entity</h2>

    <select [(ngModel)]="selected" name="context">
      <option value="">Choose...</option>
      <option *ngFor="let n of nodes" [value]="n.nodeId">
        {{ n.label }} ({{ n.nodeId }})
      </option>
    </select>

    <p class="error" *ngIf="error">{{ error }}</p>

    <button type="button" (click)="confirm()" [disabled]="!selected || busy">
      Continue
    </button>
  </div>
</div>
```

### 2.6 `context-picker-v2.component.css`

```css
.overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
  display: flex;
  align-items: center;
  justify-content: center;
}

.dialog {
  width: 340px;
  background: #fff;
  padding: 20px;
  border-radius: 6px;
}

select,
button {
  width: 100%;
  padding: 8px;
  margin-top: 12px;
}

.error {
  color: #b00020;
}
```

### 2.7 Branchement dans le dashboard

Dans `dashboard.component.ts`, ajouter `ContextPickerV2Component` au tableau `imports`. En haut de `dashboard.component.html` :

```html
<app-context-picker-v2></app-context-picker-v2>
```

### 2.8 Tests frontend

1. Login avec thomas.martin : la pop-up s'affiche.
2. Choisir 2700010 : la pop-up se ferme, le token stocké contient `node` et `roles`.
3. Rafraîchir la page : la pop-up ne revient pas.

---

## 3. Faut-il appeler PingAuthorize au moment du choix ?

Non. Au moment du choix, la vérification est déjà faite par PingFederate : si le noeud n'est pas dans le périmètre de l'utilisateur, aucun token n'est émis. Appeler PingAuthorize à cet instant ferait la même vérification une deuxième fois.

PingAuthorize intervient plus tard, à chaque action métier (par exemple la création d'un utilisateur par délégation). Il vérifie alors, à partir du token :

- que le noeud cible est bien dans le contexte choisi (le noeud du token ou un de ses descendants) ;
- que le rôle détient l'entitlement de l'action demandée ;
- que l'assignment existe toujours en base, car le token peut avoir été émis avant un retrait de droits.

En résumé : PingFederate décide qui peut ouvrir un contexte, PingAuthorize décide ce qu'on peut faire dans ce contexte.
