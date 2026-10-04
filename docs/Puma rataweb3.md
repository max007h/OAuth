# Rataweb : application partenaire de démonstration

Version du 04/10/2026. Application métier de démonstration : elle consomme PUMA (choix du contexte, décision d'autorisation) mais ne fait pas partie du POC PUMA lui-même.

Parcours : login (rataweb-portal, PKCE), pop-up de choix de l'entité, token exchange (rataweb-backend), liste des contrats, bouton "Approuver" autorisé ou refusé par PingAuthorize via PUMA.

Principes :

- l'application (A3) est déclarée une seule fois, dans application.yml du backend Rataweb ;
- le front n'appelle que le backend Rataweb ;
- toute décision passe par PUMA puis PingAuthorize ; toute erreur vaut refus ;
- le statut d'un contrat ne change que si la décision est PERMIT.

Fichiers supprimés de l'ancienne version : controller/ActionController.java, controller/ContextController.java, service/TokenExchangeService.java, config/CorsFilter.java (s'il existe). Ils sont remplacés ci-dessous.

---

## Étape 0 : base de données (pgAdmin, une seule fois)

Contrôle préalable, doit renvoyer 0 ligne :

```sql
SELECT id, code FROM permission WHERE id IN ('P23', 'P24');
```

Script, en transaction, avec contrôles avant COMMIT :

```sql
BEGIN;

-- Contrôle : R15 et R16 doivent être des rôles Rataweb (A3)
SELECT id, code, application_id FROM app_role WHERE id IN ('R15', 'R16');

CREATE SCHEMA IF NOT EXISTS rataweb;

CREATE TABLE IF NOT EXISTS rataweb.contract (
    id            BIGSERIAL     PRIMARY KEY,
    reference     VARCHAR(30)   NOT NULL UNIQUE,
    customer_name VARCHAR(100)  NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    node_id       VARCHAR(20)   NOT NULL,
    status        VARCHAR(20)   NOT NULL DEFAULT 'PENDING',
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    approved_by   VARCHAR(100),
    approved_at   TIMESTAMPTZ,
    CONSTRAINT ck_contract_status CHECK (status IN ('PENDING', 'APPROVED'))
);

INSERT INTO rataweb.contract (reference, customer_name, amount, node_id, created_at) VALUES
  ('CT-2026-001', 'Martin Keller',   18500.00, '2700013', now() - interval '20 days'),
  ('CT-2026-002', 'Anna Schulz',      9200.00, '2700013', now() - interval '18 days'),
  ('CT-2026-003', 'Lukas Wagner',    24300.00, '2700013', now() - interval '15 days'),
  ('CT-2026-004', 'Sophie Becker',    7600.00, '2700013', now() - interval '9 days'),
  ('CT-2026-005', 'Jonas Hoffmann',  13900.00, '2700013', now() - interval '3 days'),
  ('CT-2026-006', 'Laura Fischer',   11200.00, '2700010', now() - interval '12 days'),
  ('CT-2026-007', 'Paul Weber',       5400.00, '2700010', now() - interval '6 days'),
  ('CT-2026-008', 'Mia Richter',     16800.00, '2700011', now() - interval '10 days'),
  ('CT-2026-009', 'Felix Neumann',    8900.00, '2700011', now() - interval '2 days'),
  ('CT-2026-010', 'Lea Zimmermann',  21000.00, '2700015', now() - interval '8 days'),
  ('CT-2026-011', 'Tim Braun',        6300.00, '2700015', now() - interval '4 days'),
  ('CT-2026-012', 'Emma Krueger',    32500.00, '2672749', now() - interval '5 days')
ON CONFLICT (reference) DO NOTHING;

INSERT INTO permission (id, code, label, application_id) VALUES
  ('P23', 'contract.read',    'Consulter les contrats', 'A3'),
  ('P24', 'contract.approve', 'Approuver un contrat',   'A3')
ON CONFLICT (id) DO NOTHING;

-- R15 consulte, R16 consulte et approuve
INSERT INTO role_permission (role_id, permission_id, granted) VALUES
  ('R15', 'P23', true), ('R16', 'P23', true), ('R16', 'P24', true)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Rataweb ouvert sur chaque noeud portant un contrat (la vue exige le noeud exact)
INSERT INTO node_application (node_id, application_id)
SELECT DISTINCT node_id, 'A3' FROM rataweb.contract
ON CONFLICT (node_id, application_id) DO NOTHING;

-- Contrôles
SELECT node_id, status, count(*) FROM rataweb.contract GROUP BY 1, 2 ORDER BY 1;
SELECT rp.role_id, p.code FROM role_permission rp
JOIN permission p ON p.id = rp.permission_id
WHERE p.id IN ('P23', 'P24') ORDER BY 1, 2;

COMMIT;  -- ou ROLLBACK si un contrôle est faux
```

Attendu : 12 contrats PENDING sur 5 noeuds ; R15 avec contract.read ; R16 avec contract.read et contract.approve.

---

## Étape 1 : backend Rataweb (port 8082, package com.poc.rataweb)

### 1.1 pom.xml

```xml
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-security</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-oauth2-resource-server</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-jdbc</artifactId></dependency>
<dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
```

### 1.2 src/main/resources/application.yml (remplace tout)

```yaml
server:
  port: 8082

spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/postgres
    username: postgres
    password: postgres
  sql:
    init:
      mode: never

logging:
  level:
    com.poc.rataweb: DEBUG

rataweb:
  cors-origin: http://localhost:4300
  # Identifiant de l'application dans PUMA : filtre de la pop-up et décisions
  application-id: A3
  token-url: https://localhost:9031/as/token.oauth2
  client-id: rataweb-backend
  client-secret: ${RATAWEB_CLIENT_SECRET}
  jwt:
    secret-hex: ${RATAWEB_JWT_SECRET_HEX}
  puma:
    base-url: http://localhost:8081
```

Variables d'environnement à déclarer dans la configuration de lancement IntelliJ :

- RATAWEB_CLIENT_SECRET : secret du client rataweb-backend ;
- RATAWEB_JWT_SECRET_HEX : même valeur hex que la clé poc-key de PUMA.

### 1.3 config/SecurityConfig.java

```java
package com.poc.rataweb.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import java.util.HexFormat;
import java.util.List;

@Configuration
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(csrf -> csrf.disable())
            .cors(Customizer.withDefaults())
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                .requestMatchers("/api/**").authenticated()
                .anyRequest().denyAll())
            .oauth2ResourceServer(oauth -> oauth.jwt(Customizer.withDefaults()));
        return http.build();
    }

    /** Vérifie la signature HS256 des tokens émis par PingFederate (ATM JWTAccessToken). */
    @Bean
    public JwtDecoder jwtDecoder(@Value("${rataweb.jwt.secret-hex}") String secretHex) {
        SecretKey key = new SecretKeySpec(HexFormat.of().parseHex(secretHex), "HmacSHA256");
        return NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource(@Value("${rataweb.cors-origin}") String origin) {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of(origin));
        config.setAllowedMethods(List.of("GET", "POST", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

### 1.4 util/InsecureSsl.java

```java
package com.poc.rataweb.util;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;

/** POC uniquement : PingFederate utilise un certificat auto-signé. À retirer hors POC. */
public final class InsecureSsl {

    private InsecureSsl() { }

    public static SSLContext trustAll() {
        try {
            TrustManager[] trustAll = { new X509TrustManager() {
                public void checkClientTrusted(X509Certificate[] chain, String authType) { }
                public void checkServerTrusted(X509Certificate[] chain, String authType) { }
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            } };
            SSLContext context = SSLContext.getInstance("TLS");
            context.init(null, trustAll, new SecureRandom());
            return context;
        } catch (Exception e) {
            throw new IllegalStateException("Contexte SSL impossible", e);
        }
    }
}
```

### 1.5 service/TokenExchangeService.java

```java
package com.poc.rataweb.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.poc.rataweb.util.InsecureSsl;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Optional;

@Service
public class TokenExchangeService {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Value("${rataweb.token-url}")
    private String tokenUrl;

    @Value("${rataweb.client-id}")
    private String clientId;

    @Value("${rataweb.client-secret}")
    private String clientSecret;

    private final HttpClient http = HttpClient.newBuilder().sslContext(InsecureSsl.trustAll()).build();

    /** Token de contexte, ou vide si PingFederate refuse le noeud (aucun rôle dessus). */
    public Optional<String> exchange(String loginToken, String nodeId) {
        String form = "grant_type=" + enc("urn:ietf:params:oauth:grant-type:token-exchange")
                + "&subject_token=" + enc(loginToken)
                + "&subject_token_type=" + enc("urn:ietf:params:oauth:token-type:access_token")
                + "&node=" + enc(nodeId);
        String basic = Base64.getEncoder()
                .encodeToString((clientId + ":" + clientSecret).getBytes(StandardCharsets.UTF_8));

        HttpRequest request = HttpRequest.newBuilder(URI.create(tokenUrl))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Authorization", "Basic " + basic)
                .POST(HttpRequest.BodyPublishers.ofString(form))
                .build();
        try {
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                return Optional.of(MAPPER.readTree(response.body()).path("access_token").asText());
            }
            if (response.body().contains("node_not_assigned")) {
                return Optional.empty();
            }
            throw new IllegalStateException("Token exchange refusé : HTTP " + response.statusCode());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Token exchange interrompu", e);
        } catch (IOException e) {
            throw new IllegalStateException("PingFederate injoignable", e);
        }
    }

    private static String enc(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }
}
```

### 1.6 service/PumaClient.java

Seul point de contact avec PUMA : liste des entités et décisions. L'application vient du yml.

```java
package com.poc.rataweb.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.Map;
import java.util.Optional;

@Service
public class PumaClient {

    private static final Logger log = LoggerFactory.getLogger(PumaClient.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Value("${rataweb.puma.base-url}")
    private String pumaBaseUrl;

    @Value("${rataweb.application-id}")
    private String applicationId;

    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    /** Entités où l'utilisateur a un rôle dans cette application. JSON brut de PUMA. */
    public Optional<String> listNodes(String loginToken) {
        String url = pumaBaseUrl + "/api/contexts/nodes?application="
                + URLEncoder.encode(applicationId, StandardCharsets.UTF_8);
        HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                .timeout(Duration.ofSeconds(30))
                .header("Authorization", "Bearer " + loginToken)
                .GET()
                .build();
        try {
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            if (response.statusCode() == 200) {
                return Optional.of(response.body());
            }
            log.warn("Liste des noeuds PUMA : HTTP {} {}", response.statusCode(), response.body());
            return Optional.empty();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return Optional.empty();
        } catch (Exception e) {
            log.warn("PUMA injoignable pour la liste des noeuds", e);
            return Optional.empty();
        }
    }

    /** Décision PUMA, donc PingAuthorize. Toute erreur vaut refus. */
    public boolean isPermitted(String userToken, String permission, String targetNode) {
        try {
            String body = MAPPER.writeValueAsString(Map.of(
                    "application", applicationId,
                    "permission", permission,
                    "targetNode", targetNode));
            HttpRequest request = HttpRequest.newBuilder(URI.create(pumaBaseUrl + "/api/decisions"))
                    .timeout(Duration.ofSeconds(60))
                    .header("Content-Type", "application/json")
                    .header("Authorization", "Bearer " + userToken)
                    .POST(HttpRequest.BodyPublishers.ofString(body))
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            log.info("Decision PUMA {} sur {} : HTTP {} {}", permission, targetNode,
                    response.statusCode(), response.body());
            return response.statusCode() == 200
                    && MAPPER.readTree(response.body()).path("permitted").asBoolean(false);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("Decision PUMA interrompue, refus par defaut");
            return false;
        } catch (Exception e) {
            log.warn("Decision PUMA indisponible, refus par defaut", e);
            return false;
        }
    }
}
```

### 1.7 dto/Contract.java

```java
package com.poc.rataweb.dto;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public record Contract(Long id, String reference, String customerName, BigDecimal amount,
                       String nodeId, String status, OffsetDateTime createdAt,
                       String approvedBy, OffsetDateTime approvedAt) { }
```

### 1.8 repository/ContractRepository.java

```java
package com.poc.rataweb.repository;

import com.poc.rataweb.dto.Contract;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public class ContractRepository {

    /** Sous-arbre du noeud de contexte (raccourci POC : lecture directe de la hiérarchie PUMA). */
    private static final String SUBTREE = """
            WITH RECURSIVE sub AS (
                SELECT CAST(? AS varchar) AS node_id
              UNION
                SELECT np.node_id FROM public.node_parent np JOIN sub s ON np.parent_id = s.node_id
            )
            """;

    private static final RowMapper<Contract> ROW = (rs, i) -> new Contract(
            rs.getLong("id"), rs.getString("reference"), rs.getString("customer_name"),
            rs.getBigDecimal("amount"), rs.getString("node_id"), rs.getString("status"),
            rs.getObject("created_at", OffsetDateTime.class), rs.getString("approved_by"),
            rs.getObject("approved_at", OffsetDateTime.class));

    private final JdbcTemplate jdbc;

    public ContractRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Contract> findInContext(String contextNode) {
        return jdbc.query(SUBTREE
                + "SELECT c.* FROM rataweb.contract c JOIN sub ON sub.node_id = c.node_id "
                + "ORDER BY c.created_at DESC LIMIT 20", ROW, contextNode);
    }

    /** Vide si le contrat n'existe pas ou s'il est hors du contexte. */
    public Optional<Contract> findInContext(String contextNode, long id) {
        return jdbc.query(SUBTREE
                + "SELECT c.* FROM rataweb.contract c JOIN sub ON sub.node_id = c.node_id "
                + "WHERE c.id = ?", ROW, contextNode, id).stream().findFirst();
    }

    /** Approuve seulement un contrat encore en attente. */
    public boolean approve(long id, String uid) {
        return jdbc.update("UPDATE rataweb.contract SET status = 'APPROVED', approved_by = ?, "
                + "approved_at = now() WHERE id = ? AND status = 'PENDING'", uid, id) == 1;
    }
}
```

### 1.9 controller/ContextController.java

```java
package com.poc.rataweb.controller;

import com.poc.rataweb.service.PumaClient;
import com.poc.rataweb.service.TokenExchangeService;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/context")
public class ContextController {

    public record SelectRequest(String nodeId) { }

    private final TokenExchangeService tokenExchange;
    private final PumaClient puma;

    public ContextController(TokenExchangeService tokenExchange, PumaClient puma) {
        this.tokenExchange = tokenExchange;
        this.puma = puma;
    }

    /** Entités proposées dans la pop-up, filtrées sur l'application du yml. */
    @GetMapping("/nodes")
    public ResponseEntity<String> nodes(JwtAuthenticationToken token) {
        return puma.listNodes(token.getToken().getTokenValue())
                .map(json -> ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(json))
                .orElseGet(() -> ResponseEntity.status(502).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"message\":\"Liste des entites indisponible\"}"));
    }

    @PostMapping("/select")
    public ResponseEntity<Map<String, String>> select(@RequestBody SelectRequest req,
                                                      JwtAuthenticationToken token) {
        if (req == null || req.nodeId() == null || !req.nodeId().matches("^[A-Za-z0-9_-]{1,20}$")) {
            return ResponseEntity.badRequest().body(Map.of("message", "Noeud invalide"));
        }
        return tokenExchange.exchange(token.getToken().getTokenValue(), req.nodeId())
                .map(t -> ResponseEntity.ok(Map.of("access_token", t)))
                .orElseGet(() -> ResponseEntity.status(403)
                        .body(Map.of("message", "Vous n'avez aucun droit sur cette entité")));
    }
}
```

### 1.10 controller/ContractController.java

```java
package com.poc.rataweb.controller;

import com.poc.rataweb.dto.Contract;
import com.poc.rataweb.repository.ContractRepository;
import com.poc.rataweb.service.PumaClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/contracts")
public class ContractController {

    private final ContractRepository contracts;
    private final PumaClient puma;

    @Value("${rataweb.client-id}")
    private String expectedClientId;

    public ContractController(ContractRepository contracts, PumaClient puma) {
        this.contracts = contracts;
        this.puma = puma;
    }

    @GetMapping
    public ResponseEntity<?> list(JwtAuthenticationToken token) {
        String node = contextNode(token);
        if (node == null) {
            return error(400, "Choisissez d'abord une entité");
        }
        if (!puma.isPermitted(raw(token), "contract.read", node)) {
            return error(403, "Vous n'avez pas le droit de consulter les contrats");
        }
        return ResponseEntity.ok(contracts.findInContext(node));
    }

    @PostMapping("/{id}/approve")
    public ResponseEntity<?> approve(@PathVariable long id, JwtAuthenticationToken token) {
        String node = contextNode(token);
        if (node == null) {
            return error(400, "Choisissez d'abord une entité");
        }
        Optional<Contract> contract = contracts.findInContext(node, id);
        if (contract.isEmpty()) {
            return error(404, "Contrat introuvable");
        }
        if (!puma.isPermitted(raw(token), "contract.approve", contract.get().nodeId())) {
            return error(403, "Vous ne pouvez pas approuver ce contrat");
        }
        if (!contracts.approve(id, token.getToken().getSubject())) {
            return error(409, "Ce contrat est déjà approuvé");
        }
        return ResponseEntity.ok(Map.of(
                "message", "Contrat approuvé",
                "contract", contracts.findInContext(node, id).orElseThrow()));
    }

    /** Seul un token de contexte Rataweb (issu du token exchange) est accepté ici. */
    private String contextNode(JwtAuthenticationToken token) {
        if (!expectedClientId.equals(token.getToken().getClaimAsString("client_id"))) {
            return null;
        }
        return token.getToken().getClaimAsString("node");
    }

    private static String raw(JwtAuthenticationToken token) {
        return token.getToken().getTokenValue();
    }

    private static ResponseEntity<Map<String, String>> error(int status, String message) {
        return ResponseEntity.status(status).body(Map.of("message", message));
    }
}
```

### 1.11 Compilation et premiers tests

```bash
mvn compile
```

Avec un token de login rataweb-portal dans $LOGIN :

```bash
curl -s -H "Authorization: Bearer $LOGIN" http://localhost:8082/api/context/nodes
```

Attendu : la liste des entités où l'utilisateur a un rôle Rataweb.

---

## Étape 2 : PUMA et PingAuthorize

1. PartnerDecisionService (PUMA) : l'action envoyée au PDP devient la permission.

```java
request.put("action", permission);
```

2. PingAuthorize, politique "PUMA Partenaires" :
   - service PUMA.Applications (parent PUMA) ;
   - actions déclarées : contract.read, contract.approve ;
   - politique appliquée au service, sans filtre d'action ; algorithme "A single deny will override any permit decisions" ; Evaluate All coché ;
   - règle Permit "Permission accordée" : targetInContextDB Greater Than 0 et effectiveRolesDB Greater Than 0 ;
   - export du .SDP et redéploiement.

3. À vérifier : PartnerApiController lit uid dans le claim sub et contextNode dans le claim node du token reçu.

---

## Étape 3 : front Rataweb (port 4300)

### 3.1 Génération

```bash
cd rataweb-front
ng version
ng generate component pages/home --type=component --skip-tests
ng generate component pages/callback --type=component --skip-tests
ng generate service core/auth --type=service --skip-tests
ng generate service core/context --type=service --skip-tests
ng generate service core/contract --type=service --skip-tests
ng serve --port 4300
```

Si la version refuse --type pour les services, retirer l'option ou créer les fichiers à la main : seuls les noms de fichiers comptent.

### 3.2 src/app/core/config.ts (à créer)

```typescript
export const CONFIG = {
  authorizeUrl: 'https://localhost:9031/as/authorization.oauth2',
  tokenUrl: 'https://localhost:9031/as/token.oauth2',
  clientId: 'rataweb-portal',
  redirectUri: 'http://localhost:4300/callback',
  ratawebApi: 'http://localhost:8082/api'
};
```

### 3.3 src/app/core/auth.service.ts

```typescript
import { Injectable } from '@angular/core';
import { CONFIG } from './config';

const LOGIN_TOKEN = 'rw_login_token';
const CONTEXT_TOKEN = 'rw_context_token';
const VERIFIER = 'rw_pkce_verifier';
const STATE = 'rw_oauth_state';

@Injectable({ providedIn: 'root' })
export class AuthService {

  async login(): Promise<void> {
    const verifier = this.base64Url(crypto.getRandomValues(new Uint8Array(64)));
    const state = this.base64Url(crypto.getRandomValues(new Uint8Array(24)));
    sessionStorage.setItem(VERIFIER, verifier);
    sessionStorage.setItem(STATE, state);
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier));
    const params = new URLSearchParams({
      response_type: 'code',
      client_id: CONFIG.clientId,
      redirect_uri: CONFIG.redirectUri,
      code_challenge: this.base64Url(new Uint8Array(digest)),
      code_challenge_method: 'S256',
      state
    });
    window.location.href = `${CONFIG.authorizeUrl}?${params}`;
  }

  async handleCallback(code: string, state: string | null): Promise<void> {
    if (!state || state !== sessionStorage.getItem(STATE)) {
      throw new Error('Réponse OAuth invalide (state)');
    }
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: CONFIG.redirectUri,
      client_id: CONFIG.clientId,
      code_verifier: sessionStorage.getItem(VERIFIER) ?? ''
    });
    const resp = await fetch(CONFIG.tokenUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body
    });
    if (!resp.ok) {
      throw new Error(`Échec de la connexion (${resp.status})`);
    }
    const json = await resp.json();
    sessionStorage.removeItem(VERIFIER);
    sessionStorage.removeItem(STATE);
    sessionStorage.removeItem(CONTEXT_TOKEN);
    sessionStorage.setItem(LOGIN_TOKEN, json.access_token);
  }

  loginToken(): string | null { return sessionStorage.getItem(LOGIN_TOKEN); }
  contextToken(): string | null { return sessionStorage.getItem(CONTEXT_TOKEN); }
  setContextToken(token: string): void { sessionStorage.setItem(CONTEXT_TOKEN, token); }
  isLoggedIn(): boolean { return !!this.loginToken(); }

  logout(): void {
    sessionStorage.clear();
    window.location.href = '/';
  }

  /** Lecture des claims pour l'affichage uniquement : la vérification est faite côté serveur. */
  claims(token: string | null): any {
    if (!token) { return null; }
    try {
      const part = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      return JSON.parse(atob(part));
    } catch {
      return null;
    }
  }

  private base64Url(bytes: Uint8Array): string {
    let text = '';
    bytes.forEach(b => text += String.fromCharCode(b));
    return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
}
```

### 3.4 src/app/core/context.service.ts

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { CONFIG } from './config';

export interface NodeContext {
  nodeId: string;
  label: string;
}

@Injectable({ providedIn: 'root' })
export class ContextService {

  constructor(private auth: AuthService) {}

  /** Le backend Rataweb ajoute lui-même l'application (application.yml). */
  async listNodes(): Promise<NodeContext[]> {
    const resp = await fetch(`${CONFIG.ratawebApi}/context/nodes`, {
      headers: { Authorization: 'Bearer ' + this.auth.loginToken() }
    });
    const body = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      throw new Error(body.message ?? `Liste des entités indisponible (${resp.status})`);
    }
    return body;
  }

  /** Le backend Rataweb fait le token exchange à partir du token de login. */
  async select(nodeId: string): Promise<void> {
    const resp = await fetch(`${CONFIG.ratawebApi}/context/select`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + this.auth.loginToken()
      },
      body: JSON.stringify({ nodeId })
    });
    const body = await resp.json().catch(() => ({}));
    if (!resp.ok) {
      throw new Error(body.message ?? `Erreur ${resp.status}`);
    }
    this.auth.setContextToken(body.access_token);
  }

  currentNode(): string | null {
    return this.auth.claims(this.auth.contextToken())?.node ?? null;
  }

  currentRoles(): string[] {
    return this.auth.claims(this.auth.contextToken())?.roles ?? [];
  }
}
```

### 3.5 src/app/core/contract.service.ts

```typescript
import { Injectable } from '@angular/core';
import { AuthService } from './auth.service';
import { CONFIG } from './config';

export interface Contract {
  id: number;
  reference: string;
  customerName: string;
  amount: number;
  nodeId: string;
  status: 'PENDING' | 'APPROVED';
  createdAt: string;
  approvedBy: string | null;
  approvedAt: string | null;
}

@Injectable({ providedIn: 'root' })
export class ContractService {

  constructor(private auth: AuthService) {}

  async list(): Promise<Contract[]> {
    return this.call('/contracts', 'GET');
  }

  async approve(id: number): Promise<{ message: string; contract: Contract }> {
    return this.call(`/contracts/${id}/approve`, 'POST');
  }

  private async call(path: string, method: string): Promise<any> {
    const resp = await fetch(`${CONFIG.ratawebApi}${path}`, {
      method,
      headers: { Authorization: 'Bearer ' + this.auth.contextToken() }
    });
    const body = await resp.json().catch(() => ({}));
    if (resp.status === 401) {
      throw new Error('Session expirée, reconnectez-vous');
    }
    if (!resp.ok) {
      throw new Error(body.message ?? `Erreur ${resp.status}`);
    }
    return body;
  }
}
```

### 3.6 src/app/pages/callback/callback.component.ts

Les fichiers .html et .css générés pour callback peuvent être supprimés.

```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({
  selector: 'app-callback',
  standalone: true,
  template: `<p style="padding: 24px">{{ message }}</p>`
})
export class CallbackComponent implements OnInit {

  message = 'Connexion en cours...';

  constructor(private auth: AuthService, private router: Router) {}

  async ngOnInit(): Promise<void> {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');
    if (!code) {
      this.message = params.get('error_description') ?? 'Code OAuth absent';
      return;
    }
    try {
      await this.auth.handleCallback(code, params.get('state'));
      await this.router.navigateByUrl('/');
    } catch (e: any) {
      this.message = e.message;
    }
  }
}
```

### 3.7 src/app/pages/home/home.component.ts

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { ContextService, NodeContext } from '../../core/context.service';
import { Contract, ContractService } from '../../core/contract.service';

@Component({
  selector: 'app-home',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './home.component.html',
  styleUrls: ['./home.component.css']
})
export class HomeComponent implements OnInit {

  pickerVisible = false;
  nodes: NodeContext[] = [];
  selected = '';
  pickerError = '';

  showContracts = false;
  contracts: Contract[] = [];
  loading = false;
  busyId: number | null = null;
  info = '';
  error = '';

  constructor(public auth: AuthService,
              public context: ContextService,
              private contractService: ContractService) {}

  async ngOnInit(): Promise<void> {
    if (!this.auth.isLoggedIn()) {
      await this.auth.login();
      return;
    }
    if (!this.context.currentNode()) {
      await this.openPicker();
    }
  }

  async openPicker(): Promise<void> {
    this.pickerVisible = true;
    this.selected = '';
    this.pickerError = '';
    try {
      this.nodes = await this.context.listNodes();
      if (this.nodes.length === 0) {
        this.pickerError = 'Aucune entité ne vous est affectée dans Rataweb.';
      }
    } catch (e: any) {
      this.pickerError = e.message;
    }
  }

  async confirmContext(): Promise<void> {
    try {
      await this.context.select(this.selected);
      this.pickerVisible = false;
      this.showContracts = false;
      this.contracts = [];
      this.info = '';
      this.error = '';
    } catch (e: any) {
      this.pickerError = e.message;
    }
  }

  async loadContracts(): Promise<void> {
    this.showContracts = true;
    this.loading = true;
    this.info = '';
    this.error = '';
    try {
      this.contracts = await this.contractService.list();
    } catch (e: any) {
      this.contracts = [];
      this.error = e.message;
    } finally {
      this.loading = false;
    }
  }

  async approve(contract: Contract): Promise<void> {
    this.busyId = contract.id;
    this.info = '';
    this.error = '';
    try {
      const result = await this.contractService.approve(contract.id);
      this.contracts = this.contracts.map(c => c.id === contract.id ? result.contract : c);
      this.info = `${result.message} : ${contract.reference}`;
    } catch (e: any) {
      this.error = e.message;
    } finally {
      this.busyId = null;
    }
  }

  logout(): void {
    this.auth.logout();
  }
}
```

### 3.8 src/app/pages/home/home.component.html

```html
<header class="bar">
  <strong>Rataweb</strong>
  <button (click)="loadContracts()" [disabled]="!context.currentNode()">Contrats</button>
  <span class="spacer"></span>
  <span *ngIf="context.currentNode()" class="ctx">
    Entité {{ context.currentNode() }} | Rôles {{ context.currentRoles().join(', ') }}
  </span>
  <button (click)="openPicker()">Changer d'entité</button>
  <button (click)="logout()">Déconnexion</button>
</header>

<main>
  <p class="info" *ngIf="info">{{ info }}</p>
  <p class="error" *ngIf="error">{{ error }}</p>

  <section *ngIf="showContracts">
    <h2>Contrats</h2>
    <p *ngIf="loading">Chargement...</p>
    <table *ngIf="!loading && contracts.length">
      <thead>
        <tr>
          <th>Référence</th><th>Client</th><th>Montant</th><th>Entité</th>
          <th>Créé le</th><th>Statut</th><th></th>
        </tr>
      </thead>
      <tbody>
        <tr *ngFor="let c of contracts">
          <td>{{ c.reference }}</td>
          <td>{{ c.customerName }}</td>
          <td>{{ c.amount | number:'1.2-2' }} EUR</td>
          <td>{{ c.nodeId }}</td>
          <td>{{ c.createdAt | date:'dd/MM/yyyy' }}</td>
          <td>{{ c.status === 'APPROVED' ? 'Approuvé par ' + c.approvedBy : 'En attente' }}</td>
          <td>
            <button *ngIf="c.status === 'PENDING'" (click)="approve(c)" [disabled]="busyId === c.id">
              {{ busyId === c.id ? 'Vérification...' : 'Approuver' }}
            </button>
          </td>
        </tr>
      </tbody>
    </table>
    <p *ngIf="!loading && !contracts.length && !error">Aucun contrat pour cette entité.</p>
  </section>
</main>

<div class="overlay" *ngIf="pickerVisible">
  <div class="dialog">
    <h3>Choisissez votre entité</h3>
    <select [(ngModel)]="selected" name="node">
      <option value="">Choisir...</option>
      <option *ngFor="let n of nodes" [value]="n.nodeId">{{ n.label }} ({{ n.nodeId }})</option>
    </select>
    <p class="error" *ngIf="pickerError">{{ pickerError }}</p>
    <button (click)="confirmContext()" [disabled]="!selected">Continuer</button>
    <button *ngIf="context.currentNode()" (click)="pickerVisible = false">Annuler</button>
  </div>
</div>
```

### 3.9 src/app/pages/home/home.component.css

```css
.bar { display: flex; gap: 12px; align-items: center; padding: 10px 16px; background: #1f3a5f; color: #fff; }
.spacer { flex: 1; }
.ctx { font-size: 13px; }
main { padding: 16px; font-family: sans-serif; }
table { border-collapse: collapse; width: 100%; }
th, td { border-bottom: 1px solid #ddd; padding: 8px; text-align: left; }
.info { color: #1b7f3b; }
.error { color: #b00020; }
.overlay { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.4); display: flex; align-items: center; justify-content: center; }
.dialog { width: 360px; background: #fff; padding: 20px; border-radius: 6px; }
.dialog select, .dialog button { width: 100%; padding: 8px; margin-top: 10px; }
```

### 3.10 src/app/app.routes.ts

```typescript
import { Routes } from '@angular/router';
import { HomeComponent } from './pages/home/home.component';
import { CallbackComponent } from './pages/callback/callback.component';

export const routes: Routes = [
  { path: 'callback', component: CallbackComponent },
  { path: '', component: HomeComponent },
  { path: '**', redirectTo: '' }
];
```

### 3.11 Template du composant racine

Dans app.html ou app.component.html selon la version, remplacer tout le contenu par :

```html
<router-outlet></router-outlet>
```

---

## Étape 4 : PingFederate, client rataweb-portal

- redirect URI : http://localhost:4300/callback ;
- Authorization Code coché, PKCE requis ;
- Bypass Authorization Approval coché ;
- origine http://localhost:4300 autorisée dans les réglages CORS du serveur d'autorisation (sinon l'échange du code est bloqué par le navigateur).

Rappel : rataweb-backend utilise JWTAccessToken (HMAC, clé poc-key), en Token Exchange seul, avec secret.

---

## Étape 5 : scénario de démonstration

1. PUMA, thomas.martin, contexte Roller 5 : créer julia.weber avec FINANCING_ADVISOR (R15), application A3, sur AB (2700013).
2. Rataweb, julia.weber : choisir 2700013, cliquer sur "Contrats". Attendu : les 5 contrats de 2700013.
3. Cliquer sur "Approuver". Attendu : "Vous ne pouvez pas approuver ce contrat", statut inchangé en base.
4. PUMA : ajouter FINANCING_SUPERVISOR (R16) à julia.weber sur 2700013.
5. Rataweb, sans se reconnecter : cliquer de nouveau sur "Approuver". Attendu : "Contrat approuvé", statut APPROVED en base.

Message de démo : le droit change sans redéploiement ni nouveau token, parce que le PDP lit l'état réel de la base à chaque décision.

---

## Points ouverts

| Point | État |
|---|---|
| Latence des décisions (10 à 15 s) | À traiter avant la démo |
| Token de contexte dans le navigateur | BFF prévu après la démo, comme pour PUMA |
| Token Rataweb portant les rôles de toutes les applications du noeud | Filtre par application ou audience, après la démo |
| Lecture directe de node_parent par Rataweb | Raccourci POC ; à remplacer par une API hiérarchie de PUMA |
| Client secrets visibles en clair | Variables d'environnement ; régénérer après la démo |
| Certificat PingFederate accepté sans vérification (InsecureSsl) | POC uniquement |
