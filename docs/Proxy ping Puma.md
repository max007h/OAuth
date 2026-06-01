# Portail PUMA — Documentation Technique Complète

> **Portail de provisioning utilisateurs** — Angular + Spring Boot + PingFederate + PingDirectory  
> Stack : Angular 17 (port 4300) · Spring Boot 3 (port 8081) · PingFederate (9031/9999) · PingDirectory (1389/443)

---

## Table des matières

1. [Architecture globale](#1-architecture-globale)
2. [Étape 1 — Groupes LDIF dans PingDirectory](#2-étape-1--groupes-ldif-dans-pingdirectory)
3. [Étape 2 — Créer un utilisateur MANAGER de test](#3-étape-2--créer-un-utilisateur-manager-de-test)
4. [Étape 3 — Client OAuth2 `puma-portal` dans PingFederate](#4-étape-3--client-oauth2-puma-portal-dans-pingfederate)
5. [Étape 4 — Auth Policy PingFederate pour PUMA](#5-étape-4--auth-policy-pingfederate-pour-puma)
6. [Étape 5 — Frontend Angular (Portail PUMA)](#6-étape-5--frontend-angular-portail-puma)
7. [Étape 6 — Guard MANAGER Angular](#7-étape-6--guard-manager-angular)
8. [Étape 7 — Backend Spring Boot](#8-étape-7--backend-spring-boot)
9. [Étape 8 — URL initialisation mot de passe](#9-étape-8--url-initialisation-mot-de-passe)
10. [Récapitulatif ports et flux](#10-récapitulatif-ports-et-flux)

---

## 1. Architecture globale

```
[Manager]
    │
    ▼
[Portail PUMA — Angular :4300]
    │
    │  Authorization Code + PKCE (sans RAR, sans PAR)
    ▼
[PingFederate :9031]
    │  Vérifie isMemberOf=MANAGER via LDAP
    ▼
[Spring Boot PUMA API :8081]
    │  SCIM v2 REST (création user)
    │  LDAP JNDI (affectation groupe)
    ▼
[PingDirectory :443 / :1389]
    │
    ▼
[Email → nouvel utilisateur → /ext/pwdreset]
```

**Décisions techniques :**
- Nouveau client OAuth2 `puma-portal` — Authorization Code + PKCE, **sans RAR, sans PAR**
- Autorisation basée sur le scope + claim `isMemberOf`
- API REST SCIM v2 de PingDirectory pour la création des utilisateurs
- LDAP JNDI pour l'affectation des groupes
- Seuls les `MANAGER` peuvent accéder au portail

---

## 2. Étape 1 — Groupes LDIF dans PingDirectory

### Fichier `groups.ldif`

```ldif
# Groupe COMMERCIAL
dn: cn=COMMERCIAL,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: top
cn: COMMERCIAL
member: uid=dummy,ou=people,dc=example,dc=com

# Groupe MANAGER
dn: cn=MANAGER,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: top
cn: MANAGER
member: uid=dummy,ou=people,dc=example,dc=com
```

### Commande d'application

```bash
ldapadd -h 172.18.0.3 -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -f groups.ldif
```

> **Note :** Le `member: uid=dummy,...` est un placeholder requis par le schéma `groupOfNames`. Il sera remplacé lors de l'ajout des vrais membres.

---

## 3. Étape 2 — Créer un utilisateur MANAGER de test

### Fichier `manager_1.ldif`

```ldif
dn: uid=manager_1,ou=people,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: bankingPerson
objectClass: top
uid: manager_1
cn: Manager Un
sn: Un
mail: manager1@example.com
userPassword: Password1234!
```

### Ajout au groupe MANAGER

```ldif
dn: cn=MANAGER,ou=groups,dc=example,dc=com
changetype: modify
add: member
member: uid=manager_1,ou=people,dc=example,dc=com
```

### Commandes

```bash
# Créer l'utilisateur
ldapadd -h 172.18.0.3 -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -f manager_1.ldif

# Ajouter au groupe
ldapmodify -h 172.18.0.3 -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w "2FederateM0re" \
  -f add_manager_group.ldif
```

---

## 4. Étape 3 — Client OAuth2 `puma-portal` dans PingFederate

### Accès Admin UI

```
https://localhost:9999
OAuth → Clients → Add Client
```

### Configuration du client

| Champ | Valeur |
|---|---|
| Client ID | `puma-portal` |
| Client Name | `Portail PUMA` |
| Client Authentication | `None` (public client) |
| Redirect URIs | `http://localhost:4300/callback` |
| Grant Types | ✅ `Authorization Code` |
| PKCE | ✅ `Required` — S256 |
| Scopes autorisés | `openid profile` |
| PAR | ❌ Non requis |
| RAR | ❌ Non configuré |
| Token Endpoint Auth Method | `none` |

### Scopes requis dans PingFederate

Vérifier que `openid` et `profile` sont déjà enregistrés dans :
```
OAuth → Scope Management
```

Si absent, ajouter `profile` avec description `Profil utilisateur`.

---

## 5. Étape 4 — Auth Policy PingFederate pour PUMA

### Création de la policy `PumaAuthPolicy`

```
Policies → Authentication Policies → Add Policy
```

| Champ | Valeur |
|---|---|
| Policy Name | `PumaAuthPolicy` |
| Adapter | `HTMLFormAdapter` (même que BankingAuthPolicy) |
| Contract | `PumaContract` (nouveau) |

### Contract `PumaContract`

Attributs du contract :

| Attribut | Source |
|---|---|
| `subject` | `username` (depuis l'adapter) |
| `isMemberOf` | Attribute Source LDAP |

### Attribute Source LDAP

| Champ | Valeur |
|---|---|
| Data Store | PingDirectory (172.18.0.3:1389) |
| Base DN | `ou=people,dc=example,dc=com` |
| Filter | `uid=${USER_KEY}` |
| Attributs retournés | `isMemberOf` |

### Mapping Token

Dans le Token Manager (`puma-portal`) → Contract Fulfillment :

| Claim JWT | Source |
|---|---|
| `sub` | `subject` |
| `isMemberOf` | `isMemberOf` (LDAP) |

---

## 6. Étape 5 — Frontend Angular (Portail PUMA)

### Structure du projet

```
puma-portal/
├── src/
│   ├── app/
│   │   ├── auth/
│   │   │   ├── auth.config.ts
│   │   │   ├── auth.service.ts
│   │   │   └── manager.guard.ts
│   │   ├── callback/
│   │   │   └── callback.component.ts
│   │   ├── create-user/
│   │   │   └── create-user.component.ts
│   │   ├── access-denied/
│   │   │   └── access-denied.component.ts
│   │   └── app.routes.ts
│   └── proxy.conf.json
├── angular.json
└── package.json
```

### `auth.config.ts`

```typescript
// Constantes OAuth2 / PingFederate — Portail PUMA
export const PUMA_AUTH_CONFIG = {
  PF:       'https://localhost:9031',
  CLIENT:   'puma-portal',
  REDIRECT: 'http://localhost:4300/callback',
  SCOPE:    'openid profile',
};
```

### `auth.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { PUMA_AUTH_CONFIG as C } from './auth.config';

@Injectable({ providedIn: 'root' })
export class AuthService {

  // Génère le PKCE verifier et challenge dynamiquement
  async login(): Promise<void> {
    const verifier  = this.generateVerifier();
    const challenge = await this.generateChallenge(verifier);
    sessionStorage.setItem('pkce_verifier', verifier);

    const params = new URLSearchParams({
      client_id:             C.CLIENT,
      response_type:         'code',
      redirect_uri:          C.REDIRECT,
      scope:                 C.SCOPE,
      code_challenge:        challenge,
      code_challenge_method: 'S256',
      state:                 crypto.randomUUID(),
    });

    window.location.href =
      `${C.PF}/as/authorization.oauth2?${params}`;
  }

  async exchangeCode(code: string): Promise<void> {
    const verifier = sessionStorage.getItem('pkce_verifier')!;

    const body = new URLSearchParams({
      grant_type:    'authorization_code',
      client_id:     C.CLIENT,
      code,
      redirect_uri:  C.REDIRECT,
      code_verifier: verifier,
    });

    const resp = await fetch(`${C.PF}/as/token.oauth2`, {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    body.toString(),
    });

    const data = await resp.json();
    sessionStorage.setItem('access_token', data.access_token);
    sessionStorage.setItem('id_token',     data.id_token);
  }

  // Décode un JWT sans librairie externe
  decodeJwt(token: string): Record<string, any> | null {
    try {
      const payload = token.split('.')[1];
      return JSON.parse(
        atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
      );
    } catch {
      return null;
    }
  }

  // Vérifie si l'utilisateur a le groupe MANAGER
  isManager(): boolean {
    const token = this.getToken();
    if (!token) return false;
    const claims = this.decodeJwt(token);
    const groups: string[] = claims?.['isMemberOf'] ?? [];
    return groups.some(g => g.includes('MANAGER'));
  }

  logout(): void {
    const idToken = sessionStorage.getItem('id_token');
    sessionStorage.clear();
    window.location.href =
      `${C.PF}/idp/startSLO.ping?id_token_hint=${idToken}` +
      `&post_logout_redirect_uri=${encodeURIComponent(C.REDIRECT)}`;
  }

  getToken(): string | null {
    return sessionStorage.getItem('access_token');
  }

  // PKCE — génère un verifier aléatoire (32 bytes)
  private generateVerifier(): string {
    const arr = new Uint8Array(32);
    crypto.getRandomValues(arr);
    return btoa(String.fromCharCode(...arr))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  // PKCE — hash SHA-256 du verifier
  private async generateChallenge(verifier: string): Promise<string> {
    const enc  = new TextEncoder().encode(verifier);
    const hash = await crypto.subtle.digest('SHA-256', enc);
    return btoa(String.fromCharCode(...new Uint8Array(hash)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  private generateVerifier(): string {
    const arr = new Uint8Array(32);
    crypto.getRandomValues(arr);
    return btoa(String.fromCharCode(...arr))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }
}
```

### `callback.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../auth/auth.service';

@Component({
  selector: 'app-callback',
  standalone: true,
  template: `<p>Connexion en cours...</p>`,
})
export class CallbackComponent implements OnInit {
  constructor(private auth: AuthService, private router: Router) {}

  async ngOnInit(): Promise<void> {
    const params = new URLSearchParams(window.location.search);
    const code   = params.get('code');
    if (!code) { this.router.navigate(['/']); return; }

    await this.auth.exchangeCode(code);

    if (this.auth.isManager()) {
      this.router.navigate(['/create-user']);
    } else {
      this.router.navigate(['/access-denied']);
    }
  }
}
```

### `create-user.component.ts`

```typescript
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../auth/auth.service';

interface CreateUserForm {
  uid:       string;
  firstName: string;
  lastName:  string;
  email:     string;
  role:      'COMMERCIAL' | 'MANAGER';
}

@Component({
  selector: 'app-create-user',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="container">
      <h1>Portail PUMA — Créer un utilisateur</h1>

      <form (ngSubmit)="submit()">
        <label>Login (uid)</label>
        <input [(ngModel)]="form.uid" name="uid" required />

        <label>Prénom</label>
        <input [(ngModel)]="form.firstName" name="firstName" required />

        <label>Nom</label>
        <input [(ngModel)]="form.lastName" name="lastName" required />

        <label>Email</label>
        <input [(ngModel)]="form.email" name="email" type="email" required />

        <label>Rôle</label>
        <select [(ngModel)]="form.role" name="role">
          <option value="COMMERCIAL">Commercial</option>
          <option value="MANAGER">Manager</option>
        </select>

        <button type="submit" [disabled]="loading">Créer l'utilisateur</button>
      </form>

      <div *ngIf="successMessage" class="success">
        {{ successMessage }}
        <p>
          L'utilisateur doit initialiser son mot de passe sur :
          <a href="https://localhost:9031/ext/pwdreset" target="_blank">
            https://localhost:9031/ext/pwdreset
          </a>
        </p>
      </div>

      <div *ngIf="errorMessage" class="error">{{ errorMessage }}</div>

      <button (click)="logout()">Déconnexion</button>
    </div>
  `,
})
export class CreateUserComponent {
  form: CreateUserForm = {
    uid: '', firstName: '', lastName: '', email: '', role: 'COMMERCIAL'
  };
  loading        = false;
  successMessage = '';
  errorMessage   = '';

  constructor(private auth: AuthService) {}

  async submit(): Promise<void> {
    this.loading        = true;
    this.successMessage = '';
    this.errorMessage   = '';

    try {
      const resp = await fetch('http://localhost:8081/api/users', {
        method:  'POST',
        headers: {
          'Content-Type':  'application/json',
          'Authorization': 'Bearer ' + this.auth.getToken(),
        },
        body: JSON.stringify(this.form),
      });

      if (resp.ok) {
        this.successMessage =
          `Utilisateur ${this.form.uid} créé avec succès.`;
        this.form = {
          uid: '', firstName: '', lastName: '', email: '', role: 'COMMERCIAL'
        };
      } else {
        const err = await resp.text();
        this.errorMessage = `Erreur : ${err}`;
      }
    } catch (e) {
      this.errorMessage = 'Erreur réseau.';
    } finally {
      this.loading = false;
    }
  }

  logout(): void { this.auth.logout(); }
}
```

### `app.routes.ts`

```typescript
import { Routes } from '@angular/router';
import { managerGuard } from './auth/manager.guard';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./home/home.component').then(m => m.HomeComponent),
  },
  {
    path: 'callback',
    loadComponent: () =>
      import('./callback/callback.component').then(m => m.CallbackComponent),
  },
  {
    path: 'create-user',
    canActivate: [managerGuard],
    loadComponent: () =>
      import('./create-user/create-user.component')
        .then(m => m.CreateUserComponent),
  },
  {
    path: 'access-denied',
    loadComponent: () =>
      import('./access-denied/access-denied.component')
        .then(m => m.AccessDeniedComponent),
  },
];
```

---

## 7. Étape 6 — Guard MANAGER Angular

### `manager.guard.ts`

```typescript
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';

export const managerGuard = () => {
  const auth   = inject(AuthService);
  const router = inject(Router);

  if (auth.isManager()) return true;

  // Pas de token → login
  if (!auth.getToken()) {
    auth.login();
    return false;
  }

  // Token présent mais pas MANAGER → accès refusé
  router.navigate(['/access-denied']);
  return false;
};
```

---

## 8. Étape 7 — Backend Spring Boot

### `application.yml`

```yaml
server:
  port: 8081  # Différent du banking-app (8080)

pingdirectory:
  host: 172.18.0.3
  port: 443                              # API REST SCIM v2
  ldap-port: 1389                        # LDAP pour affectation groupes
  base-dn: ou=people,dc=example,dc=com
  groups-dn: ou=groups,dc=example,dc=com
  admin-dn: cn=administrator,dc=example,dc=com
  admin-password: 2FederateM0re

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://localhost:9031

cors:
  allowed-origins: http://localhost:4300
```

### `CreateUserRequest.java`

```java
public record CreateUserRequest(
    String uid,
    String firstName,
    String lastName,
    String email,
    String role   // "COMMERCIAL" ou "MANAGER"
) {}
```

### `UserController.java`

```java
@RestController
@RequestMapping("/api/users")
public class UserController {

    @Autowired
    private UserProvisioningService userService;

    @PostMapping
    public ResponseEntity<?> createUser(
            @RequestBody CreateUserRequest req,
            JwtAuthenticationToken token) {

        // Double vérification rôle MANAGER côté backend
        List<String> groups =
            token.getToken().getClaimAsStringList("isMemberOf");

        boolean isManager = groups != null &&
            groups.stream().anyMatch(g -> g.contains("MANAGER"));

        if (!isManager) {
            return ResponseEntity.status(403).body("Accès refusé — rôle MANAGER requis");
        }

        // Validation du rôle cible
        if (!List.of("COMMERCIAL", "MANAGER").contains(req.role())) {
            return ResponseEntity.badRequest().body("Rôle invalide");
        }

        userService.createUser(req);

        return ResponseEntity.ok(Map.of(
            "message", "Utilisateur " + req.uid() + " créé avec succès.",
            "passwordResetUrl", "https://localhost:9031/ext/pwdreset",
            "instruction", "L'utilisateur doit initialiser son mot de passe en cliquant sur 'Mot de passe oublié'."
        ));
    }
}
```

### `UserProvisioningService.java`

```java
@Service
public class UserProvisioningService {

    @Value("${pingdirectory.host}")           private String host;
    @Value("${pingdirectory.port}")           private int port;
    @Value("${pingdirectory.ldap-port}")      private int ldapPort;
    @Value("${pingdirectory.admin-dn}")       private String adminDn;
    @Value("${pingdirectory.admin-password}") private String adminPwd;

    public void createUser(CreateUserRequest req) {
        // Étape 1 : Créer l'utilisateur via SCIM v2 REST
        createViaScim(req);
        // Étape 2 : Ajouter au groupe via LDAP
        addToGroup(req.uid(), req.role());
    }

    private void createViaScim(CreateUserRequest req) {
        String baseUrl = "https://" + host + ":" + port + "/scim/v2";

        String body = """
        {
          "schemas": ["urn:ietf:params:scim:schemas:core:2.0:User"],
          "userName": "%s",
          "name": {
            "givenName": "%s",
            "familyName": "%s"
          },
          "emails": [{ "value": "%s", "primary": true }],
          "password": "Changeme123!"
        }
        """.formatted(req.uid(), req.firstName(), req.lastName(), req.email());

        try {
            HttpClient client = HttpClient.newBuilder()
                .sslContext(trustAllSslContext())  // POC uniquement
                .build();

            HttpRequest httpReq = HttpRequest.newBuilder()
                .uri(URI.create(baseUrl + "/Users"))
                .header("Content-Type", "application/json")
                .header("Authorization", basicAuth(adminDn, adminPwd))
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();

            HttpResponse<String> resp =
                client.send(httpReq, HttpResponse.BodyHandlers.ofString());

            if (resp.statusCode() != 201) {
                throw new RuntimeException(
                    "SCIM error: " + resp.statusCode() + " " + resp.body());
            }
        } catch (Exception e) {
            throw new RuntimeException("Erreur création SCIM", e);
        }
    }

    private void addToGroup(String uid, String role) {
        String groupDn  = "cn=" + role + ",ou=groups,dc=example,dc=com";
        String memberDn = "uid=" + uid  + ",ou=people,dc=example,dc=com";

        Hashtable<String, String> env = new Hashtable<>();
        env.put(Context.INITIAL_CONTEXT_FACTORY,
            "com.sun.jndi.ldap.LdapCtxFactory");
        env.put(Context.PROVIDER_URL, "ldap://" + host + ":" + ldapPort);
        env.put(Context.SECURITY_AUTHENTICATION, "simple");
        env.put(Context.SECURITY_PRINCIPAL,   adminDn);
        env.put(Context.SECURITY_CREDENTIALS, adminPwd);

        try {
            DirContext ctx = new InitialDirContext(env);
            ModificationItem[] mods = {
                new ModificationItem(
                    DirContext.ADD_ATTRIBUTE,
                    new BasicAttribute("member", memberDn))
            };
            ctx.modifyAttributes(groupDn, mods);
            ctx.close();
        } catch (NamingException e) {
            throw new RuntimeException("Erreur LDAP affectation groupe", e);
        }
    }

    // Basic Auth header pour SCIM
    private String basicAuth(String user, String pass) {
        String creds = user + ":" + pass;
        return "Basic " + Base64.getEncoder()
            .encodeToString(creds.getBytes(StandardCharsets.UTF_8));
    }

    // SSL permissif pour POC (ne pas utiliser en production)
    private SSLContext trustAllSslContext() throws Exception {
        TrustManager[] tm = new TrustManager[]{
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                public void checkClientTrusted(X509Certificate[] c, String a) {}
                public void checkServerTrusted(X509Certificate[] c, String a) {}
            }
        };
        SSLContext sc = SSLContext.getInstance("TLS");
        sc.init(null, tm, new SecureRandom());
        return sc;
    }
}
```

### `SecurityConfig.java` (Spring Boot PUMA)

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .csrf(csrf -> csrf.disable())
            .sessionManagement(session ->
                session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                .requestMatchers("/api/**").authenticated()
                .anyRequest().authenticated()
            )
            .oauth2ResourceServer(oauth2 ->
                oauth2.jwt(jwt -> jwt.decoder(jwtDecoder()))
            );
        return http.build();
    }

    @Bean
    public JwtDecoder jwtDecoder() {
        // Valider les tokens émis par PingFederate
        return NimbusJwtDecoder
            .withIssuerLocation("https://localhost:9031")
            .build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of("http://localhost:4300"));
        config.setAllowedMethods(List.of("GET","POST","PUT","DELETE","OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);
        UrlBasedCorsConfigurationSource source =
            new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

---

## 9. Étape 8 — URL initialisation mot de passe

Une fois l'utilisateur créé, il reçoit un message lui indiquant d'aller sur :

```
https://localhost:9031/ext/pwdreset
```

**Flow PingFederate natif :**
1. L'utilisateur accède à l'URL ci-dessus
2. Il saisit son **login (uid)**
3. PingFederate envoie un email de réinitialisation
4. L'utilisateur clique sur le lien et définit son nouveau mot de passe

**Prérequis PingFederate :**
- Password Credential Validator (PCV) configuré avec PingDirectory
- Politique de reset activée dans : `Server → Password Reset → Enable`
- Attribut email présent dans PingDirectory pour l'envoi du lien

---

## 10. Récapitulatif ports et flux

| Composant | Port | Rôle |
|---|---|---|
| Angular PUMA | 4300 | Frontend portail |
| Spring Boot PUMA | 8081 | API provisioning |
| PingFederate AS | 9031 | Authorization Server OAuth2 |
| PingFederate Admin | 9999 | Interface d'administration |
| PingDirectory LDAP | 1389 | Annuaire LDAP |
| PingDirectory REST | 443 | API SCIM v2 |

### Flux complet de création d'un utilisateur

```
1. Manager → http://localhost:4300
2. Clic "Connexion" → redirect vers PingFederate (PKCE)
3. Login HTMLForm → PingFederate vérifie isMemberOf=MANAGER
4. Redirect → http://localhost:4300/callback?code=xxx
5. Angular échange le code → reçoit access_token JWT
6. JWT décodé → isMemberOf contient "MANAGER" → accès autorisé
7. Manager remplit le formulaire (uid, nom, prénom, email, rôle)
8. POST http://localhost:8081/api/users avec Bearer token
9. Spring Boot vérifie le claim isMemberOf côté backend
10. SCIM v2 → PingDirectory crée l'utilisateur avec password=Changeme123!
11. LDAP JNDI → PingDirectory ajoute uid au groupe COMMERCIAL ou MANAGER
12. Réponse : "Utilisateur créé — initialiser le mot de passe sur /ext/pwdreset"
```

---

*Document généré pour le POC Portail PUMA — Environnement de développement local*  
*Ne pas utiliser le trustAllSslContext() et les credentials en clair en production*
