# Rataweb : application partenaire de démonstration

Version du 04/10/2026. Rataweb est une application métier de démonstration. Elle consomme PUMA (choix du contexte, décision d'autorisation) mais ne fait pas partie du POC PUMA.

## Principes

| Sujet | Choix |
|---|---|
| Base | Une seule instance PostgreSQL, base postgres, deux schémas : public pour PUMA, rataweb pour le partenaire |
| Isolation | Rataweb se connecte avec son propre compte (rataweb_app), propriétaire du schéma rataweb, sans aucun droit sur les tables PUMA |
| Application | A3 déclarée une seule fois, dans application.yml du backend Rataweb |
| Token de contexte | Il reste dans le backend Rataweb (BFF). Le front ne garde que son token de login et l'identifiant du noeud choisi |
| Décision | Toute action passe par PUMA puis PingAuthorize. Toute erreur vaut refus |
| Écriture | Le statut d'un contrat ne change que si la décision est PERMIT |

Parcours : login (rataweb-portal, PKCE), pop-up de choix de l'entité, token exchange par le backend Rataweb (rataweb-backend), liste des contrats, bouton "Approuver".

Fichiers à supprimer de l'ancienne version du backend Rataweb : controller/ActionController.java, controller/ContextController.java, service/TokenExchangeService.java, config/CorsFilter.java s'il existe. Ils sont remplacés ci-dessous.

---

## Étape 0 : schéma public (PUMA)

Rien à ajouter dans schema.sql : aucune table ne change. Les ajouts sont des données du catalogue PUMA, lues par PingFederate et PingAuthorize.

### 0.1 Exécution immédiate dans pgAdmin (connecté à la base postgres)

```sql
BEGIN;

SELECT id, code FROM public.permission WHERE id IN ('P23', 'P24');               -- attendu : 0 ligne
SELECT id, code, application_id FROM public.app_role WHERE id IN ('R15', 'R16');  -- attendu : A3

INSERT INTO public.permission (id, code, label, application_id) VALUES
  ('P23', 'contract.read',    'Consulter les contrats', 'A3'),
  ('P24', 'contract.approve', 'Approuver un contrat',   'A3')
ON CONFLICT (id) DO NOTHING;

-- R15 consulte, R16 consulte et approuve
INSERT INTO public.role_permission (role_id, permission_id, granted) VALUES
  ('R15', 'P23', true), ('R16', 'P23', true), ('R16', 'P24', true)
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Rataweb ouvert sur les vendors de la démo (la vue exige le noeud exact)
INSERT INTO public.node_application (node_id, application_id)
SELECT n, 'A3' FROM unnest(ARRAY['2700013','2700010','2700011','2700015','2672749']) AS n
ON CONFLICT (node_id, application_id) DO NOTHING;

SELECT rp.role_id, p.code FROM public.role_permission rp
JOIN public.permission p ON p.id = rp.permission_id
WHERE p.id IN ('P23', 'P24') ORDER BY 1, 2;

COMMIT;  -- ou ROLLBACK si un contrôle est faux
```

Attendu : R15 avec contract.read ; R16 avec contract.read et contract.approve.

### 0.2 Même ajout dans data.sql du backend PUMA (à la fin du fichier)

Pour qu'une base reconstruite contienne aussi ces lignes. Rejouable grâce à ON CONFLICT.

```sql
-- Rataweb : permissions des contrats
INSERT INTO permission (id, code, label, application_id) VALUES
  ('P23', 'contract.read',    'Consulter les contrats', 'A3'),
  ('P24', 'contract.approve', 'Approuver un contrat',   'A3')
ON CONFLICT (id) DO NOTHING;

INSERT INTO role_permission (role_id, permission_id, granted) VALUES
  ('R15', 'P23', true), ('R16', 'P23', true), ('R16', 'P24', true)
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO node_application (node_id, application_id) VALUES
  ('2700013', 'A3'), ('2700010', 'A3'), ('2700011', 'A3'), ('2700015', 'A3'), ('2672749', 'A3')
ON CONFLICT (node_id, application_id) DO NOTHING;
```

---

## Étape 1 : schéma rataweb (partenaire)

### 1.1 Création du compte et du schéma (pgAdmin, connecté en postgres, une seule fois)

```sql
CREATE ROLE rataweb_app LOGIN PASSWORD 'rataweb';
CREATE SCHEMA IF NOT EXISTS rataweb AUTHORIZATION rataweb_app;
```

Équivalent dans l'interface pgAdmin : base postgres, clic droit sur Schemas, Create, Schema ; Name = rataweb ; Owner = rataweb_app.

La table n'est pas créée ici : c'est le backend Rataweb qui la crée au démarrage (étape 2.3).

### 1.2 Contrôle de l'isolation

Ouvre une connexion pgAdmin avec l'utilisateur rataweb_app sur la base postgres, puis :

```sql
SELECT count(*) FROM public.node;
```

Attendu : permission denied. Rataweb ne peut pas lire les tables de PUMA.

---

## Étape 2 : backend Rataweb (port 8082, package com.poc.rataweb)

### 2.1 pom.xml

```xml
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-security</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-oauth2-resource-server</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-jdbc</artifactId></dependency>
<dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
```

### 2.2 src/main/resources/application.yml (remplace tout)

Le schéma est fixé par currentSchema dans l'URL : toutes les requêtes non qualifiées du backend Rataweb visent le schéma rataweb.

```yaml
server:
  port: 8082

spring:
  datasource:
    url: jdbc:postgresql://localhost:5432/postgres?currentSchema=rataweb
    username: rataweb_app
    password: ${RATAWEB_DB_PASSWORD:rataweb}
  sql:
    init:
      mode: always

logging:
  level:
    com.poc.rataweb: DEBUG

rataweb:
  cors-origin: http://localhost:4300
  # Identifiant de l'application dans PUMA : filtre de la pop-up et décisions
  application-id: A3
  # Client OAuth du front (token de login)
  portal-client-id: rataweb-portal
  token-url: https://localhost:9031/as/token.oauth2
  # Client OAuth du backend (token exchange)
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

### 2.3 src/main/resources/schema.sql

Exécuté à chaque démarrage, dans le schéma rataweb. Rejouable.

```sql
CREATE TABLE IF NOT EXISTS contract (
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
```

### 2.4 src/main/resources/data.sql

```sql
INSERT INTO contract (reference, customer_name, amount, node_id, created_at) VALUES
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
```

### 2.5 config/SecurityConfig.java

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
        config.setAllowedHeaders(List.of("Authorization", "Content-Type", "X-Context-Node"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

### 2.6 util/InsecureSsl.java

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

### 2.7 service/TokenExchangeService.java

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

### 2.8 service/ContextResolver.java (BFF)

Le token de contexte ne sort jamais du backend. Il est rangé en mémoire sous la clé "sub du token de login vérifié + noeud". S'il est absent ou expiré, le backend refait le token exchange avec le token de login.

```java
package com.poc.rataweb.service;

import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class ContextResolver {

    private final TokenExchangeService tokenExchange;
    private final JwtDecoder jwtDecoder;
    private final Map<String, Jwt> cache = new ConcurrentHashMap<>();

    public ContextResolver(TokenExchangeService tokenExchange, JwtDecoder jwtDecoder) {
        this.tokenExchange = tokenExchange;
        this.jwtDecoder = jwtDecoder;
    }

    /** Token de contexte pour ce noeud, ou vide si PingFederate refuse le noeud. */
    public Optional<Jwt> resolve(Jwt loginToken, String nodeId) {
        String key = loginToken.getSubject() + "|" + nodeId;
        Jwt cached = cache.get(key);
        if (cached != null && cached.getExpiresAt() != null
                && cached.getExpiresAt().isAfter(Instant.now().plusSeconds(30))) {
            return Optional.of(cached);
        }
        cache.remove(key);
        Optional<Jwt> fresh = tokenExchange.exchange(loginToken.getTokenValue(), nodeId)
                .map(jwtDecoder::decode);
        fresh.ifPresent(jwt -> cache.put(key, jwt));
        return fresh;
    }
}
```

### 2.9 service/PumaClient.java

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

    /** Décision PUMA, donc PingAuthorize, avec le token de contexte. Toute erreur vaut refus. */
    public boolean isPermitted(String contextToken, String permission, String targetNode) {
        try {
            String body = MAPPER.writeValueAsString(Map.of(
                    "application", applicationId,
                    "permission", permission,
                    "targetNode", targetNode));
            HttpRequest request = HttpRequest.newBuilder(URI.create(pumaBaseUrl + "/api/decisions"))
                    .timeout(Duration.ofSeconds(60))
                    .header("Content-Type", "application/json")
                    .header("Authorization", "Bearer " + contextToken)
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

### 2.10 dto/Contract.java

```java
package com.poc.rataweb.dto;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public record Contract(Long id, String reference, String customerName, BigDecimal amount,
                       String nodeId, String status, OffsetDateTime createdAt,
                       String approvedBy, OffsetDateTime approvedAt) { }
```

### 2.11 repository/ContractRepository.java

Rataweb ne connaît pas la hiérarchie : il affiche les contrats de l'entité choisie.

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

    private static final RowMapper<Contract> ROW = (rs, i) -> new Contract(
            rs.getLong("id"), rs.getString("reference"), rs.getString("customer_name"),
            rs.getBigDecimal("amount"), rs.getString("node_id"), rs.getString("status"),
            rs.getObject("created_at", OffsetDateTime.class), rs.getString("approved_by"),
            rs.getObject("approved_at", OffsetDateTime.class));

    private final JdbcTemplate jdbc;

    public ContractRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Contract> findByNode(String nodeId) {
        return jdbc.query("SELECT * FROM contract WHERE node_id = ? "
                + "ORDER BY created_at DESC LIMIT 20", ROW, nodeId);
    }

    /** Vide si le contrat n'existe pas ou n'appartient pas à l'entité. */
    public Optional<Contract> findByNodeAndId(String nodeId, long id) {
        return jdbc.query("SELECT * FROM contract WHERE node_id = ? AND id = ?",
                ROW, nodeId, id).stream().findFirst();
    }

    /** Approuve seulement un contrat encore en attente. */
    public boolean approve(long id, String uid) {
        return jdbc.update("UPDATE contract SET status = 'APPROVED', approved_by = ?, "
                + "approved_at = now() WHERE id = ? AND status = 'PENDING'", uid, id) == 1;
    }
}
```

### 2.12 controller/ContextController.java

```java
package com.poc.rataweb.controller;

import com.poc.rataweb.service.ContextResolver;
import com.poc.rataweb.service.PumaClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/context")
public class ContextController {

    public record SelectRequest(String nodeId) { }

    private final ContextResolver resolver;
    private final PumaClient puma;

    @Value("${rataweb.portal-client-id}")
    private String portalClientId;

    public ContextController(ContextResolver resolver, PumaClient puma) {
        this.resolver = resolver;
        this.puma = puma;
    }

    /** Entités proposées dans la pop-up, filtrées sur l'application du yml. */
    @GetMapping("/nodes")
    public ResponseEntity<String> nodes(JwtAuthenticationToken token) {
        if (!isPortalToken(token.getToken())) {
            return ResponseEntity.status(403).contentType(MediaType.APPLICATION_JSON)
                    .body("{\"message\":\"Token de login Rataweb attendu\"}");
        }
        return puma.listNodes(token.getToken().getTokenValue())
                .map(json -> ResponseEntity.ok().contentType(MediaType.APPLICATION_JSON).body(json))
                .orElseGet(() -> ResponseEntity.status(502).contentType(MediaType.APPLICATION_JSON)
                        .body("{\"message\":\"Liste des entites indisponible\"}"));
    }

    /** Token exchange côté serveur. Le front ne reçoit que le noeud et les rôles. */
    @PostMapping("/select")
    public ResponseEntity<Map<String, Object>> select(@RequestBody SelectRequest req,
                                                      JwtAuthenticationToken token) {
        if (!isPortalToken(token.getToken())) {
            return ResponseEntity.status(403).body(Map.of("message", "Token de login Rataweb attendu"));
        }
        if (req == null || req.nodeId() == null || !req.nodeId().matches("^[A-Za-z0-9_-]{1,20}$")) {
            return ResponseEntity.badRequest().body(Map.of("message", "Noeud invalide"));
        }
        return resolver.resolve(token.getToken(), req.nodeId())
                .map(context -> {
                    List<String> roles = context.getClaimAsStringList("roles");
                    return ResponseEntity.ok(Map.<String, Object>of(
                            "node", context.getClaimAsString("node"),
                            "roles", roles != null ? roles : List.of()));
                })
                .orElseGet(() -> ResponseEntity.status(403)
                        .body(Map.of("message", "Vous n'avez aucun droit sur cette entité")));
    }

    private boolean isPortalToken(Jwt jwt) {
        return portalClientId.equals(jwt.getClaimAsString("client_id"));
    }
}
```

### 2.13 controller/ContractController.java

Le front envoie son token de login et l'en-tête X-Context-Node. Le backend retrouve le token de contexte et l'utilise pour la décision.

```java
package com.poc.rataweb.controller;

import com.poc.rataweb.dto.Contract;
import com.poc.rataweb.repository.ContractRepository;
import com.poc.rataweb.service.ContextResolver;
import com.poc.rataweb.service.PumaClient;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/contracts")
public class ContractController {

    private static final String HEADER = "X-Context-Node";

    private final ContractRepository contracts;
    private final ContextResolver resolver;
    private final PumaClient puma;

    @Value("${rataweb.portal-client-id}")
    private String portalClientId;

    public ContractController(ContractRepository contracts, ContextResolver resolver, PumaClient puma) {
        this.contracts = contracts;
        this.resolver = resolver;
        this.puma = puma;
    }

    @GetMapping
    public ResponseEntity<?> list(JwtAuthenticationToken token,
                                  @RequestHeader(value = HEADER, required = false) String node) {
        ResponseEntity<Map<String, String>> invalid = checkRequest(token, node);
        if (invalid != null) {
            return invalid;
        }
        Optional<Jwt> context = resolver.resolve(token.getToken(), node);
        if (context.isEmpty()) {
            return error(403, "Vous n'avez aucun droit sur cette entité");
        }
        if (!puma.isPermitted(context.get().getTokenValue(), "contract.read", node)) {
            return error(403, "Vous n'avez pas le droit de consulter les contrats");
        }
        return ResponseEntity.ok(contracts.findByNode(node));
    }

    @PostMapping("/{id}/approve")
    public ResponseEntity<?> approve(@PathVariable long id, JwtAuthenticationToken token,
                                     @RequestHeader(value = HEADER, required = false) String node) {
        ResponseEntity<Map<String, String>> invalid = checkRequest(token, node);
        if (invalid != null) {
            return invalid;
        }
        Optional<Jwt> context = resolver.resolve(token.getToken(), node);
        if (context.isEmpty()) {
            return error(403, "Vous n'avez aucun droit sur cette entité");
        }
        Optional<Contract> contract = contracts.findByNodeAndId(node, id);
        if (contract.isEmpty()) {
            return error(404, "Contrat introuvable");
        }
        if (!puma.isPermitted(context.get().getTokenValue(), "contract.approve", contract.get().nodeId())) {
            return error(403, "Vous ne pouvez pas approuver ce contrat");
        }
        if (!contracts.approve(id, token.getToken().getSubject())) {
            return error(409, "Ce contrat est déjà approuvé");
        }
        return ResponseEntity.ok(Map.of(
                "message", "Contrat approuvé",
                "contract", contracts.findByNodeAndId(node, id).orElseThrow()));
    }

    /** Token de login du portail Rataweb et noeud bien formé. Null si tout va bien. */
    private ResponseEntity<Map<String, String>> checkRequest(JwtAuthenticationToken token, String node) {
        if (!portalClientId.equals(token.getToken().getClaimAsString("client_id"))) {
            return error(403, "Token de login Rataweb attendu");
        }
        if (node == null || !node.matches("^[A-Za-z0-9_-]{1,20}$")) {
            return error(400, "Choisissez d'abord une entité");
        }
        return null;
    }

    private static ResponseEntity<Map<String, String>> error(int status, String message) {
        return ResponseEntity.status(status).body(Map.of("message", message));
    }
}
```

### 2.14 Compilation et tests

```bash
mvn compile
```

Démarrer le backend : la table contract est créée dans le schéma rataweb et remplie. Contrôle dans pgAdmin :

```sql
SELECT node_id, status, count(*) FROM rataweb.contract GROUP BY 1, 2 ORDER BY 1;
```

Tests avec un token de login rataweb-portal dans $LOGIN (navigateur, Session Storage, rw_login_token) :

```bash
# Entités de l'utilisateur dans Rataweb
curl -s -H "Authorization: Bearer $LOGIN" http://localhost:8082/api/context/nodes

# Choix du contexte : la réponse contient le noeud et les rôles, jamais de token
curl -s -X POST -H "Authorization: Bearer $LOGIN" -H "Content-Type: application/json" \
  -d '{"nodeId":"2700013"}' http://localhost:8082/api/context/select

# Liste des contrats
curl -s -m 60 -H "Authorization: Bearer $LOGIN" -H "X-Context-Node: 2700013" \
  http://localhost:8082/api/contracts
```

---

## Étape 3 : PUMA et PingAuthorize

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

3. À vérifier : PartnerApiController lit uid dans le claim sub et contextNode dans le claim node du token reçu (ici le token de contexte Rataweb, signé avec poc-key).

---

## Étape 4 : front Rataweb (port 4300)

Le front ne garde que son token de login et le noeud choisi. "Changer d'entité" rappelle /api/context/select avec le même token de login.

### 4.1 Génération

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

### 4.2 src/app/core/config.ts (à créer)

```typescript
export const CONFIG = {
  authorizeUrl: 'https://localhost:9031/as/authorization.oauth2',
  tokenUrl: 'https://localhost:9031/as/token.oauth2',
  clientId: 'rataweb-portal',
  redirectUri: 'http://localhost:4300/callback',
  ratawebApi: 'http://localhost:8082/api'
};
```

### 4.3 src/app/core/auth.service.ts

```typescript
import { Injectable } from '@angular/core';
import { CONFIG } from './config';

const LOGIN_TOKEN = 'rw_login_token';
const CONTEXT_NODE = 'rw_context_node';
const CONTEXT_ROLES = 'rw_context_roles';
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
    this.clearContext();
    sessionStorage.setItem(LOGIN_TOKEN, json.access_token);
  }

  loginToken(): string | null { return sessionStorage.getItem(LOGIN_TOKEN); }
  isLoggedIn(): boolean { return !!this.loginToken(); }

  setContext(node: string, roles: string[]): void {
    sessionStorage.setItem(CONTEXT_NODE, node);
    sessionStorage.setItem(CONTEXT_ROLES, JSON.stringify(roles));
  }

  contextNode(): string | null { return sessionStorage.getItem(CONTEXT_NODE); }

  contextRoles(): string[] {
    try {
      return JSON.parse(sessionStorage.getItem(CONTEXT_ROLES) ?? '[]');
    } catch {
      return [];
    }
  }

  clearContext(): void {
    sessionStorage.removeItem(CONTEXT_NODE);
    sessionStorage.removeItem(CONTEXT_ROLES);
  }

  logout(): void {
    sessionStorage.clear();
    window.location.href = '/';
  }

  private base64Url(bytes: Uint8Array): string {
    let text = '';
    bytes.forEach(b => text += String.fromCharCode(b));
    return btoa(text).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
}
```

### 4.4 src/app/core/context.service.ts

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

  /** Token exchange fait par le backend : on ne reçoit que le noeud et les rôles. */
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
    this.auth.setContext(body.node, body.roles ?? []);
  }

  currentNode(): string | null {
    return this.auth.contextNode();
  }

  currentRoles(): string[] {
    return this.auth.contextRoles();
  }
}
```

### 4.5 src/app/core/contract.service.ts

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

  /** Token de login et noeud choisi : le backend retrouve lui-même le token de contexte. */
  private async call(path: string, method: string): Promise<any> {
    const resp = await fetch(`${CONFIG.ratawebApi}${path}`, {
      method,
      headers: {
        Authorization: 'Bearer ' + this.auth.loginToken(),
        'X-Context-Node': this.auth.contextNode() ?? ''
      }
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

### 4.6 src/app/pages/callback/callback.component.ts

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

### 4.7 src/app/pages/home/home.component.ts

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

### 4.8 src/app/pages/home/home.component.html

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

### 4.9 src/app/pages/home/home.component.css

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

### 4.10 src/app/app.routes.ts

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

### 4.11 Template du composant racine

Dans app.html ou app.component.html selon la version, remplacer tout le contenu par :

```html
<router-outlet></router-outlet>
```

---

## Étape 5 : PingFederate, client rataweb-portal

- redirect URI : http://localhost:4300/callback ;
- Authorization Code coché, PKCE requis ;
- Bypass Authorization Approval coché ;
- origine http://localhost:4300 autorisée dans les réglages CORS du serveur d'autorisation (sinon l'échange du code est bloqué par le navigateur).

Rappel : rataweb-backend utilise JWTAccessToken (HMAC, clé poc-key), en Token Exchange seul, avec secret.

---

## Étape 6 : scénario de démonstration

1. PUMA, thomas.martin, contexte Roller 5 : créer julia.weber avec FINANCING_ADVISOR (R15), application A3, sur AB (2700013).
2. Rataweb, julia.weber : choisir 2700013, cliquer sur "Contrats". Attendu : les 5 contrats de 2700013.
3. Cliquer sur "Approuver". Attendu : "Vous ne pouvez pas approuver ce contrat", statut inchangé en base.
4. PUMA : ajouter FINANCING_SUPERVISOR (R16) à julia.weber sur 2700013.
5. Rataweb, sans se reconnecter : cliquer de nouveau sur "Approuver". Attendu : "Contrat approuvé", statut APPROVED en base.

Message de démo : le droit change sans redéploiement ni nouveau token, parce que le PDP lit l'état réel de la base à chaque décision. Et le token de contexte ne quitte jamais le serveur.

Remise à zéro avant une nouvelle démo (pgAdmin, en postgres) :

```sql
UPDATE rataweb.contract SET status = 'PENDING', approved_by = NULL, approved_at = NULL;
```

---

## Points ouverts

| Point | État |
|---|---|
| Latence des décisions (10 à 15 s) | À traiter avant la démo |
| Cache des tokens de contexte en mémoire | Perdu au redémarrage, sans impact : nouveau token exchange automatique |
| Token Rataweb portant les rôles de toutes les applications du noeud | Filtre par application ou audience, après la démo |
| Vue d'un superviseur sur les vendors de son entité | Rataweb affiche l'entité choisie ; le sous-arbre viendra d'une API hiérarchie de PUMA |
| Même BFF côté PUMA | Plan 3.3 |
| Client secrets visibles en clair | Variables d'environnement ; régénérer après la démo |
| Certificat PingFederate accepté sans vérification (InsecureSsl) | POC uniquement |
