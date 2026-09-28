# Rataweb : démo d'une application partenaire

## Le but

Prouver que le modèle PUMA fonctionne pour une application partenaire, avec le strict minimum :

1. l'utilisateur se connecte à Rataweb ;
2. une pop-up lui propose les noeuds où il a un rôle **Rataweb** (et leurs descendants) ;
3. il en choisit un, Rataweb obtient un nouveau token qui ne contient que **ses droits Rataweb sur ce noeud** ;
4. quatre boutons, un par fonctionnalité. Le backend vérifie seulement que le token contient un rôle autorisé pour ce bouton, comme le ferait une API Gateway.

Pas de PDP dans cette démo : on s'arrête au contrôle grossier par rôle. La décision fine (PingAuthorize) viendra plus tard. Rataweb ne touche jamais la base PUMA, il utilise seulement l'API PUMA pour lister les noeuds.

| Composant | Port |
|---|---|
| Rataweb front | 4300 |
| Rataweb back | 8082 |
| PUMA back | 8081 |
| PingFederate | 9031 |

Ordre : base, PingFederate, PUMA, Rataweb back, Rataweb front.

---

## 1. Base de données

```sql
-- L'application d'un client OAuth : les tokens demandés par ce client
-- ne contiendront que les droits de cette application
ALTER TABLE application ADD COLUMN IF NOT EXISTS client_id varchar(100);
UPDATE application SET client_id = 'rataweb-backend' WHERE id = 'A3';

-- Vue partenaire : la vue PUMA, avec l'application du rôle.
-- L'héritage reste calculé à un seul endroit.
CREATE OR REPLACE VIEW partner_user_node_roles AS
SELECT v.uid, v.node_id, v.role_id, r.application_id
FROM puma_user_node_roles v
JOIN app_role r ON r.id = v.role_id;
```

La vue `puma_user_node_roles` ne change pas : PUMA et le PDP continuent de l'utiliser.

Vérification :

```sql
SELECT * FROM partner_user_node_roles
WHERE uid = 'max.walker' AND application_id = 'A3';
```

---

## 2. PingFederate

### 2.1 Deux clients

**Applications > OAuth > Clients**.

`rataweb-portal`, en recopiant `puma-portal` :
- Client Authentication : None
- Redirect URI : `http://localhost:4300/callback`
- Grant : Authorization Code (PKCE)

`rataweb-backend`, en recopiant `puma-backend` :
- Client Authentication : Client Secret (génère-le et garde-le)
- Grant : Token Exchange uniquement
- Default Access Token Manager : `JWTAccessToken`

Si PingFederate filtre les origines CORS, ajoute `http://localhost:4300`.

### 2.2 Les rôles : ne garder que ceux de l'application du client

Mapping `puma-context-policy`, attribute source `pumaRoles` :

- Table : `partner_user_node_roles`
- Filtre :

```
uid = '${tepp.subject}' AND node_id = '${tepp.node}'
AND (application_id = (SELECT id FROM application WHERE client_id = '${context.ClientId}')
     OR '${context.ClientId}' = 'puma-backend')
```

Pour `puma-backend`, rien ne change : PUMA garde tous les rôles. Pour `rataweb-backend`, seuls ceux de A3 remontent.

L'Issuance Criteria existante suffit : sans rôle Rataweb sur le noeud, pas de token.

### 2.3 Tests

Deux tests distincts.

**Non-régression de PUMA**, avec un token de login de Thomas (le manager PUMA). Le filtre JDBC est partagé, son token PUMA doit rester identique à avant :

```bash
curl -k -u puma-backend:SECRET_PUMA https://localhost:9031/as/token.oauth2 \
  -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token=$TOKEN_THOMAS \
  -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  -d node=2700010
```

Attendu : tous les rôles de Thomas, comme aujourd'hui.

**Fonctionnel Rataweb**, avec un token de login de max.walker (créé par Thomas, rôles Rataweb). Remplace le noeud par celui de son affectation :

```bash
curl -k -u rataweb-backend:SECRET_RATAWEB https://localhost:9031/as/token.oauth2 \
  -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token=$TOKEN_MAX \
  -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  -d node=NOEUD_DE_MAX
```

Attendu : `client_id` = `rataweb-backend`, `node` = le noeud choisi, `roles` = uniquement ses rôles Rataweb.

---

## 3. PUMA : filtrer la liste des noeuds par application

### 3.1 `AssignmentRepository`

```java
@Query(value = """
    SELECT DISTINCT v.node_id AS "nodeId", n.label AS "label"
    FROM partner_user_node_roles v
    JOIN node n ON n.id = v.node_id
    WHERE v.uid = :uid AND v.application_id = :app
    ORDER BY v.node_id
    """, nativeQuery = true)
List<NodeContextView> findContextNodesForApp(@Param("uid") String uid, @Param("app") String app);
```

### 3.2 `UserContextService`

```java
public List<NodeContextDto> getContextNodes(String uid, String application) {
    String user = uid.toLowerCase(Locale.ROOT);
    List<NodeContextView> rows = application == null
            ? assignmentRepository.findContextNodes(user)
            : assignmentRepository.findContextNodesForApp(user, application);
    return rows.stream()
            .map(v -> new NodeContextDto(v.getNodeId(), v.getLabel()))
            .toList();
}
```

### 3.3 `ContextController`

```java
@GetMapping("/nodes")
public List<NodeContextDto> nodes(@AuthenticationPrincipal Jwt jwt,
                                  @RequestParam(required = false) String application) {
    return userContextService.getContextNodes(claims.getSub(jwt), application);
}
```

Sans paramètre, PUMA garde son comportement actuel. Ce filtre ne sert qu'à l'affichage : la sécurité est à l'émission du token.

### 3.4 `CorsFilter`

```java
String origin = request.getHeader("Origin");
if ("http://localhost:4200".equals(origin) || "http://localhost:4300".equals(origin)) {
    response.setHeader("Access-Control-Allow-Origin", origin);
    response.setHeader("Vary", "Origin");
}
```

---

## 4. Rataweb back

Projet Spring Boot, dépendances **Web** et **OAuth2 Resource Server**, package `com.poc.rataweb`.

### 4.1 `application.yml`

```yaml
server:
  port: 8082

rataweb:
  client-id: rataweb-backend
  client-secret: SECRET_RATAWEB
  token-url: https://localhost:9031/as/token.oauth2
  jwt:
    secret-hex: MEME_VALEUR_QUE_POC_KEY
```

### 4.2 `SecurityConfig.java`

```java
@Configuration
public class SecurityConfig {

    @Bean
    SecurityFilterChain chain(HttpSecurity http) throws Exception {
        return http
                .csrf(c -> c.disable())
                .cors(Customizer.withDefaults())
                .authorizeHttpRequests(a -> a.anyRequest().authenticated())
                .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .build();
    }

    @Bean
    JwtDecoder jwtDecoder(@Value("${rataweb.jwt.secret-hex}") String hex) {
        SecretKey key = new SecretKeySpec(HexFormat.of().parseHex(hex), "HmacSHA256");
        return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
    }

    @Bean
    CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of("http://localhost:4300"));
        config.setAllowedMethods(List.of("GET", "POST", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

### 4.3 `TokenExchangeService.java`

```java
@Service
public class TokenExchangeService {

    @Value("${rataweb.token-url}")     private String tokenUrl;
    @Value("${rataweb.client-id}")     private String clientId;
    @Value("${rataweb.client-secret}") private String clientSecret;

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** Échange le token de login contre un token Rataweb pour le noeud choisi. */
    public String exchange(String loginToken, String nodeId) throws Exception {
        String form = "grant_type=" + enc("urn:ietf:params:oauth:grant-type:token-exchange")
                + "&subject_token=" + enc(loginToken)
                + "&subject_token_type=" + enc("urn:ietf:params:oauth:token-type:access_token")
                + "&node=" + enc(nodeId);

        String basic = Base64.getEncoder().encodeToString(
                (clientId + ":" + clientSecret).getBytes(StandardCharsets.UTF_8));

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(tokenUrl))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Authorization", "Basic " + basic)
                .POST(HttpRequest.BodyPublishers.ofString(form))
                .build();

        HttpClient client = HttpClient.newBuilder().sslContext(trustAll()).build();
        HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            return null;   // noeud refusé ou erreur : pas de token
        }
        return MAPPER.readTree(response.body()).path("access_token").asText();
    }

    private static String enc(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    // POC uniquement : PingFederate a un certificat auto-signé
    private static SSLContext trustAll() throws Exception {
        TrustManager[] managers = { new X509TrustManager() {
            public void checkClientTrusted(X509Certificate[] c, String a) { }
            public void checkServerTrusted(X509Certificate[] c, String a) { }
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
        } };
        SSLContext context = SSLContext.getInstance("TLS");
        context.init(null, managers, new SecureRandom());
        return context;
    }
}
```

### 4.4 `ContextController.java`

```java
@RestController
@RequestMapping("/api/context")
public class ContextController {

    private final TokenExchangeService exchange;

    public ContextController(TokenExchangeService exchange) {
        this.exchange = exchange;
    }

    @PostMapping("/select")
    public ResponseEntity<?> select(@AuthenticationPrincipal Jwt jwt,
                                    @RequestBody Map<String, String> body) throws Exception {
        String token = exchange.exchange(jwt.getTokenValue(), body.get("nodeId"));
        if (token == null) {
            return ResponseEntity.status(403).body(Map.of("message", "Aucun droit Rataweb sur ce noeud."));
        }
        return ResponseEntity.ok(Map.of("access_token", token));
    }
}
```

### 4.5 `ActionController.java`

Un endpoint par fonctionnalité. Chaque bouton accepte une liste de rôles, comme une route d'API Gateway.

```java
@RestController
@RequestMapping("/api")
public class ActionController {

    // Rôles Rataweb : R15 Conseiller financement, R16 Superviseur financement
    private static final List<String> READ    = List.of("R15", "R16");
    private static final List<String> CREATE  = List.of("R15", "R16");
    private static final List<String> SUBMIT  = List.of("R15", "R16");
    private static final List<String> APPROVE = List.of("R16");

    @GetMapping("/quotes")
    public ResponseEntity<?> readQuotes(@AuthenticationPrincipal Jwt jwt) {
        return run(jwt, READ, "Consultation des devis");
    }

    @PostMapping("/quotes")
    public ResponseEntity<?> createQuote(@AuthenticationPrincipal Jwt jwt) {
        return run(jwt, CREATE, "Création d'un devis");
    }

    @PostMapping("/requests/submit")
    public ResponseEntity<?> submitRequest(@AuthenticationPrincipal Jwt jwt) {
        return run(jwt, SUBMIT, "Soumission d'une demande");
    }

    @PostMapping("/requests/approve")
    public ResponseEntity<?> approveRequest(@AuthenticationPrincipal Jwt jwt) {
        return run(jwt, APPROVE, "Approbation d'une demande");
    }

    private ResponseEntity<?> run(Jwt jwt, List<String> allowedRoles, String label) {
        // Le token doit avoir été émis pour Rataweb, sur un noeud choisi
        if (!"rataweb-backend".equals(jwt.getClaimAsString("client_id"))) {
            return refuse(label + " : token non émis pour Rataweb.");
        }
        String node = jwt.getClaimAsString("node");
        List<String> roles = jwt.getClaimAsStringList("roles");

        boolean allowed = node != null && roles != null
                && roles.stream().anyMatch(allowedRoles::contains);
        if (!allowed) {
            return refuse(label + " refusée : rôle requis " + allowedRoles + ".");
        }
        return ResponseEntity.ok(Map.of("message", label + " autorisée sur le noeud " + node + "."));
    }

    private ResponseEntity<?> refuse(String message) {
        return ResponseEntity.status(403).body(Map.of("message", message));
    }
}
```

---

## 5. Rataweb front

### 5.1 Projet

```bash
ng new rataweb-front --standalone --routing --style=css --skip-tests
cd rataweb-front
ng serve --port 4300
```

Depuis `banking-app`, recopie `auth.service.ts` et le composant `callback`, en changeant seulement le `client_id` (`rataweb-portal`) et la redirect URI (`http://localhost:4300/callback`). Garde `getToken()` et `setToken()`.

### 5.2 `core/api.ts`

```typescript
export const PUMA_API = 'http://localhost:8081/api';
export const RATAWEB_API = 'http://localhost:8082/api';
export const APP_ID = 'A3';
```

### 5.3 `core/rataweb.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { APP_ID, PUMA_API, RATAWEB_API } from './api';

export interface NodeItem {
  nodeId: string;
  label: string;
}

@Injectable({ providedIn: 'root' })
export class RatawebService {

  constructor(private auth: AuthService) {}

  private async call(url: string, method = 'GET', body?: unknown): Promise<any> {
    const resp = await fetch(url, {
      method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.auth.getToken()
      },
      body: body ? JSON.stringify(body) : undefined
    });
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      throw new Error(data.message ?? 'Erreur ' + resp.status);
    }
    return data;
  }

  // Noeuds où l'utilisateur a un rôle Rataweb (API PUMA)
  nodes(): Promise<NodeItem[]> {
    return this.call(`${PUMA_API}/contexts/nodes?application=${APP_ID}`);
  }

  // Le backend Rataweb fait le token exchange
  async selectNode(nodeId: string): Promise<void> {
    const data = await this.call(`${RATAWEB_API}/context/select`, 'POST', { nodeId });
    this.auth.setToken(data.access_token);
  }

  action(path: string, method: string): Promise<{ message: string }> {
    return this.call(`${RATAWEB_API}${path}`, method);
  }

  hasContext(): boolean {
    const token = this.auth.getToken();
    if (!token) return false;
    try {
      const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      return payload.client_id === 'rataweb-backend' && !!payload.node;
    } catch {
      return false;
    }
  }
}
```

### 5.4 `features/home/home.component.ts`

La pop-up et les boutons sur la même page, pour rester simple.

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { NodeItem, RatawebService } from '../../core/rataweb.service';

@Component({
  selector: 'app-home',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './home.component.html',
  styleUrls: ['./home.component.css']
})
export class HomeComponent implements OnInit {

  nodes: NodeItem[] = [];
  selected = '';
  showPicker = false;
  results: string[] = [];
  error = '';

  actions = [
    { label: 'Consulter les devis',     path: '/quotes',           method: 'GET' },
    { label: 'Créer un devis',          path: '/quotes',           method: 'POST' },
    { label: 'Soumettre une demande',   path: '/requests/submit',  method: 'POST' },
    { label: 'Approuver une demande',   path: '/requests/approve', method: 'POST' }
  ];

  constructor(private rataweb: RatawebService) {}

  async ngOnInit(): Promise<void> {
    if (!this.rataweb.hasContext()) {
      await this.openPicker();
    }
  }

  async openPicker(): Promise<void> {
    this.showPicker = true;
    this.error = '';
    try {
      this.nodes = await this.rataweb.nodes();
      if (this.nodes.length === 0) {
        this.error = "Vous n'avez aucun rôle Rataweb.";
      }
    } catch (e: any) {
      this.error = e.message;
    }
  }

  async choose(): Promise<void> {
    try {
      await this.rataweb.selectNode(this.selected);
      this.showPicker = false;
      this.results = [];
    } catch (e: any) {
      this.error = e.message;
    }
  }

  async run(action: { label: string; path: string; method: string }): Promise<void> {
    try {
      const res = await this.rataweb.action(action.path, action.method);
      this.results.unshift('OK : ' + res.message);
    } catch (e: any) {
      this.results.unshift('REFUS : ' + e.message);
    }
  }
}
```

### 5.5 `home.component.html`

```html
<div class="page">
  <h1>Rataweb</h1>

  <button class="link" (click)="openPicker()">Changer de noeud</button>

  <div class="actions">
    <button *ngFor="let a of actions" (click)="run(a)">{{ a.label }}</button>
  </div>

  <ul class="results">
    <li *ngFor="let r of results">{{ r }}</li>
  </ul>
</div>

<div class="overlay" *ngIf="showPicker">
  <div class="dialog">
    <h2>Choisissez votre noeud</h2>
    <select [(ngModel)]="selected" name="node">
      <option value="">Choisir...</option>
      <option *ngFor="let n of nodes" [value]="n.nodeId">{{ n.label }} ({{ n.nodeId }})</option>
    </select>
    <p class="error" *ngIf="error">{{ error }}</p>
    <button (click)="choose()" [disabled]="!selected">Continuer</button>
  </div>
</div>
```

Tous les boutons sont affichés exprès : on veut voir le backend refuser.

### 5.6 `home.component.css`

```css
.page { max-width: 600px; margin: 40px auto; font-family: sans-serif; }
.actions button { display: block; width: 100%; padding: 10px; margin: 8px 0; }
.link { background: none; border: none; color: #1565c0; cursor: pointer; padding: 0; }
.results { padding-left: 18px; font-size: 0.9rem; }
.overlay { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.4);
           display: flex; align-items: center; justify-content: center; }
.dialog { background: #fff; padding: 20px; width: 320px; border-radius: 6px; }
.dialog select, .dialog button { width: 100%; padding: 8px; margin-top: 10px; }
.error { color: #b00020; }
```

### 5.7 Routes

```typescript
export const routes: Routes = [
  { path: 'callback', component: CallbackComponent },
  { path: '', component: HomeComponent }
];
```

Le déclenchement du login se fait comme dans `banking-app`.

---

## 6. Scénarios

| Utilisateur | Rôle Rataweb | Résultat attendu |
|---|---|---|
| max.walker, Superviseur (R16) | sur son noeud | Les quatre boutons OK |
| max.walker, Conseiller (R15) seulement | sur son noeud | Approuver refusé, le reste OK |
| un utilisateur sans rôle Rataweb | aucun | Pop-up vide, aucun token, aucun accès |

Pour tester les deux premiers cas, Thomas attribue à max.walker l'un ou l'autre rôle depuis PUMA.

Et en parallèle, la non-régression : dans PUMA, le token de Thomas reste identique à avant.

## 7. Ce que la démo prouve, et ses limites

Elle prouve :

- un rôle appartient à une application, et une application ne voit que ses rôles ;
- le contrôle grossier par rôle, tel que le ferait une API Gateway ;
- l'héritage descendant : un rôle sur Roller 5 vaut sur ses vendors ;
- le token ne porte que le noeud choisi, pas toute la hiérarchie ;
- une nouvelle application partenaire, c'est de la configuration, sans code dans PUMA ;
- l'application ne touche jamais la base PUMA.

Ses limites :

- **Fraîcheur** : un rôle retiré reste actif jusqu'à l'expiration du token. Durée de vie courte, et PDP pour les actions sensibles.
- **Contrôle grossier seulement** : le rôle suffit à passer. Les permissions exactes, la spécialisation et le noeud cible seront vérifiés plus tard par PingAuthorize, pour chaque action.
- **Secret et certificat** : secret en clair dans le `yml` et `trustAll`, réservés au POC.
