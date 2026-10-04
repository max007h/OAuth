docker ps --format '{{.Names}}' | grep -i federate
docker exec NOM_DU_CONTENEUR tail -150 /opt/out/instance/log/server.log | grep -i -E "token|exchange|processor|audience"


curl -sk -u "rataweb-backend:$RATAWEB_CLIENT_SECRET" https://localhost:9031/as/token.oauth2 \
  -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token="$LOGIN" \
  -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  -d node=2700013




uid = '${tepp.subject}' AND node_id = '${tepp.node}' AND application_id = 'A3'

#this.get("context.HttpRequest").getObjectValue().getParameter("node")


#r = #this.get("ds.pumaRoles.role_id"), #r != null && #r.getValue() != null



# Rataweb : application partenaire de démonstration

Version du 05/10/2026. Rataweb est une application métier de démonstration. Elle consomme PUMA (choix du contexte, décision d'autorisation) mais ne fait pas partie du POC PUMA.

## Principes

| Sujet | Choix |
|---|---|
| Base | Une instance PostgreSQL, base postgres : schéma public pour PUMA, schéma rataweb pour le partenaire |
| Isolation | Rataweb se connecte avec rataweb_app, propriétaire du schéma rataweb, sans droit sur les tables PUMA |
| Audience | Les tokens Rataweb (login et contexte) portent aud = A3, l'identifiant de l'application dans le catalogue PUMA |
| Identification de l'application | PUMA la déduit du token signé (aud, ou à défaut client_id via le catalogue). L'appelant ne la déclare jamais |
| Token de login | Seul token présent dans le navigateur (client rataweb-portal) |
| Token de contexte | Obtenu par token exchange (client rataweb-backend), il reste dans le backend Rataweb. Un token de login correspond à un seul contexte |
| Modèle de décision | Service = ressource (Rataweb.Contract), action = verbe (read, approve), attributs = faits sur la ressource (amount) |
| Catalogue | La permission (contract.approve) est déduite par PUMA de la ressource et de l'action |
| Rôle de la base | PIP : elle fournit des faits (cible dans le contexte, permission effective). La politique décide |
| Règle métier | Approbation plafonnée à 20 000 EUR, refus nommé "Montant au-delà de la délégation" |
| Sécurité | Refus par défaut ; toute erreur vaut refus ; uid, contexte et application viennent du token vérifié |

Les deux backends utilisent le package com.poc.banking.

## Revue de sécurité

| Contrôle | Où |
|---|---|
| Signature et expiration de chaque token | Spring Security (Rataweb et PUMA), clé HS256 poc-key |
| Le token est destiné à Rataweb | Rataweb vérifie aud = A3 (RFC 9068) |
| Le front ne détient pas le token de contexte | ContextResolver (Rataweb) |
| Le contexte demandé est autorisé | PingFederate refuse le token exchange sans rôle sur le noeud (Issuance Criteria) |
| L'application ne peut pas être falsifiée | PUMA la déduit du token signé ; la requête n'a pas de champ application |
| Pas d'incohérence action / permission | PUMA déduit la permission de la ressource et de l'action |
| Les attributs de ressource ne masquent pas l'identité | Noms réservés refusés (uid, contextNode, targetNode, targetApplication, permission) |
| Cible dans le contexte, permission effective, spécialisation | Règles PingAuthorize, à partir des faits du PIP |
| Règle métier (plafond) | Politique PingAuthorize, sans code dans les applications |
| Refus par défaut | PingAuthorize, PUMA et Rataweb |

---

## Étape 0 : catalogue PUMA (schéma public)

Rien à ajouter dans schema.sql de PUMA. Les ajouts sont des données.

### 0.1 Exécution immédiate dans pgAdmin (base postgres, utilisateur postgres)

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

-- Client du backend Rataweb, utilisé tant que l'audience n'est pas dans les tokens
UPDATE public.application SET client_id = 'rataweb-backend' WHERE id = 'A3';

-- Contrôles
SELECT rp.role_id, p.code FROM public.role_permission rp
JOIN public.permission p ON p.id = rp.permission_id
WHERE p.id IN ('P23', 'P24') ORDER BY 1, 2;

SELECT id, name, client_id FROM public.application WHERE id = 'A3';  -- attendu : A3 | Rataweb | rataweb-backend

COMMIT;  -- ou ROLLBACK si un contrôle est faux
```

Le name de A3 doit être exactement Rataweb : c'est le nom du service parent dans PingAuthorize.

### 0.2 Même ajout à la fin de data.sql du backend PUMA

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

UPDATE application SET client_id = 'rataweb-backend' WHERE id = 'A3';
```

---

## Étape 1 : schéma rataweb (partenaire)

### 1.1 Compte et schéma (pgAdmin, utilisateur postgres, une seule fois)

```sql
CREATE ROLE rataweb_app LOGIN PASSWORD 'rataweb';
CREATE SCHEMA IF NOT EXISTS rataweb AUTHORIZATION rataweb_app;
```

Équivalent pgAdmin : base postgres, clic droit sur Schemas, Create, Schema ; Name = rataweb ; Owner = rataweb_app.

### 1.2 Contrôle de l'isolation

Connexion pgAdmin avec rataweb_app sur la base postgres :

```sql
SELECT count(*) FROM public.node;
```

Attendu : permission denied.

---

## Étape 2 : PingFederate, audience dans les tokens Rataweb

Objectif : le token de login (rataweb-portal) et le token de contexte (rataweb-backend) portent aud = A3. Dans PingFederate, l'audience se règle sur l'Access Token Manager (ATM), pas sur le client. On crée donc un ATM dédié à Rataweb. Les libellés peuvent varier légèrement selon la version.

### 2.1 Créer l'ATM JWTAccessToken-A3

Applications, OAuth, Access Token Management, Create New Instance :

| Champ | Valeur |
|---|---|
| Instance Name / ID | JWTAccessToken-A3 |
| Type | JSON Web Tokens |
| Signing | HMAC SHA-256, même clé que JWTAccessToken (poc-key, même Key ID) |
| Audience Claim Value | A3 |
| Issuer Claim Value | identique à JWTAccessToken |
| Token Lifetime | 60 minutes (identique à JWTAccessToken) |
| Access Token Attribute Contract | mêmes attributs que JWTAccessToken (sub, node, roles, et les autres déjà présents) |

La même clé de signature permet à PUMA et Rataweb de vérifier ces tokens sans changement.

### 2.2 Recopier les Access Token Mappings

Applications, OAuth, Access Token Mappings. Pour l'ATM JWTAccessToken-A3, recréer les mêmes mappings que pour JWTAccessToken :

1. Le contexte utilisé au login par rataweb-portal (Default, ou le contrat de la politique d'authentification) : mêmes sources et même fulfillment (sub...).
2. Le contexte Token Exchange Processor Policy puma-context-policy :
   - même source JDBC pumaRoles, même filtre : uid = '${tepp.subject}' AND node_id = '${tepp.node}' ;
   - même fulfillment (sub, node, roles) ;
   - **même Issuance Criteria : ds.pumaRoles.role_id non vide, message node_not_assigned.**

Point de sécurité : sans l'Issuance Criteria, PingFederate émettrait un token de contexte même pour un noeud sans aucun rôle. C'est le contrôle qui ferme la porte au choix d'un mauvais contexte.

### 2.3 Rattacher les clients

Applications, OAuth, Clients :

- rataweb-portal : Default Access Token Manager = JWTAccessToken-A3 ;
- rataweb-backend : Default Access Token Manager = JWTAccessToken-A3.

Ne pas toucher puma-portal ni puma-backend : PUMA garde JWTAccessToken.

### 2.4 Vérification

Se connecter à Rataweb, puis décoder le token de login (Session Storage, rw_login_token) dans le terminal :

```bash
echo "COLLE_LE_TOKEN" | cut -d. -f2 | tr '_-' '/+' | base64 -D 2>/dev/null; echo
```

Attendu : "aud":"A3". Puis choisir une entité : la console Rataweb affiche Token exchange OK. Pour voir l'aud du token de contexte, ajouter temporairement jwt.getAudience() dans le log de ContextResolver.select.

Si le token exchange échoue après ce changement (subject token refusé), vérifier dans le Token Processor pf-jwt-processor qu'aucune audience attendue n'exclut A3.

---

## Étape 3 : PingAuthorize, politique Rataweb Contrats

Les attributs uid, contextNode, targetNode, targetApplication, permission, targetInContextDB et effectiveRolesDB existent déjà (politique PUMA Assignation). On ne les modifie pas.

### 3.1 Trust Framework

1. Services : créer Rataweb (même type que PUMA), puis Contract avec Parent = Rataweb. Résultat : Rataweb.Contract.
2. Actions : créer read et approve.
3. Attributes : créer amount, type Number, resolver Request, sans valeur par défaut.

Si une politique "PUMA Partner Decision", un service PUMA.Applications ou des actions contract.read et contract.approve ont été créés auparavant : les supprimer.

### 3.2 Politique

Policies, racine, Add Policy :

| Champ | Valeur |
|---|---|
| Nom | Rataweb Contrats |
| Applies to | service Rataweb.Contract |
| Combining Algorithm | A single deny will override any permit decisions |
| Evaluate All | coché |

### 3.3 Règles

Pour chaque règle : Add Rule, Applies to = l'action indiquée, When sur ALL, Effect.

| Nom | Applies to | Effect | Conditions |
|---|---|---|---|
| Consultation autorisée | action read | Permit | targetInContextDB Greater Than 0 ; effectiveRolesDB Greater Than 0 |
| Approbation autorisée | action approve | Permit | targetInContextDB Greater Than 0 ; effectiveRolesDB Greater Than 0 ; amount Less Than Or Equal 20000 |
| Montant au-delà de la délégation | action approve | Deny | amount Greater Than 20000 |

Si l'opérateur Less Than Or Equal n'existe pas, utiliser Less Than 20000.01.

Chaque règle Permit contient toutes ses conditions : si l'on retire la règle Deny, la politique reste sûre. La règle Deny nomme la raison du refus dans la trace.

### 3.4 Déploiement et tests directs

Save, export du .SDP, redéploiement. Puis :

```bash
# julia.weber (R15) consulte : PERMIT
curl -sk -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" \
  -d '{"domain":"PUMA","service":"Rataweb.Contract","action":"read",
       "attributes":{"uid":"julia.weber","contextNode":"2700013","targetNode":"2700013",
       "targetApplication":"A3","permission":"contract.read"}}'

# max.walker (R16) approuve 18 500 : PERMIT
curl -sk -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" \
  -d '{"domain":"PUMA","service":"Rataweb.Contract","action":"approve",
       "attributes":{"uid":"max.walker","contextNode":"2700013","targetNode":"2700013",
       "targetApplication":"A3","permission":"contract.approve","amount":18500}}'
```

| uid | action | amount | Attendu |
|---|---|---|---|
| julia.weber | read | | PERMIT |
| max.walker | approve | 18500 | PERMIT |
| max.walker | approve | 24300 | DENY, règle Montant au-delà de la délégation |
| julia.weber | approve | 18500 | NOT_APPLICABLE (R15 n'accorde pas contract.approve) |

---

## Étape 4 : backend PUMA, API de décision pour les partenaires

PUMA ne contient aucune liste de partenaires. L'application est déduite du token : audience d'abord, client_id via le catalogue sinon.

Vérifier l'existant pour remplacer plutôt que dupliquer :

```bash
grep -rln "PartnerApiController\|PartnerDecisionService\|PartnerRegistry" src/main/java/
```

Si PartnerRegistry.java existe, le supprimer, ainsi que tout bloc puma.partner et toute ligne partner-service dans application.yml.

### 4.1 service/PartnerDecisionService.java (remplace l'existant)

```java
package com.poc.banking.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;

/** Décision PingAuthorize pour une ressource d'une application partenaire. Toute erreur vaut refus. */
@Service
public class PartnerDecisionService {

    private static final Logger log = LoggerFactory.getLogger(PartnerDecisionService.class);
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Value("${puma.authz.pdp.base-url}")
    private String baseUrl;

    @Value("${puma.authz.pdp.domain}")
    private String domain;

    private final HttpClient http = HttpClient.newBuilder()
            .sslContext(trustAll())
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    public boolean decide(String uid, String contextNode, String applicationId, String service,
                          String action, String permission, String targetNode,
                          Map<String, Object> resourceAttributes) {
        // Les faits sur la ressource d'abord, l'identité ensuite : elle ne peut pas être écrasée.
        Map<String, Object> attributes = new LinkedHashMap<>(resourceAttributes);
        attributes.put("uid", uid);
        attributes.put("contextNode", contextNode);
        attributes.put("targetNode", targetNode);
        attributes.put("targetApplication", applicationId);
        attributes.put("permission", permission);

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("domain", domain);
        body.put("service", service);
        body.put("action", action);
        body.put("attributes", attributes);

        try {
            HttpRequest request = HttpRequest.newBuilder(URI.create(baseUrl + "/governance-engine"))
                    .timeout(Duration.ofSeconds(60))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(body)))
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            String decision = MAPPER.readTree(response.body()).path("decision").asText();
            log.info("Decision partenaire uid={} contexte={} service={} action={} cible={} attributs={} : {}",
                    uid, contextNode, service, action, targetNode, resourceAttributes, decision);
            return response.statusCode() == 200 && "PERMIT".equalsIgnoreCase(decision);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("Decision partenaire interrompue, refus par defaut");
            return false;
        } catch (Exception e) {
            log.warn("PDP indisponible, refus par defaut", e);
            return false;
        }
    }

    /** POC uniquement : PingAuthorize utilise un certificat auto-signé. */
    private static SSLContext trustAll() {
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

### 4.2 controller/PartnerApiController.java (remplace l'existant)

```java
package com.poc.banking.controller;

import com.poc.banking.service.PartnerDecisionService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

/**
 * Décision pour les applications partenaires.
 * uid, contexte et application viennent du token vérifié, jamais du corps de la requête.
 */
@RestController
@RequestMapping("/api")
public class PartnerApiController {

    public record DecisionRequest(String resource, String action,
                                  String targetNode, Map<String, Object> attributes) { }

    public record DecisionResponse(boolean permitted) { }

    private record Application(String id, String name) { }

    private static final Logger log = LoggerFactory.getLogger(PartnerApiController.class);
    private static final String NAME = "^[A-Za-z]{1,40}$";
    private static final String NODE = "^[A-Za-z0-9_-]{1,20}$";
    private static final Set<String> RESERVED =
            Set.of("uid", "contextNode", "targetNode", "targetApplication", "permission");

    private final PartnerDecisionService decisions;
    private final JdbcTemplate jdbc;

    public PartnerApiController(PartnerDecisionService decisions, JdbcTemplate jdbc) {
        this.decisions = decisions;
        this.jdbc = jdbc;
    }

    @PostMapping("/decisions")
    public ResponseEntity<DecisionResponse> decide(@RequestBody DecisionRequest req,
                                                   JwtAuthenticationToken token) {
        Jwt jwt = token.getToken();
        String uid = jwt.getSubject();
        String contextNode = jwt.getClaimAsString("node");
        if (uid == null || contextNode == null || req == null
                || !matches(req.resource(), NAME) || !matches(req.action(), NAME)
                || !matches(req.targetNode(), NODE)) {
            return deny(400);
        }

        Optional<Application> application = resolveApplication(jwt);
        if (application.isEmpty()) {
            log.warn("Application introuvable pour aud={} client_id={}",
                    jwt.getAudience(), jwt.getClaimAsString("client_id"));
            return deny(403);
        }

        Map<String, Object> resourceAttributes = req.attributes() == null ? Map.of() : req.attributes();
        for (Map.Entry<String, Object> e : resourceAttributes.entrySet()) {
            boolean validValue = e.getValue() instanceof Number || e.getValue() instanceof String;
            if (!matches(e.getKey(), NAME) || RESERVED.contains(e.getKey()) || !validValue) {
                return deny(400);
            }
        }

        String action = req.action().toLowerCase(Locale.ROOT);
        String service = application.get().name() + "." + req.resource();
        // La permission du catalogue est déduite, jamais fournie par l'application.
        String permission = req.resource().toLowerCase(Locale.ROOT) + "." + action;

        boolean permitted = decisions.decide(uid, contextNode, application.get().id(),
                service, action, permission, req.targetNode(), resourceAttributes);
        return ResponseEntity.ok(new DecisionResponse(permitted));
    }

    /**
     * Application du catalogue désignée par le token signé : audience d'abord,
     * client_id ensuite (tant que l'audience n'est pas configurée dans PingFederate).
     */
    private Optional<Application> resolveApplication(Jwt jwt) {
        List<String> audience = jwt.getAudience();
        if (audience != null) {
            for (String aud : audience) {
                List<Application> found = jdbc.query("SELECT id, name FROM application WHERE id = ?",
                        (rs, i) -> new Application(rs.getString("id"), rs.getString("name")), aud);
                if (found.size() == 1) {
                    return Optional.of(found.get(0));
                }
            }
        }
        String clientId = jwt.getClaimAsString("client_id");
        if (clientId == null) {
            return Optional.empty();
        }
        List<Application> found = jdbc.query("SELECT id, name FROM application WHERE client_id = ?",
                (rs, i) -> new Application(rs.getString("id"), rs.getString("name")), clientId);
        return found.size() == 1 ? Optional.of(found.get(0)) : Optional.empty();
    }

    private static boolean matches(String value, String pattern) {
        return value != null && value.matches(pattern);
    }

    private static ResponseEntity<DecisionResponse> deny(int status) {
        return ResponseEntity.status(status).body(new DecisionResponse(false));
    }
}
```

### 4.3 Compilation

```bash
mvn compile
```

Puis redémarrage de PUMA.

---

## Étape 5 : backend Rataweb (port 8082)

Fichiers à supprimer de l'ancienne version : controller/ActionController.java, config/CorsFilter.java. Si DatabaseBootstrap.java ou ContextExceptionHandler.java empêchent le démarrage, les supprimer aussi.

### 5.1 pom.xml

```xml
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-security</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-oauth2-resource-server</artifactId></dependency>
<dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-jdbc</artifactId></dependency>
<dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
```

### 5.2 src/main/resources/application.yml (remplace tout)

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
    com.poc.banking: DEBUG

rataweb:
  cors-origin: http://localhost:4300
  # Identifiant de l'application dans le catalogue PUMA : filtre de la pop-up et audience attendue
  application-id: A3
  # Client OAuth du front (token de login)
  portal-client-id: rataweb-portal
  token-url: https://localhost:9031/as/token.oauth2
  # Client OAuth du backend (token exchange)
  client-id: rataweb-backend
  client-secret: ${RATAWEB_CLIENT_SECRET}
  jwt:
    secret-hex: ${RATAWEB_JWT_SECRET_HEX}
    # Passer à true après l'étape 2 (audience configurée dans PingFederate)
    require-audience: false
  puma:
    base-url: http://localhost:8081
```

Variables d'environnement (configuration de lancement IntelliJ) :

- RATAWEB_CLIENT_SECRET : secret du client rataweb-backend ;
- RATAWEB_JWT_SECRET_HEX : même valeur hex que la clé poc-key de PUMA.

### 5.3 src/main/resources/schema.sql

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

### 5.4 src/main/resources/data.sql

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

### 5.5 config/SecurityConfig.java

Vérifie la signature, l'expiration et, une fois l'étape 2 faite, l'audience.

```java
package com.poc.banking.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtClaimNames;
import org.springframework.security.oauth2.jwt.JwtClaimValidator;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
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

    /** Signature HS256 (poc-key), expiration, et audience A3 si require-audience vaut true. */
    @Bean
    public JwtDecoder jwtDecoder(@Value("${rataweb.jwt.secret-hex}") String secretHex,
                                 @Value("${rataweb.application-id}") String applicationId,
                                 @Value("${rataweb.jwt.require-audience:false}") boolean requireAudience) {
        SecretKey key = new SecretKeySpec(HexFormat.of().parseHex(secretHex), "HmacSHA256");
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
        if (requireAudience) {
            OAuth2TokenValidator<Jwt> audience = new JwtClaimValidator<List<String>>(
                    JwtClaimNames.AUD, aud -> aud != null && aud.contains(applicationId));
            decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                    JwtValidators.createDefault(), audience));
        }
        return decoder;
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

Le même décodeur sert aussi à ContextResolver : avec require-audience à true, un token de contexte sans aud = A3 est refusé, ce qui contrôle aussi la configuration de rataweb-backend.

### 5.6 config/InsecureSsl.java

```java
package com.poc.banking.config;

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

### 5.7 service/TokenExchangeService.java

```java
package com.poc.banking.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.poc.banking.config.InsecureSsl;
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

### 5.8 service/ContextResolver.java (BFF)

```java
package com.poc.banking.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/** Un token de login correspond à un seul token de contexte, rangé sous le jti du token de login. */
@Service
public class ContextResolver {

    private static final Logger log = LoggerFactory.getLogger(ContextResolver.class);

    private record Entry(Jwt context, Instant loginExpiresAt) { }

    private final TokenExchangeService tokenExchange;
    private final JwtDecoder jwtDecoder;
    private final Map<String, Entry> contexts = new ConcurrentHashMap<>();

    public ContextResolver(TokenExchangeService tokenExchange, JwtDecoder jwtDecoder) {
        this.tokenExchange = tokenExchange;
        this.jwtDecoder = jwtDecoder;
    }

    /** Choix d'une entité : remplace le contexte précédent de ce token de login. */
    public Optional<Jwt> select(Jwt login, String nodeId) {
        purgeExpiredLogins();
        Optional<Jwt> context = tokenExchange.exchange(login.getTokenValue(), nodeId)
                .map(jwtDecoder::decode);
        if (context.isPresent()) {
            Jwt jwt = context.get();
            contexts.put(key(login), new Entry(jwt, login.getExpiresAt()));
            log.info("Token exchange OK : sub={} node={} roles={} client_id={} aud={} expire={}",
                    jwt.getSubject(), jwt.getClaimAsString("node"), jwt.getClaimAsStringList("roles"),
                    jwt.getClaimAsString("client_id"), jwt.getAudience(), jwt.getExpiresAt());
        } else {
            contexts.remove(key(login));
            log.info("Token exchange refusé par PingFederate : sub={} node={}", login.getSubject(), nodeId);
        }
        return context;
    }

    /** Contexte courant de ce token de login, renouvelé s'il a expiré. Vide si aucune entité choisie. */
    public Optional<Jwt> current(Jwt login) {
        Entry entry = contexts.get(key(login));
        if (entry == null) {
            return Optional.empty();
        }
        Jwt context = entry.context();
        if (context.getExpiresAt() != null
                && context.getExpiresAt().isAfter(Instant.now().plusSeconds(30))) {
            return Optional.of(context);
        }
        return select(login, context.getClaimAsString("node"));
    }

    private static String key(Jwt login) {
        return login.getId() != null ? login.getId() : login.getTokenValue();
    }

    private void purgeExpiredLogins() {
        Instant now = Instant.now();
        contexts.values().removeIf(e -> e.loginExpiresAt() != null && e.loginExpiresAt().isBefore(now));
    }
}
```

### 5.9 service/PumaClient.java

La requête de décision ne contient pas d'application : PUMA la déduit du token.

```java
package com.poc.banking.service;

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
import java.util.LinkedHashMap;
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
    public boolean isPermitted(String contextToken, String resource, String action,
                               String targetNode, Map<String, Object> resourceAttributes) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("resource", resource);
            body.put("action", action);
            body.put("targetNode", targetNode);
            body.put("attributes", resourceAttributes);

            HttpRequest request = HttpRequest.newBuilder(URI.create(pumaBaseUrl + "/api/decisions"))
                    .timeout(Duration.ofSeconds(60))
                    .header("Content-Type", "application/json")
                    .header("Authorization", "Bearer " + contextToken)
                    .POST(HttpRequest.BodyPublishers.ofString(MAPPER.writeValueAsString(body)))
                    .build();
            HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
            log.info("Decision PUMA {} {} sur {} : HTTP {} {}", resource, action, targetNode,
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

### 5.10 dto/Contract.java

```java
package com.poc.banking.dto;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

public record Contract(Long id, String reference, String customerName, BigDecimal amount,
                       String nodeId, String status, OffsetDateTime createdAt,
                       String approvedBy, OffsetDateTime approvedAt) { }
```

### 5.11 repository/ContractRepository.java

```java
package com.poc.banking.repository;

import com.poc.banking.dto.Contract;
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

### 5.12 controller/ContextController.java

```java
package com.poc.banking.controller;

import com.poc.banking.service.ContextResolver;
import com.poc.banking.service.PumaClient;
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
        return resolver.select(token.getToken(), req.nodeId())
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

### 5.13 controller/ContractController.java

Rataweb fournit la ressource, l'action et les faits (noeud, montant). Il ne décide rien.

```java
package com.poc.banking.controller;

import com.poc.banking.dto.Contract;
import com.poc.banking.repository.ContractRepository;
import com.poc.banking.service.ContextResolver;
import com.poc.banking.service.PumaClient;
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

    private static final String RESOURCE = "Contract";

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
    public ResponseEntity<?> list(JwtAuthenticationToken token) {
        if (!isPortalToken(token)) {
            return error(403, "Token de login Rataweb attendu");
        }
        Optional<Jwt> context = resolver.current(token.getToken());
        if (context.isEmpty()) {
            return noContext();
        }
        String node = context.get().getClaimAsString("node");
        if (!puma.isPermitted(context.get().getTokenValue(), RESOURCE, "read", node, Map.of())) {
            return error(403, "Vous n'avez pas le droit de consulter les contrats");
        }
        return ResponseEntity.ok(contracts.findByNode(node));
    }

    @PostMapping("/{id}/approve")
    public ResponseEntity<?> approve(@PathVariable long id, JwtAuthenticationToken token) {
        if (!isPortalToken(token)) {
            return error(403, "Token de login Rataweb attendu");
        }
        Optional<Jwt> context = resolver.current(token.getToken());
        if (context.isEmpty()) {
            return noContext();
        }
        String node = context.get().getClaimAsString("node");
        Optional<Contract> contract = contracts.findByNodeAndId(node, id);
        if (contract.isEmpty()) {
            return error(404, "Contrat introuvable");
        }
        Map<String, Object> facts = Map.of("amount", contract.get().amount());
        if (!puma.isPermitted(context.get().getTokenValue(), RESOURCE, "approve",
                contract.get().nodeId(), facts)) {
            return error(403, "Vous ne pouvez pas approuver ce contrat");
        }
        if (!contracts.approve(id, token.getToken().getSubject())) {
            return error(409, "Ce contrat est déjà approuvé");
        }
        return ResponseEntity.ok(Map.of(
                "message", "Contrat approuvé",
                "contract", contracts.findByNodeAndId(node, id).orElseThrow()));
    }

    private boolean isPortalToken(JwtAuthenticationToken token) {
        return portalClientId.equals(token.getToken().getClaimAsString("client_id"));
    }

    /** Aucun contexte pour ce token de login (jamais choisi, ou backend redémarré). */
    private static ResponseEntity<Map<String, String>> noContext() {
        return ResponseEntity.status(409).body(Map.of(
                "code", "no_context",
                "message", "Choisissez d'abord une entité"));
    }

    private static ResponseEntity<Map<String, String>> error(int status, String message) {
        return ResponseEntity.status(status).body(Map.of("message", message));
    }
}
```

### 5.14 Compilation et tests

```bash
mvn compile
grep -rn "X-Context-Node\|resolve(\|checkRequest\|partner-name\|partnerName" src/main/java/   # attendu : aucun résultat
```

Contrôle de la table dans pgAdmin :

```sql
SELECT node_id, status, count(*) FROM rataweb.contract GROUP BY 1, 2 ORDER BY 1;
```

Avec un token de login rataweb-portal dans $LOGIN (annexe A) :

```bash
curl -i -H "Authorization: Bearer $LOGIN" http://localhost:8082/api/context/nodes

curl -i -X POST -H "Authorization: Bearer $LOGIN" -H "Content-Type: application/json" \
  -d '{"nodeId":"2700013"}' http://localhost:8082/api/context/select

curl -i -m 60 -H "Authorization: Bearer $LOGIN" http://localhost:8082/api/contracts
```

Un token PUMA est refusé (403, ou 401 une fois require-audience activé). Une réponse vide est un 401 : regarder l'en-tête WWW-Authenticate.

### 5.15 Activation du contrôle d'audience

Après l'étape 2 et la vérification aud = A3 : passer rataweb.jwt.require-audience à true, redémarrer Rataweb, refaire les trois curl. Un token PUMA doit alors être refusé en 401 par Spring Security, avant même les contrôleurs.

---

## Étape 6 : front Rataweb (port 4300, composants standalone)

Le front ne garde que son token de login. "Changer d'entité" rappelle /api/context/select. Le front ne connaît ni l'application, ni les permissions.

### 6.1 Nettoyage et génération

Garder : src/main.ts, src/index.html, src/styles.css, et dans src/app : app.component.ts, .html, .css, app.config.ts, app.routes.ts. Supprimer le reste de src/app.

```bash
cd rataweb-front
ng generate component pages/home --type=component --skip-tests
ng generate component pages/callback --type=component --skip-tests
ng generate service core/auth --skip-tests
ng generate service core/context --skip-tests
ng generate service core/contract --skip-tests
ng serve --port 4300
```

Créer à la main src/app/core/config.ts (6.2). app.config.ts doit contenir au minimum :

```typescript
import { ApplicationConfig } from '@angular/core';
import { provideRouter } from '@angular/router';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [provideRouter(routes)]
};
```

### 6.2 src/app/core/config.ts

```typescript
export const CONFIG = {
  authorizeUrl: 'https://localhost:9031/as/authorization.oauth2',
  tokenUrl: 'https://localhost:9031/as/token.oauth2',
  clientId: 'rataweb-portal',
  redirectUri: 'http://localhost:4300/callback',
  ratawebApi: 'http://localhost:8082/api'
};
```

### 6.3 src/app/core/auth.service.ts

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

  /** Affichage uniquement : le backend ne lit jamais ces valeurs. */
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

### 6.4 src/app/core/context.service.ts

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

### 6.5 src/app/core/contract.service.ts

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

  /** Seul le token de login est envoyé : le backend retrouve le contexte associé. */
  private async call(path: string, method: string): Promise<any> {
    const resp = await fetch(`${CONFIG.ratawebApi}${path}`, {
      method,
      headers: { Authorization: 'Bearer ' + this.auth.loginToken() }
    });
    const body = await resp.json().catch(() => ({}));
    if (resp.status === 401) {
      throw new Error('Session expirée, reconnectez-vous');
    }
    if (body.code === 'no_context') {
      this.auth.clearContext();
    }
    if (!resp.ok) {
      throw new Error(body.message ?? `Erreur ${resp.status}`);
    }
    return body;
  }
}
```

### 6.6 src/app/pages/callback/

callback.component.ts :

```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({
  selector: 'app-callback',
  standalone: true,
  templateUrl: './callback.component.html',
  styleUrls: ['./callback.component.css']
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

callback.component.html :

```html
<p class="message">{{ message }}</p>
```

callback.component.css :

```css
.message { padding: 24px; font-family: sans-serif; }
```

### 6.7 src/app/pages/home/

home.component.ts :

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
      if (!this.context.currentNode()) {
        await this.openPicker();
      }
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
      if (!this.context.currentNode()) {
        await this.openPicker();
      }
    } finally {
      this.busyId = null;
    }
  }

  logout(): void {
    this.auth.logout();
  }
}
```

home.component.html :

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

home.component.css :

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

### 6.8 src/app/app.routes.ts

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

### 6.9 src/app/app.component.html

Remplacer tout le contenu par :

```html
<router-outlet></router-outlet>
```

Le composant racine doit importer RouterOutlet. Garder son nom de classe (importé par main.ts).

### 6.10 Réglages PingFederate du client rataweb-portal

- redirect URI : http://localhost:4300/callback ;
- Authorization Code coché, PKCE requis, Client Authentication à NONE ;
- Bypass Authorization Approval coché ;
- origine http://localhost:4300 autorisée dans les réglages CORS du serveur d'autorisation.

---

## Étape 7 : ordre d'exécution conseillé

1. Étapes 0 et 1 (bases).
2. Étape 3 (PingAuthorize) et ses curl directs.
3. Étape 4 (PUMA), redémarrage.
4. Étape 5 (Rataweb) avec require-audience à false, tests curl.
5. Étape 6 (front), scénario de l'étape 8.
6. Étape 2 (audience PingFederate), vérification aud = A3.
7. Étape 5.15 : require-audience à true, nouveau passage du scénario.

L'audience arrive en dernier : le scénario fonctionne d'abord grâce au repli client_id du catalogue, puis on durcit sans rien casser.

---

## Étape 8 : scénario de démonstration

1. PUMA, thomas.martin, contexte Roller 5 : créer julia.weber avec FINANCING_ADVISOR (R15), application A3, sur AB (2700013).
2. Rataweb, julia.weber : la pop-up ne propose que AB. "Contrats" : les 5 contrats s'affichent (règle Consultation autorisée).
3. "Approuver" sur CT-2026-001 : refus, statut inchangé (R15 n'accorde pas contract.approve).
4. PUMA : ajouter FINANCING_SUPERVISOR (R16) à julia.weber sur 2700013.
5. Rataweb, sans se reconnecter : "Approuver" CT-2026-001 (18 500 EUR). Attendu : "Contrat approuvé".
6. "Approuver" CT-2026-003 (24 300 EUR). Attendu : refus. La raison "Montant au-delà de la délégation" apparaît dans le Decision Visualiser.

Messages de démo :

- le droit change sans redéploiement ni nouveau token : le PDP lit l'état réel de la base à chaque décision ;
- le plafond est une règle métier portée par la politique, sans une ligne de code dans Rataweb ;
- l'application est identifiée par le token signé : un partenaire ne peut pas se faire passer pour un autre ;
- le token de contexte ne quitte jamais le serveur.

Traces à montrer :

- console Rataweb : Token exchange OK (avec aud), Decision PUMA Contract approve ;
- console PUMA : Decision partenaire ... service=Rataweb.Contract action=approve attributs={amount=...} ;
- PingAuthorize : Decision Visualiser, règle appliquée.

Remise à zéro avant une nouvelle démo (pgAdmin, utilisateur postgres) :

```sql
UPDATE rataweb.contract SET status = 'PENDING', approved_by = NULL, approved_at = NULL;
```

---

## Annexe A : obtenir un token de login rataweb-portal sans le front

```bash
VERIFIER=$(openssl rand -base64 48 | tr -d '=+/\n' | cut -c1-64)
CHALLENGE=$(printf %s "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=\n')
echo "https://localhost:9031/as/authorization.oauth2?response_type=code&client_id=rataweb-portal&redirect_uri=http://localhost:4300/callback&code_challenge=$CHALLENGE&code_challenge_method=S256"
```

Ouvrir l'URL en navigation privée, se connecter, copier la valeur de code, puis dans le même terminal :

```bash
curl -sk -X POST https://localhost:9031/as/token.oauth2 \
  -d grant_type=authorization_code -d code=COLLE_LE_CODE \
  -d redirect_uri=http://localhost:4300/callback \
  -d client_id=rataweb-portal -d code_verifier=$VERIFIER
```

Le code expire vite : enchaîner sans attendre. Puis export LOGIN="access_token".

---

## Points ouverts

| Point | État |
|---|---|
| Latence des décisions (10 à 15 s) | À traiter avant la démo |
| Spécialisation R30 (R16 sur 2700013, retire request.approve) | Sans effet sur contract.approve ; à retirer si elle gêne |
| Repli client_id dans PartnerApiController | À supprimer une fois l'audience en place partout |
| Audience côté PUMA (aud = A0 pour puma-portal et puma-backend) | Même procédure qu'à l'étape 2, après la démo |
| Simplification du PDP (grantingRoles + retraits sur le chemin) | Après la démo, avec root_role_id écrit par le module de gouvernance du catalogue |
| Raison du refus affichée à l'utilisateur | Aujourd'hui dans le Decision Visualiser ; à remonter via les statements PingAuthorize |
| Règle des quatre yeux | Colonne created_by et règle Deny, après la démo |
| Cache des contextes en mémoire | Perdu au redémarrage : le front rouvre la pop-up (code no_context) |
| Token de login dans le navigateur | Cible : session serveur (cookie HttpOnly) |
| Vue d'un superviseur sur les vendors de son entité | Le sous-arbre viendra d'une API hiérarchie de PUMA |
| Même BFF côté PUMA | Plan 3.3 |
| Client secrets visibles en clair | Variables d'environnement ; régénérer après la démo |
| Certificats auto-signés acceptés sans vérification | POC uniquement |
| Restes de l'ancienne implémentation dans app_role (R1 à R4, salesman...) | Sans effet grâce au filtre d'application ; à nettoyer |
| Règles Deny explicatives de la politique PUMA Assignation | Après la démo |
