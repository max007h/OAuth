ALTER TABLE assignment
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS created_by varchar(100);

  
CREATE TABLE IF NOT EXISTS assignment (
  id         bigserial PRIMARY KEY,
  user_id    bigint       NOT NULL REFERENCES puma_user(id) ON DELETE CASCADE,
  role_id    varchar(80)  NOT NULL REFERENCES app_role(id),
  node_id    varchar(20)  NOT NULL REFERENCES node(id),
  created_at timestamptz  NOT NULL DEFAULT now(),
  created_by varchar(100),
  CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id)
);






INSERT INTO puma_user (uid, email, display_name) VALUES
  ('thomas.martin', 'thomas.martin@test.local', 'Thomas Martin')
ON CONFLICT (uid) DO NOTHING;

INSERT INTO assignment (user_id, role_id, node_id)
SELECT u.id, v.role_id, v.node_id
FROM puma_user u
CROSS JOIN (VALUES
  ('R4', '9200002'),
  ('R4', '9200005'),
  ('R1', '9200005')
) AS v(role_id, node_id)
WHERE u.uid = 'thomas.martin'
ON CONFLICT (user_id, role_id, node_id) DO NOTHING;



CREATE TABLE IF NOT EXISTS puma_user (
  id           bigserial PRIMARY KEY,
  uid          varchar(100) NOT NULL UNIQUE,
  email        varchar(255),
  display_name varchar(255),
  status       varchar(20) NOT NULL DEFAULT 'ACTIVE',
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS assignment (
  id       bigserial PRIMARY KEY,
  user_id  bigint      NOT NULL REFERENCES puma_user(id) ON DELETE CASCADE,
  role_id  varchar(80) NOT NULL REFERENCES app_role(id),
  node_id  varchar(20) NOT NULL REFERENCES node(id),
  CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id)
);



DELETE FROM assignment WHERE user_id IN ('thomas', 'julia');
DELETE FROM puma_user  WHERE uid     IN ('thomas', 'julia');


INSERT INTO puma_user (uid, first_name, last_name, email) VALUES
  ('thomas.martin', 'Thomas', 'Martin', 'thomas.martin@test.local')
ON CONFLICT (uid) DO NOTHING;

INSERT INTO assignment (user_id, role_id, node_id) VALUES
  ('thomas.martin', 'R4', '9200002'),
  ('thomas.martin', 'R4', '9200005'),
  ('thomas.martin', 'R1', '9200005')
ON CONFLICT (user_id, role_id, node_id) DO NOTHING;






CREATE TABLE IF NOT EXISTS assignment (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  role_id     varchar(100) NOT NULL,
  node_id     varchar(20) NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  varchar(100),
  CONSTRAINT fk_assignment_user FOREIGN KEY (user_id)
      REFERENCES puma_user (id) ON DELETE CASCADE,
  CONSTRAINT fk_assignment_role FOREIGN KEY (role_id)
      REFERENCES app_role (id),
  CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id)
);






SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('app_role', 'permission', 'application', 'node_parent')
ORDER BY table_name, ordinal_position;




-- Roles globaux, node_id a NULL
INSERT INTO app_role (name, application_id, parent_role_id, node_id)
VALUES ('ShopAdmin', 'BusinessApp1', NULL, NULL),
       ('Viewer',    'BusinessApp1', NULL, NULL),
       ('ShopAdmin', 'BusinessApp2', NULL, NULL)
ON CONFLICT DO NOTHING;

-- Permissions de BusinessApp1
INSERT INTO permission (code, label, application_id)
VALUES ('assign',      'Affecter un utilisateur', 'BusinessApp1'),
       ('user.create', 'Creer un utilisateur',    'BusinessApp1')
ON CONFLICT DO NOTHING;

-- ShopAdmin sur BusinessApp1 detient les deux permissions
INSERT INTO role_permission (role_id, permission_id, granted)
SELECT r.id, p.id, true
FROM app_role r, permission p
WHERE r.name = 'ShopAdmin'
  AND r.application_id = 'BusinessApp1'
  AND r.node_id IS NULL
  AND p.application_id = 'BusinessApp1'
  AND p.code IN ('assign', 'user.create')
ON CONFLICT DO NOTHING;

-- Utilisateur de test
INSERT INTO puma_user (uid, email, display_name, status)
VALUES ('thomas.martin', 'thomas.martin@example.com', 'Thomas Martin', 'ACTIVE')
ON CONFLICT (uid) DO NOTHING;

-- Les trois assignments du diagramme
INSERT INTO assignment (user_id, role_id, node_id, created_by)
SELECT u.id, r.id, v.node, 'seed'
FROM puma_user u
JOIN app_role r ON r.name = 'ShopAdmin' AND r.node_id IS NULL
JOIN (VALUES ('BusinessApp1', '9200005'),
             ('BusinessApp1', '9200002'),
             ('BusinessApp2', '9200005')) AS v(app, node)
  ON v.app = r.application_id
WHERE u.uid = 'thomas.martin'
ON CONFLICT ON CONSTRAINT uq_assignment DO NOTHING;



ALTER TABLE app_role ADD CONSTRAINT uq_app_role
  UNIQUE (name, application_id, node_id);
ALTER TABLE permission ADD CONSTRAINT uq_permission
  UNIQUE (code, application_id);




CREATE TABLE IF NOT EXISTS puma_user (
  id            bigserial PRIMARY KEY,
  uid           varchar(100) NOT NULL UNIQUE,
  email         varchar(255),
  display_name  varchar(255),
  status        varchar(20) NOT NULL DEFAULT 'ACTIVE',
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS assignment (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  role_id     bigint NOT NULL,
  node_id     varchar(20) NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  varchar(100),
  CONSTRAINT fk_assignment_user FOREIGN KEY (user_id)
      REFERENCES puma_user (id) ON DELETE CASCADE,
  CONSTRAINT fk_assignment_role FOREIGN KEY (role_id)
      REFERENCES app_role (id),
  CONSTRAINT uq_assignment UNIQUE (user_id, role_id, node_id)
);

CREATE INDEX IF NOT EXISTS idx_assignment_user ON assignment (user_id);
CREATE INDEX IF NOT EXISTS idx_assignment_node ON assignment (node_id);






-- Applications
INSERT INTO application (name) VALUES
  ('BusinessApp1'),
  ('BusinessApp2'),
  ('BusinessApp3');

-- Roles globaux, node_id a NULL
INSERT INTO app_role (name, application_id, parent_role_id, node_id)
SELECT 'ShopAdmin', id, NULL, NULL FROM application WHERE name = 'BusinessApp1';
INSERT INTO app_role (name, application_id, parent_role_id, node_id)
SELECT 'Viewer', id, NULL, NULL FROM application WHERE name = 'BusinessApp1';
INSERT INTO app_role (name, application_id, parent_role_id, node_id)
SELECT 'ShopAdmin', id, NULL, NULL FROM application WHERE name = 'BusinessApp2';
INSERT INTO app_role (name, application_id, parent_role_id, node_id)
SELECT 'Salesman', id, NULL, NULL FROM application WHERE name = 'BusinessApp3';

-- Permissions, rattachees a leur application
INSERT INTO permission (code, label, application_id)
SELECT 'assign', 'Affecter un utilisateur', id FROM application WHERE name = 'BusinessApp1';
INSERT INTO permission (code, label, application_id)
SELECT 'user.create', 'Creer un utilisateur', id FROM application WHERE name = 'BusinessApp1';

-- ShopAdmin sur BusinessApp1 peut assign et user.create
INSERT INTO role_permission (role_id, permission_id, granted)
SELECT r.id, p.id, true
FROM app_role r
JOIN application a ON a.id = r.application_id
JOIN permission p ON p.application_id = a.id
WHERE r.name = 'ShopAdmin' AND a.name = 'BusinessApp1'
  AND p.code IN ('assign', 'user.create');

-- Utilisateur
INSERT INTO puma_user (uid, email, display_name, status)
VALUES ('thomas.martin', 'thomas.martin@example.com', 'Thomas Martin', 'ACTIVE');

-- Assignments, les trois du diagramme
INSERT INTO assignment (user_id, role_id, node_id, created_by)
SELECT u.id, r.id, '9200005', 'seed'
FROM puma_user u, app_role r
JOIN application a ON a.id = r.application_id
WHERE u.uid = 'thomas.martin' AND r.name = 'ShopAdmin' AND a.name = 'BusinessApp1';

INSERT INTO assignment (user_id, role_id, node_id, created_by)
SELECT u.id, r.id, '9200002', 'seed'
FROM puma_user u, app_role r
JOIN application a ON a.id = r.application_id
WHERE u.uid = 'thomas.martin' AND r.name = 'ShopAdmin' AND a.name = 'BusinessApp1';

INSERT INTO assignment (user_id, role_id, node_id, created_by)
SELECT u.id, r.id, '9200005', 'seed'
FROM puma_user u, app_role r
JOIN application a ON a.id = r.application_id
WHERE u.uid = 'thomas.martin' AND r.name = 'ShopAdmin' AND a.name = 'BusinessApp2';



SELECT a.node_id, r.name AS role, app.name AS application
FROM assignment a
JOIN puma_user u ON u.id = a.user_id
JOIN app_role r ON r.id = a.role_id
JOIN application app ON app.id = r.application_id
WHERE u.uid = 'thomas.martin'
ORDER BY app.name, a.node_id;


SELECT count(*) FROM app_role r
JOIN role_permission rp ON rp.role_id = r.id
JOIN permission p ON p.id = rp.permission_id
JOIN application a ON a.id = r.application_id
WHERE r.name = 'ShopAdmin' AND a.name = 'BusinessApp1'
  AND r.node_id IS NULL AND p.code = 'assign' AND rp.granted = true;






@Entity
@Table(name = "app_role")
public class AppRole {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(name = "application_id", nullable = false)
    private Long applicationId;

    @Column(name = "parent_role_id")
    private Long parentRoleId;

    @Column(name = "node_id", length = 20)
    private String nodeId;

    // getters et setters
}







package com.puma.model;

import jakarta.persistence.*;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "puma_user")
public class PumaUser {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 100)
    private String uid;

    @Column(length = 255)
    private String email;

    @Column(name = "display_name", length = 255)
    private String displayName;

    @Column(nullable = false, length = 20)
    private String status = "ACTIVE";

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Assignment> assignments = new ArrayList<>();

    public PumaUser() {
    }

    public PumaUser(String uid, String email, String displayName) {
        this.uid = uid;
        this.email = email;
        this.displayName = displayName;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getUid() {
        return uid;
    }

    public void setUid(String uid) {
        this.uid = uid;
    }

    public String getEmail() {
        return email;
    }

    public void setEmail(String email) {
        this.email = email;
    }

    public String getDisplayName() {
        return displayName;
    }

    public void setDisplayName(String displayName) {
        this.displayName = displayName;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(OffsetDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public List<Assignment> getAssignments() {
        return assignments;
    }

    public void setAssignments(List<Assignment> assignments) {
        this.assignments = assignments;
    }

    public void addAssignment(Assignment assignment) {
        assignments.add(assignment);
        assignment.setUser(this);
    }

    public void removeAssignment(Assignment assignment) {
        assignments.remove(assignment);
        assignment.setUser(null);
    }
}





package com.puma.model;

import jakarta.persistence.*;
import java.time.OffsetDateTime;
import java.util.Objects;

@Entity
@Table(name = "assignment",
       uniqueConstraints = @UniqueConstraint(
           name = "uq_assignment",
           columnNames = {"user_id", "role_id", "node_id"}))
public class Assignment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private PumaUser user;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "role_id", nullable = false)
    private AppRole role;

    @Column(name = "node_id", nullable = false, length = 20)
    private String nodeId;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "created_by", length = 100)
    private String createdBy;

    public Assignment() {
    }

    public Assignment(PumaUser user, AppRole role, String nodeId, String createdBy) {
        this.user = user;
        this.role = role;
        this.nodeId = nodeId;
        this.createdBy = createdBy;
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public PumaUser getUser() {
        return user;
    }

    public void setUser(PumaUser user) {
        this.user = user;
    }

    public AppRole getRole() {
        return role;
    }

    public void setRole(AppRole role) {
        this.role = role;
    }

    public String getNodeId() {
        return nodeId;
    }

    public void setNodeId(String nodeId) {
        this.nodeId = nodeId;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(OffsetDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public String getCreatedBy() {
        return createdBy;
    }

    public void setCreatedBy(String createdBy) {
        this.createdBy = createdBy;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Assignment)) return false;
        Assignment other = (Assignment) o;
        return id != null && id.equals(other.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }
}







SELECT count(*) AS granted_count
FROM app_role r
JOIN role_permission rp ON rp.role_id = r.id
JOIN permission p ON p.id = rp.permission_id
JOIN application a ON a.id = r.application_id
WHERE r.name = 'ShopAdmin'
  AND a.name = 'BusinessApp1'
  AND r.node_id IS NULL
  AND p.name = 'assign'
  AND rp.granted = true

  



ResponseEntity<String> response = rest.exchange(
        baseUrl + "/governance-engine/batch",
        HttpMethod.POST,
        entity,
        String.class);

JsonNode body = new ObjectMapper().readTree(response.getBody());
JsonNode responses = body.path("responses");





@PostConstruct
void init() {
    this.rest = new RestTemplate(trustAllRequestFactory());
    this.rest.getMessageConverters().add(new MappingJackson2HttpMessageConverter());
}

org.springframework.http.converter.json.MappingJackson2HttpMessageConverter




Ensuite parce qu'OpenFGA est un projet open source, donc la question du support et de la conformité se pose dans un contexte bancaire.




Le coarse d'abord, et il est déjà là.
Le contrôle grossier, c'est l'authentification PingFederate et le test d'appartenance au groupe MANAGER dans ton backend. C'est ce qui filtre l'écrasante majorité des appels illégitimes, et c'est peu coûteux.
Le fine grained, c'est ta chaîne : ce manager précis peut-il agir sur ce noeud précis pour cette application. Il ne s'exécute que sur les appels qui ont déjà passé le premier filtre.
La doc Apigee dit exactement ça : intégrer PingAuthorize tard dans le PreFlow, après les contrôles d'authentification et d'autorisation grossiers, parce que c'est là qu'il apporte sa valeur.
Pour ton POC, la priorité est inverse de l'ordre d'exécution. Le coarse est trivial et déjà fait, personne ne demande de le démontrer. Le fine grained est ce qui justifie un PDP, et c'est le sujet de l'atelier. C'est donc lui que tu portes.
Un point à assumer en séance : ton /governance-engine ignore l'en-tête Authorization, donc le sujet est celui que l'appelant déclare. C'est acceptable parce que le PEP a validé le token en amont, mais il faut le dire avant qu'on te le demande




docker cp env-pingauthorizepap-1:/opt/out/instance/lib/postgresql-42.7.3.jar /tmp/postgresql-42.7.3.jar

docker cp /tmp/postgresql-42.7.3.jar env-pingauthorize-1:/opt/out/instance/lib/

docker restart env-pingauthorize-1




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -d '{
    "domain": "PUMA",
    "service": "PUMA.Administration",
    "action": "assign",
    "attributes": {
      "uid": "thomas.martin",
      "targetApplication": "BusinessApp1",
      "targetNode": "2700010"
    }
  }'


#this.![#this.substring(#this.indexOf('|')+1, #this.lastIndexOf('|'))]






WITH RECURSIVE ancestors AS (
  SELECT node_id, parent_id FROM node_parent WHERE node_id = '2700010'
  UNION ALL
  SELECT np.node_id, np.parent_id FROM node_parent np
  JOIN ancestors a ON np.node_id = a.parent_id
)
SELECT parent_id FROM ancestors






docker exec -it pingdirectory /opt/out/instance/bin/ldapsearch \
  --hostname localhost --port 1389 \
  --bindDN "cn=administrator" --bindPassword "2FederateM0re" \
  --baseDN "ou=People,dc=example,dc=com" \
  "(objectClass=pumaPartnerUser)" \
  uid partnerGrant opScope opScopeExclude reportScope





sequenceDiagram
    autonumber
    participant PEP as PUMA backend 8081<br/>role PEP
    participant PDP as PingAuthorize 7443<br/>role PDP
    participant PAP as PAP PingAuthorize<br/>role PAP
    participant PIP as PingDirectory 1389<br/>role PIP

    Note over PAP,PDP: Hors ligne, avant toute requete<br/>l administrateur ecrit le Trust Framework<br/>et la policy Delegation DenyUnlessPermit<br/>le PDP charge la version publiee

    Note over PEP: Thomas Martin veut affecter un utilisateur<br/>sur le vendeur 2700010, application BusinessApp1<br/>le PEP a valide le token et calcule les ancetres

    PEP->>PDP: POST /governance-engine<br/>domain PUMA, service PUMA.Administration<br/>action assign<br/>uid thomas.martin<br/>targetApplication BusinessApp1<br/>targetNode 2700010<br/>targetNodeParents 2700010, 9200005,<br/>9100002, 9300001, CL_A

    Note over PEP,PDP: Le PEP ne declare aucun droit<br/>il decrit la cible, rien d autre

    PDP->>PIP: recherche LDAP (uid=thomas.martin)<br/>base ou=People,dc=example,dc=com
    PIP-->>PDP: XML searchResponse<br/>partnerGrant BusinessApp1 9200005 ShopAdmin<br/>partnerGrant BusinessApp1 9200002 ShopAdmin<br/>partnerGrant BusinessApp2 9200005 ShopAdmin

    PDP->>PDP: managerGrants, processeur XPath<br/>trois grants extraits

    PDP->>PDP: grantsForApp, Collection Filter<br/>prefixe BusinessApp1<br/>BusinessApp2 ecarte, deux grants retenus

    PDP->>PDP: nodesFromGrants, projection SpEL<br/>segment noeud des grants retenus<br/>9200005 et 9200002

    PDP->>PDP: matchedNodes, Collection Filter<br/>intersection avec targetNodeParents<br/>9200005 retenu, matchCount egal 1

    PDP->>PDP: rule node authorised<br/>matchCount superieur a zero

    PDP-->>PEP: PERMIT, authorised true<br/>evaluation log complet

    Note over PEP: Le PEP applique la decision<br/>il n en reevalue aucune partie

    Note over PDP,PIP: Cas cible 2700015<br/>ancetres 9200006, 9100002, 9300001, CL_A<br/>aucun noeud de grant present<br/>matchCount zero, policy DENY

    Note over PDP,PIP: Cas application BusinessApp2<br/>grantsForApp ne retient que le grant 9200005<br/>la comparaison porte sur la bonne application

    Note over PDP: Hors perimetre a ce stade<br/>segment role jamais compare<br/>opScope, opScopeExclude, reportScope non branches<br/>exclusion du noeud propre non traitee







//searchResultEntry/attr[@name='partnerGrant']/text()



docker exec env-pingauthorize-1 /opt/out/instance/bin/ldapsearch \
  --hostname pingdirectory --port 1389 \
  --bindDN "cn=administrator" --bindPassword "<ton mdp>" \
  --baseDN "" --searchScope base "(objectClass=*)" namingContexts


docker exec env-pingauthorize-1 /opt/out/instance/bin/ldapsearch \
  --hostname pingdirectory --port 1389 \
  --bindDN "cn=administrator" --bindPassword "<ton mdp>" \
  --baseDN "<le suffixe trouvé>" \
  "(uid=thomas.martin)" partnerGrant

pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 \
  --attribute-name targetNode

pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 \
  --attribute-name targetNodeParents --set multi-valued:true

pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 \
  --attribute-name targetApplication

pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 \
  --attribute-name targetRole


  curl -k -X POST https://localhost:7443/scim/v2/Users \
  -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' \
  -H 'Content-Type: application/scim+json' \
  -d '{"schemas":["urn:pingidentity:schemas:PumaUser:1.0"],
       "targetNode":"2700010",
       "targetNodeParents":["2700010","9200005","9100002","9300001","CL_A"],
       "targetApplication":"BusinessApp1",
       "targetRole":"Salesman"}'






curl -k -X POST https://localhost:7443/scim/v2/Users \
  -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' \
  -H 'Content-Type: application/scim+json' \
  -d '{"schemas":["urn:pingidentity:schemas:PumaUser:1.0"],
       "uid":"test.user",
       "targetNodeParents":"2700010,9200005,9100002,9300001,CL_A"}'




curl -k https://localhost:7443/scim/v2/Users \
  -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}'



docker exec env-pingauthorize-1 /opt/out/instance/bin/dsconfig set-policy-decision-service-prop \
  --set "access-token-validator:Mock Access Token Validator" \
  --no-prompt







package com.example.demo;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import java.util.Base64;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

class PingAuthorizePdpIntegrationTest {

    private static final String PDP_URL = "https://localhost:7443/governance-engine";
    private HttpClient httpClient;

    @BeforeEach
    void setUp() throws Exception {
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, new TrustManager[]{new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] certs, String authType) {}
            public void checkServerTrusted(X509Certificate[] certs, String authType) {}
        }}, new SecureRandom());

        this.httpClient = HttpClient.newBuilder()
                .sslContext(sslContext)
                .build();
    }

    @Test
    @DisplayName("Test d'intégration PDP avec JWT valide")
    void shouldEvaluatePdpPolicyWithMockToken() throws Exception {
        // Génération d'un véritable JWT structuré
        String jwtToken = generateMockJwt("thomas.martin");

        String requestBody = "{"
                + "\"domain\":\"PUMA\","
                + "\"service\":\"PUMA.Administration\","
                + "\"action\":\"assign\","
                + "\"attributes\":{\"targetNodeParents\":\"2700010\"}"
                + "}";

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(PDP_URL))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + jwtToken)
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .build();

        HttpResponse<String> response = this.httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        System.out.println("====== STATUS CODE ===== " + response.statusCode());
        System.out.println("====== RESPONSE BODY =====\n" + response.body());

        assertEquals(200, response.statusCode());
        assertFalse(response.body().contains("Missing Attribute: TokenOwner"), 
                "TokenOwner doit être extrait du JWT sans erreur MISSING_ATTRIBUTE");
    }

    private String generateMockJwt(String username) throws Exception {
        String header = Base64.getUrlEncoder().withoutPadding().encodeToString("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".getBytes(StandardCharsets.UTF_8));
        
        long now = System.currentTimeMillis() / 1000;
        String payloadJson = String.format("{\"sub\":\"%s\",\"active\":true,\"exp\":%d}", username, now + 3600);
        String payload = Base64.getUrlEncoder().withoutPadding().encodeToString(payloadJson.getBytes(StandardCharsets.UTF_8));

        String contentToSign = header + "." + payload;
        Mac hmac = Mac.getInstance("HmacSHA256");
        // Clé HMAC de test standard
        hmac.init(new SecretKeySpec("secretsecretsecretsecretsecretsecret".getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
        String signature = Base64.getUrlEncoder().withoutPadding().encodeToString(hmac.doFinal(contentToSign.getBytes(StandardCharsets.UTF_8)));

        return contentToSign + "." + signature;
    }
}





package com.example.demo;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PingAuthorizePdpIntegrationTest {

    private static final String PDP_URL = "https://localhost:7443/governance-engine";
    private HttpClient httpClient;

    @BeforeEach
    void setUp() throws Exception {
        // Bypass SSL pour les certificats auto-signés du PDP local (-k)
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, new TrustManager[]{new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] certs, String authType) {}
            public void checkServerTrusted(X509Certificate[] certs, String authType) {}
        }}, new SecureRandom());

        this.httpClient = HttpClient.newBuilder()
                .sslContext(sslContext)
                .build();
    }

    @Test
    @DisplayName("Devrait évaluer la politique PDP avec le token mock et la résolution tokenUid")
    void shouldEvaluatePdpPolicyWithMockToken() throws Exception {
        // Mock Token payload JSON
        String mockTokenJson = "{\"active\":true,\"sub\":\"thomas.martin\"}";

        // Body de la requête PDP
        String requestBody = "{"
                + "\"domain\":\"PUMA\","
                + "\"service\":\"PUMA.Administration\","
                + "\"action\":\"assign\","
                + "\"attributes\":{\"targetNodeParents\":\"2700010\"}"
                + "}";

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(PDP_URL))
                .header("Content-Type", "application/json")
                .header("Authorization", "Bearer " + mockTokenJson)
                .POST(HttpRequest.BodyPublishers.ofString(requestBody))
                .build();

        HttpResponse<String> response = this.httpClient.send(request, HttpResponse.BodyHandlers.ofString());

        // Assertions
        assertEquals(200, response.statusCode(), "Le PDP doit répondre avec un code 200 OK");
        
        String responseBody = response.body();
        assertTrue(responseBody.contains("\"code\":\"OK\""), "La réponse doit contenir un statut OK");
        
        // Vérifie qu'il n'y a plus l'erreur MISSING_ATTRIBUTE sur TokenOwner
        assertTrue(!responseBody.contains("Missing Attribute: TokenOwner"), 
                "TokenOwner doit être résolu correctement sans erreur MISSING_ATTRIBUTE");
    }
}



<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
</dependency>








curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNodeParents":"2700010"}}'




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNodeParents":"2700010"}}'





curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {\"active\":true,\"sub\":\"khomas.martin\"}" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNodeParents":"2700010"}}'







pazcfg set-policy-decision-service-prop --set decision-response-view:attributes --set decision-response-view:request --set decision-response-view:evaluation-log-with-attribute-values

curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005"}}' > /tmp/decision.json; python3 -m json.tool /tmp/decision.json | head -80



pazcfg get-policy-decision-service-prop --property decision-response-view


curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' -d '{"domain":"PUMA","service":"PUMA.Administration","identityProvider":"Mock Access Token Validator","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005"}}'


curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005"}}'



pazcfg set-external-server-prop --server-name "PingDirectory Server" --set server-port:1389 --set connection-security:none --reset key-manager-provider --reset trust-manager-provider
docker restart env-pingauthorize-1


docker exec env-pingauthorize-1 grep "external-server-initialization-failed" /opt/out/instance/logs/errors | tail -2


pazcfg set-external-server-prop --server-name "PingDirectory Server" --set "bind-dn:cn=Directory Manager,cn=Root DNs,cn=config"
docker restart env-pingauthorize-1

docker exec env-pingauthorize-1 grep -i "external-server-initialization-failed\|User Store Availability" /opt/out/instance/logs/errors | tail -20


start config mock 

pazcfg set-trust-manager-provider-prop --provider-name "Blind Trust" --set enabled:true

pazcfg list-key-manager-providers

pazcfg list-locations
pazcfg get-global-configuration-prop --property location

pazcfg set-external-server-prop --server-name "PingDirectory Server" --set location:Docker

pazcfg create-load-balancing-algorithm --algorithm-name "User Store LBA" --type failover --set enabled:true --set "backend-server:PingDirectory Server"


pazcfg set-store-adapter-prop --adapter-name UserStoreAdapter --set enabled:true --set "load-balancing-algorithm:User Store LBA" --set auxiliary-ldap-objectclass:pumaPartnerUser

pazcfg get-store-adapter-prop --adapter-name UserStoreAdapter

pazcfg create-scim-schema --schema-name urn:pingidentity:schemas:PumaUser:1.0 --set display-name:PumaUser

pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 --attribute-name uid
pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 --attribute-name partnerGrant --set multi-valued:true
pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 --attribute-name opScope --set multi-valued:true
pazcfg create-scim-attribute --schema-name urn:pingidentity:schemas:PumaUser:1.0 --attribute-name reportScope --set multi-valued:true


pazcfg create-scim-resource-type --type-name Users --type mapping --set enabled:true --set endpoint:Users --set "primary-store-adapter:UserStoreAdapter" --set lookthrough-limit:500 --set core-schema:urn:pingidentity:schemas:PumaUser:1.0

pazcfg create-store-adapter-mapping --type-name Users --mapping-name uid --set scim-resource-type-attribute:uid --set store-adapter-attribute:uid --set searchable:true
pazcfg create-store-adapter-mapping --type-name Users --mapping-name partnerGrant --set scim-resource-type-attribute:partnerGrant --set store-adapter-attribute:partnerGrant
pazcfg create-store-adapter-mapping --type-name Users --mapping-name opScope --set scim-resource-type-attribute:opScope --set store-adapter-attribute:opScope
pazcfg create-store-adapter-mapping --type-name Users --mapping-name reportScope --set scim-resource-type-attribute:reportScope --set store-adapter-attribute:reportScope


mock:
----
pazcfg create-access-token-validator --validator-name "Mock Access Token Validator" --type mock --set enabled:true --set evaluation-order-index:9999

pazcfg create-token-resource-lookup-method --validator-name "Mock Access Token Validator" --method-name "User by uid" --type scim --set scim-resource-type:Users --set 'match-filter:uid eq "%sub%"' --set evaluation-order-index:1000

test with token
------
curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -H 'Authorization: Bearer {"active":true,"sub":"thomas.martin"}' -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005"}}'
----------------
docker exec env-pingauthorize-1 /opt/out/instance/bin/ldapsearch --hostname pingdirectory --port 1636 --useSSL --trustAll --bindDN "cn=administrator" --bindPassword "2FederateM0re" --baseDN "dc=example,dc=com" "(uid=thomas.martin)" uid


pazcfg create-external-server --server-name "PingDirectory Server" --type ping-identity-ds --set server-host-name:pingdirectory --set server-port:1636 --set "bind-dn:cn=administrator" --set "password:2FederateM0re" --set connection-security:ssl --set trust-manager-provider:"Blind Trust" --set k
ey-manager-provider:"JKS"

pazcfg create-load-balancing-algorithm --algorithm-name "User Store LBA" --type failover --set enabled:true --set "backend-server:PingDirectory Server"









pazcfg create-external-server --server-name "PingDirectory Server" --type ping-identity-ds --set server-host-name:pingdirectory --set server-port:1636 --set "bind-dn:cn=administrator" --set "password:2FederateM0re" --set connection-security:ssl --set trust-manager-provider:"Blind Trust"


pazcfg create-load-balancing-algorithm --algorithm-name "User Store LBA" --type failover --set enabled:true --set "backend-server:PingDirectory Server"

pazcfg list-load-balancing-algorithms

pazcfg get-store-adapter-prop --adapter-name UserStoreAdapter : enabled











docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch --port 1636 --useSSL --trustAll --bindDN "cn=administrator" --bindPassword "2FederateM0re" --baseDN "dc=example,dc=com" "(uid=thomas.martin)" dn partnerGrant



pazcfg get-store-adapter-prop --adapter-name UserStoreAdapter

docker exec env-pingauthorize-1 ls /opt/out/instance/config/archived-configs



alias pazcfg='docker exec env-pingauthorize-1 /opt/out/instance/bin/dsconfig --no-prompt --noPropertiesFile --hostname localhost --port 1636 --useSSL --trustAll --bindDN "cn=administrator" --bindPassword "2FederateM0re"'

pazcfg list-store-adapters
pazcfg list-scim-resource-types
pazcfg list-external-servers
pazcfg list-load-balancing-algorithms



docker exec env-pingauthorize-1 cat /opt/out/instance/config/build-info.txt



docker exec env-pingauthorize-1 /opt/out/instance/bin/dsconfig --no-prompt --noPropertiesFile --hostname localhost --port 1636 --useSSL --trustAll --bindDN "cn=administrator" --bindPassword "2FederateM0re" list-access-token-validators




curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005"}}'


curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700015","targetNodeParents":"2700015,9200006,9100002,9300001,CL_A","managerNodes":"9200005"}}'

curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005,9200002"}}'



curl -k -X POST https://localhost:7443/governance-engine -H "Content-Type: application/json" -H "Accept: application/json" -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200002,9200003"}}'




PDP="https://localhost:7443/governance-engine"
H='-H Content-Type:application/json -H Accept:application/json'

# 1. PERMIT attendu : 9200005 est bien dans les parents de 2700010
curl -k -X POST $PDP $H -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005"}}'

# 2. DENY attendu : 9200005 absent des parents de 2700015
curl -k -X POST $PDP $H -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700015","targetNodeParents":"2700015,9200006,9100002,9300001,CL_A","managerNodes":"9200005"}}'


# 3. Deux grants, un seul matche. PERMIT = "au moins un", DENY = "tous"
curl -k -X POST $PDP $H -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200005,9200002"}}'

# 4. Temoin negatif obligatoire : aucun ne matche, doit rendre DENY
curl -k -X POST $PDP $H -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A","managerNodes":"9200002,9200003"}}'







curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A"}}'

  

curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700015","targetNodeParents":"2700015,9200006,9100002,9300001,CL_A"}}'




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010","targetNodeParents":"2700010,9200005,9100002,9300001,CL_A"}}'




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700010"}}'


curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{"targetNode":"2700015"}}'
  




docker exec env-pingauthorize-1 grep -o "targetNode" /tmp/policies.SDP | head -3




curl -k -X POST https://localhost:7443/governance-engine/batch \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"requests":[{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{}},{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{}}]}'

  




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{}}'

  



docker exec env-pingauthorize-1 /opt/out/instance/bin/status | grep -A6 "Policy Decision Service"


curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{}}'




docker cp ~/Downloads/<nom-du-fichier>.SDP env-pingauthorize-1:/tmp/policies.SDP

docker exec env-pingauthorize-1 /opt/out/instance/bin/dsconfig \
  --no-prompt --noPropertiesFile \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword "2FederateM0re" \
  set-policy-decision-service-prop \
  --set pdp-mode:embedded \
  --set "deployment-package:/tmp/policies.SDP" \
  --set trust-framework-version:v2


curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign","attributes":{}}'
  





TOKEN="<ton token frais>"

curl -i -H "Authorization: Bearer $TOKEN" \
  http://localhost:8081/api/hierarchy/subtree

  curl -i -H "Authorization: Bearer $TOKEN" \
  http://localhost:8081/api/applications

curl -i -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8081/api/roles?application=BusinessApp1&node=2700010"




docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword "2FederateM0re" \
  --baseDN "ou=people,dc=example,dc=com" \
  "(uid=thomas.martin)" partnerGrant isMemberOf






docker inspect env-pingdirectory-1 --format '{{json .Mounts}}' | python3 -m json.tool



docker exec env-pingauthorizepap-1 grep -rl "1443" /opt/out/instance/config/ 2>/dev/null
docker exec env-pingauthorizepap-1 env | grep -i port



docker exec env-pingauthorizepap-1 sh -c \
  "netstat -tln 2>/dev/null || ss -tln 2>/dev/null || cat /proc/net/tcp"

docker inspect env-pingauthorizepap-1 \
  --format '{{json .Config.Healthcheck}}'




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign",
       "attributes":{"targetNode":"2700010",
                     "targetNodeParents":"2700010,9200005,9100002,9300001,CL_A"}}'




# Mesures complementaires SAST / SCA

## Contexte

Apres relecture du fichier de mesures, je voulais partager un point d'attention avant qu'on fige les specifications avec l'equipe orchestrateur.

Le jeu actuel decrit surtout l'activite de notre outillage : combien de scans ont tourne, combien de findings ils remontent, quelle part du parc est couverte. C'est necessaire et ca constitue une bonne base pour la phase 2. En l'etat, ca ne nous permettra pas de repondre a la question qui nous sera posee en comite : est-ce que notre exposition diminue ?

Il manque d'abord la dimension temporelle. Aujourd'hui, une vulnerabilite critique detectee il y a deux jours et une autre ouverte depuis plus d'un an sont comptees de la meme facon. Tant qu'on ne conserve pas la date de premiere detection et la date de correction, on ne peut produire ni delai de remediation, ni taux de respect d'un SLA, ni age de la dette, c'est-a-dire exactement ce qui nous sera demande dans le cadre du pilotage reglementaire.

Il manque ensuite la dimension de flux. Toutes les mesures sont des photographies a l'instant T. Un stock qui reste stable d'un mois sur l'autre peut aussi bien vouloir dire que rien ne bouge que deux cents vulnerabilites creees et deux cents corrigees. Ce sont deux situations tres differentes, qui appellent des decisions opposees.

Ces deux manques relevent du meme prerequis technique : persister un etat par vulnerabilite (cle stable, date de premiere detection, date de correction, statut) plutot que des compteurs agreges a chaque scan. L'ajustement est a porter cote orchestrateur, en amont de l'indexation Splunk, et il conditionne tous les indicateurs de pilotage qu'on pourra construire ensuite.

Les huit mesures ci-dessous s'appuient sur ce principe.

## Tableau des mesures

| Type | Mesure | Description de synthese | Source de donnees | Commentaire | Formule de calcul |
|---|---|---|---|---|---|
| SAST | SAST_13 | Ecart entre le nombre de vulnerabilites introduites et le nombre de vulnerabilites corrigees sur les 30 derniers jours glissants, sur le perimetre des codes sources deployes en production | SAST_01 (evenements de scan) + Global_03 (deploiements). Pas de CMDB. Cible : index splunk | Suppose que l'orchestrateur emette des evenements de transition (introduite / corrigee) par comparaison au scan precedent du meme module, et non le seul listing brut des findings. Fenetre glissante ancree a minuit (-30d@d vers @d) pour que la valeur ne bouge pas en cours de journee. Seules les corrections effectives sont comptees : derogations et faux positifs exclus, sinon l'indicateur s'ameliore en fermant des tickets | Nb(introduites, 30 j) moins Nb(corrigees, 30 j). Resultat positif : la dette croit |
| SCA | SCA_09 | Ecart entre le nombre de vulnerabilites de composants tiers introduites et corrigees sur les 30 derniers jours glissants, sur le perimetre des codes sources deployes en production | SCA_01 (evenements de scan) + Global_03 (deploiements). Pas de CMDB. Cible : index splunk | Meme principe que SAST_13. Cle d'identite stable : module + composant + CVE. A noter qu'une CVE peut apparaitre sans nouveau build, quand elle est publiee apres le dernier scan. C'est une introduction legitime, elle doit etre comptabilisee | Nb(introduites, 30 j) moins Nb(corrigees, 30 j) |
| SAST | SAST_14 | Nombre de vulnerabilites de criticite critique, encore ouvertes, portees par des codes sources deployes en production appartenant a une application exposee a Internet | SAST_01 + Global_01 / Global_03 pour le rattachement module vers CCX, enrichi par la CMDB (attribut Expose a Internet, classification DICT) par jointure sur le CCX. Cible : index splunk | L'exposition ne vient pas de l'outil de scan mais de la CMDB. Le mapping CCX vers CMDB figure aujourd'hui en option dans Global_01 : il doit passer en prerequis ferme, sinon la mesure n'est pas calculable. Pas d'alternative fiable cote POP a ce stade, c'est a arbitrer avant la phase 2 | Nb distinct(vulnerabilite) ou criticite = critique ET statut = ouvert ET expose_internet = vrai |
| SAST | SAST_15 | Nombre de vulnerabilites de criticite critique, encore ouvertes, portees par des codes sources deployes en production n'appartenant pas a une application exposee a Internet | Identique a SAST_14, CMDB requise | Sert de contrepoint : verifie que la priorisation sur le perimetre expose ne se fait pas au detriment du reste du parc. Techniquement une mesure unique avec l'exposition en dimension suffirait, les deux lignes ne se justifient que si le comite suit deux valeurs distinctes dans le temps | Nb distinct(vulnerabilite) ou criticite = critique ET statut = ouvert ET expose_internet = faux |
| SCA | SCA_10 | Nombre de vulnerabilites de composants tiers de criticite critique (CVSS de 9 a 10), encore ouvertes, sur des codes sources deployes en production appartenant a une application exposee a Internet | SCA_01 + Global_01 / Global_03, enrichi par la CMDB via le CCX. Cible : index splunk | Meme prerequis CMDB que SAST_14. Ajouter l'attribut correctif disponible en dimension permet de separer ce qui est actionnable par nos equipes de ce qui depend de l'editeur | Nb distinct(module + composant + CVE) ou CVSS de 9 a 10 ET statut = ouvert ET expose_internet = vrai |
| SCA | SCA_11 | Nombre de vulnerabilites de composants tiers de criticite critique (CVSS de 9 a 10), encore ouvertes, sur des codes sources deployes en production n'appartenant pas a une application exposee a Internet | Identique a SCA_10, CMDB requise | Meme remarque que pour SAST_15 | Nb distinct(module + composant + CVE) ou CVSS de 9 a 10 ET statut = ouvert ET expose_internet = faux |
| SAST | SAST_16 | Nombre de vulnerabilites ouvertes depuis plus de 90 jours a compter de leur premiere detection, sur les codes sources deployes en production, ventile par niveau de criticite | Etat de vulnerabilite persiste par l'orchestrateur (derive de SAST_01). Pas de CMDB, sauf pour la ventilation par filiere : POP n'ayant pas la connaissance des filieres a date, cette ventilation passerait par la CMDB. Cible : index splunk | Restituable directement dans Splunk des lors que la date de premiere detection est persistee. Le recalcul a la volee sur l'historique brut fonctionne mais devient couteux au-dela de quelques mois : prevoir un summary index ou un KV Store rafraichi a chaque scan. Le seuil de 90 jours est a aligner sur les SLA de remediation une fois ceux-ci formalises. Restitution en barres empilees par criticite | Nb distinct(vulnerabilite) ou statut = ouvert ET (date du jour moins date de premiere detection) superieur a 90 j, groupe par criticite |
| SCA | SCA_12 | Nombre de vulnerabilites de composants tiers ouvertes depuis plus de 90 jours a compter de leur premiere detection, sur les codes sources deployes en production, ventile par niveau de criticite | Etat de vulnerabilite persiste par l'orchestrateur (derive de SCA_01). Pas de CMDB hors ventilation par filiere. Cible : index splunk | Meme principe que SAST_16. L'anciennete se compte a partir de la premiere detection sur le module, pas de la date de publication de la CVE | Nb distinct(module + composant + CVE) ou statut = ouvert ET (date du jour moins date de premiere detection) superieur a 90 j, groupe par criticite |

## Points d'arbitrage

Deux sujets transverses conditionnent l'ensemble.

Les quatre mesures d'exposition (SAST_14, SAST_15, SCA_10, SCA_11) reposent toutes sur le meme rapprochement CMDB via le CCX. Tant qu'il reste optionnel, aucune des quatre n'est produite.

Les huit mesures reposent sur l'objet d'etat par vulnerabilite cote orchestrateur. C'est le seul developpement reellement nouveau demande, et il est mutualise.
