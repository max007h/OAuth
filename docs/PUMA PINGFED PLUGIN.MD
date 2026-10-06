package com.poc.adapter;

import com.pingidentity.sdk.AuthnAdapterResponse;
import com.pingidentity.sdk.AuthnAdapterResponse.AUTHN_STATUS;
import com.pingidentity.sdk.IdpAuthenticationAdapterV2;
import org.sourceid.saml20.adapter.AuthnAdapterException;
import org.sourceid.saml20.adapter.conf.Configuration;
import org.sourceid.saml20.adapter.idp.authn.AuthnPolicy;
import org.sourceid.saml20.adapter.idp.authn.IdpAuthnAdapterDescriptor;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import java.io.IOException;
import java.io.PrintWriter;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Base64;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.logging.Logger;

/**
 * Lets the user pick a working node right after authentication, inside the PingFederate flow.
 * Chained after HTMLFormAdapter. Returns subject and node to the policy contract.
 */
public class NodeSelectionAdapter implements IdpAuthenticationAdapterV2 {

    private static final Logger LOG = Logger.getLogger(NodeSelectionAdapter.class.getName());

    // PingFederate keys, kept as literals to avoid depending on SDK constants
    private static final String KEY_CHAINED = "com.pingidentity.adapter.input.parameter.chained.attributes";
    private static final String KEY_RESUME = "com.pingidentity.adapter.input.parameter.resume.path";

    // Form and session parameters
    private static final String PARAM_NODE = "puma_node";
    private static final String PARAM_CSRF = "puma_csrf";
    private static final String SESSION_CSRF = "puma.node.selection.csrf";

    // PUMA application in the catalogue
    private static final String APPLICATION = "A0";

    // PostgreSQL connection, can be overridden by container environment variables.
    // Default values TO BE COPIED from the PingFederate puma-postgres data store.
    private static final String DB_URL = env("PUMA_DB_URL", "jdbc:postgresql://host.docker.internal:5432/TO_BE_SET");
    private static final String DB_USER = env("PUMA_DB_USER", "TO_BE_SET");
    private static final String DB_PASSWORD = env("PUMA_DB_PASSWORD", "TO_BE_SET");

    private static final String SQL_NODES =
            "SELECT DISTINCT v.node_id, n.label "
          + "FROM puma_user_node_roles v "
          + "JOIN node n ON n.id = v.node_id "
          + "WHERE v.uid = lower(?) AND v.application_id = ? "
          + "ORDER BY n.label";

    private static final SecureRandom RANDOM = new SecureRandom();

    @Override
    public IdpAuthnAdapterDescriptor getAdapterDescriptor() {
        return new IdpAuthnAdapterDescriptor(this, "PUMA Node Selection Adapter",
                Set.of("subject", "node"), false, null);
    }

    @Override
    public void configure(Configuration configuration) {
    }

    @Override
    public Map<String, Object> getAdapterInfo() {
        return Collections.emptyMap();
    }

    @Override
    @SuppressWarnings("rawtypes")
    public Map lookupAuthN(HttpServletRequest req, HttpServletResponse resp,
                           String partnerSpEntityId, AuthnPolicy policy, String resumePath)
            throws AuthnAdapterException, IOException {
        return Collections.emptyMap();
    }

    @Override
    @SuppressWarnings("rawtypes")
    public boolean logoutAuthN(Map authnIdentifiers, HttpServletRequest req,
                               HttpServletResponse resp, String resumePath)
            throws AuthnAdapterException, IOException {
        return false;
    }

    @Override
    public AuthnAdapterResponse lookupAuthN(HttpServletRequest request,
                                            HttpServletResponse response,
                                            Map<String, Object> inParameters)
            throws AuthnAdapterException, IOException {

        String uid = chainedUid(inParameters);
        if (uid == null) {
            LOG.warning("[NodeSelectionAdapter] No user found in chained attributes. Received keys: "
                    + (inParameters == null ? "null" : inParameters.keySet()));
            return failure("User not identified");
        }

        Map<String, String> nodes;
        try {
            nodes = loadNodes(uid);
        } catch (SQLException | ClassNotFoundException e) {
            LOG.severe("[NodeSelectionAdapter] Unable to load nodes: " + e.getMessage());
            return failure("Contexts unavailable");
        }

        if (nodes.isEmpty()) {
            LOG.warning("[NodeSelectionAdapter] No node for " + uid);
            return failure("No context available for this user");
        }

        String chosen = request.getParameter(PARAM_NODE);

        // First pass: render the selection page
        if (chosen == null) {
            String resume = resumePath(inParameters);
            if (resume == null) {
                return failure("Missing resume path");
            }
            String csrf = newToken();
            request.getSession(true).setAttribute(SESSION_CSRF, csrf);
            renderPage(response, resume, nodes, csrf);
            AuthnAdapterResponse inProgress = new AuthnAdapterResponse();
            inProgress.setAuthnStatus(AUTHN_STATUS.IN_PROGRESS);
            return inProgress;
        }

        // Second pass: check the CSRF token, then the selected node
        HttpSession session = request.getSession(false);
        Object expected = session == null ? null : session.getAttribute(SESSION_CSRF);
        if (session != null) {
            session.removeAttribute(SESSION_CSRF);
        }
        if (expected == null || !expected.equals(request.getParameter(PARAM_CSRF))) {
            LOG.warning("[NodeSelectionAdapter] Invalid CSRF token for " + uid);
            return failure("Invalid request");
        }
        if (!nodes.containsKey(chosen)) {
            LOG.warning("[NodeSelectionAdapter] Node rejected for " + uid + " : " + chosen);
            return failure("Context not allowed");
        }

        Map<String, Object> attributes = new HashMap<>();
        attributes.put("subject", uid.toLowerCase());
        attributes.put("node", chosen);

        AuthnAdapterResponse ok = new AuthnAdapterResponse();
        ok.setAuthnStatus(AUTHN_STATUS.SUCCESS);
        ok.setAttributeMap(attributes);
        LOG.info("[NodeSelectionAdapter] Context selected by " + uid + " : " + chosen);
        return ok;
    }

    // Identifier of the user authenticated by the previous adapter
    @SuppressWarnings("unchecked")
    private String chainedUid(Map<String, Object> inParameters) {
        if (inParameters == null) {
            return null;
        }
        Object chained = inParameters.get(KEY_CHAINED);
        if (!(chained instanceof Map)) {
            return null;
        }
        Map<String, Object> attrs = (Map<String, Object>) chained;
        for (String key : new String[] {"username", "subject", "uid"}) {
            String value = firstValue(attrs.get(key));
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return null;
    }

    private String resumePath(Map<String, Object> inParameters) {
        Object value = inParameters.get(KEY_RESUME);
        if (value == null) {
            value = inParameters.get("resumePath");
        }
        return value == null ? null : value.toString();
    }

    private static String firstValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Collection) {
            Collection<?> c = (Collection<?>) value;
            return c.isEmpty() ? null : String.valueOf(c.iterator().next());
        }
        if (value instanceof String[]) {
            String[] a = (String[]) value;
            return a.length == 0 ? null : a[0];
        }
        return String.valueOf(value);
    }

    private Map<String, String> loadNodes(String uid) throws SQLException, ClassNotFoundException {
        Class.forName("org.postgresql.Driver");
        Map<String, String> nodes = new LinkedHashMap<>();
        try (Connection c = DriverManager.getConnection(DB_URL, DB_USER, DB_PASSWORD);
             PreparedStatement ps = c.prepareStatement(SQL_NODES)) {
            ps.setString(1, uid);
            ps.setString(2, APPLICATION);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    nodes.put(rs.getString(1), rs.getString(2));
                }
            }
        }
        return nodes;
    }

    private void renderPage(HttpServletResponse response, String resume,
                            Map<String, String> nodes, String csrf) throws IOException {
        response.setContentType("text/html; charset=UTF-8");
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Frame-Options", "DENY");
        PrintWriter out = response.getWriter();
        out.println("<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"UTF-8\">");
        out.println("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
        out.println("<title>PUMA, select your context</title>");
        out.println("<style>body{font-family:Arial,sans-serif;background:#f4f5f7;margin:0}"
                + ".card{max-width:420px;margin:80px auto;background:#fff;padding:32px;border-radius:8px;"
                + "box-shadow:0 2px 8px rgba(0,0,0,.1)}h1{font-size:20px;margin:0 0 8px}"
                + "p{color:#555;font-size:14px}select,button{width:100%;padding:10px;margin-top:12px;"
                + "font-size:15px}button{background:#00754a;color:#fff;border:0;border-radius:4px;cursor:pointer}"
                + "</style></head><body><div class=\"card\">");
        out.println("<h1>Select your context</h1>");
        out.println("<p>Choose the node you want to work on.</p>");
        out.println("<form method=\"post\" action=\"" + escape(resume) + "\">");
        out.println("<input type=\"hidden\" name=\"" + PARAM_CSRF + "\" value=\"" + escape(csrf) + "\">");
        out.println("<select name=\"" + PARAM_NODE + "\" required>");
        for (Map.Entry<String, String> e : nodes.entrySet()) {
            out.println("<option value=\"" + escape(e.getKey()) + "\">"
                    + escape(e.getValue()) + " (" + escape(e.getKey()) + ")</option>");
        }
        out.println("</select><button type=\"submit\">Continue</button></form></div></body></html>");
        out.flush();
    }

    private static AuthnAdapterResponse failure(String message) {
        AuthnAdapterResponse r = new AuthnAdapterResponse();
        r.setAuthnStatus(AUTHN_STATUS.FAILURE);
        r.setErrorMessage(message);
        return r;
    }

    private static String newToken() {
        byte[] b = new byte[32];
        RANDOM.nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    private static String escape(String s) {
        if (s == null) {
            return "";
        }
        return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&#39;");
    }

    private static String env(String name, String fallback) {
        String v = System.getenv(name);
        return (v == null || v.isBlank()) ? fallback : v;
    }
}

        





# PUMA phase 2 : choix du noeud dans PingFederate, sans token exchange

Le noeud est choisi dans le parcours PingFederate, sur une page affichée juste après le login. Le token final émis au client puma-portal contient directement sub, node et roles. Le flux actuel par token exchange reste en place tant que celui-ci n'est pas validé.

## 0. Avant de commencer

1. Exporter la configuration PingFederate (System, Configuration Archive).
2. Travailler sur une branche Git pour le front.

## 1. Code

### 1.1 Ajouter la classe

Copier NodeSelectionAdapter.java dans src/main/java/com/poc/adapter/.

Les imports ont été écrits sans voir ceux de ParValidationAdapter. Avant de compiler, remplacer le bloc d'imports de NodeSelectionAdapter par celui de ParValidationAdapter pour les classes communes : HttpServletRequest, HttpServletResponse (javax ou jakarta selon la version), AuthnAdapterException, AuthnPolicy, Configuration, IdpAuthnAdapterDescriptor, AuthnAdapterResponse, IdpAuthenticationAdapterV2. Ajouter HttpSession dans le même package que HttpServletRequest.

Reprendre aussi exactement la forme de l'appel new IdpAuthnAdapterDescriptor(...) de ParValidationAdapter, en remplaçant seulement le nom par "PUMA Node Selection Adapter" et le contrat par Set.of("subject", "node").

### 1.2 Renseigner la connexion à la base

Dans NodeSelectionAdapter, remplacer les trois valeurs A_COMPLETER par celles du data store puma-postgres de PingFederate (URL JDBC, compte, mot de passe). Elles peuvent aussi être passées par les variables d'environnement PUMA_DB_URL, PUMA_DB_USER et PUMA_DB_PASSWORD du conteneur.

### 1.3 Déclarer le plugin

Dans le dossier PF-INF, ouvrir le fichier qui contient déjà com.poc.adapter.ParValidationAdapter et ajouter la ligne :

```
com.poc.adapter.NodeSelectionAdapter
```

### 1.4 Construire et vérifier le jar

```
mvn clean package
unzip -l target/poc-par-validation-adapter.jar | grep -E "NodeSelectionAdapter|PF-INF"
unzip -p target/poc-par-validation-adapter.jar PF-INF/* | grep NodeSelection
```

Attendu : la classe est présente, et le descripteur PF-INF contient les deux adapters.

## 2. Déploiement

```
docker cp target/poc-par-validation-adapter.jar env-pingfederate-1:/opt/out/instance/server/default/deploy/
docker exec env-pingfederate-1 ls -l /opt/out/instance/server/default/lib | grep postgresql
docker restart env-pingfederate-1
```

Le driver postgresql-42.7.3.jar doit être présent dans lib. Attendre la fin du démarrage, puis vérifier dans Authentication, IdP Adapters, Create New Instance, que le type PUMA Node Selection Adapter apparaît.

## 3. Configuration PingFederate

1. Créer l'instance de l'adapter : id NodeSelection, type PUMA Node Selection Adapter. Le contrat contient subject et node.
2. Dans le contrat de politique utilisé par puma-portal (PumaContract), ajouter l'attribut node.
3. Dans PumaAuthPolicy, construire la chaîne : HTMLFormAdapter, puis sur Success NodeSelection, puis sur Success PumaContract. Les branches Fail se terminent sans contrat. Contract Fulfillment : subject et node depuis NodeSelection.
4. Dans l'Access Token Mapping de PumaContract vers l'ATM de puma-portal :
   1. ajouter une source JDBC sur puma_user_node_roles avec le filtre `uid = '${subject}' AND node_id = '${node}'` ;
   2. mapper node depuis le contrat et roles depuis cette source ;
   3. ajouter l'Issuance Criteria sur role_id non vide, avec le message node_not_assigned.
5. Vérifier que l'ATM de puma-portal signe avec la même clé poc-key que JWTAccessToken. Sinon, le backend rejettera le token.

## 4. Frontend PUMA

1. Ne plus ouvrir la pop-up ContextPickerV2 quand le token contient déjà node et roles.
2. Corriger ContextV2Service.hasContext : tester la présence de node et roles dans le token, et non client_id === 'puma-backend'.
3. Changer de contexte revient à relancer une demande d'autorisation. La session PingFederate évite de ressaisir le mot de passe.

## 5. Tests attendus

| Test | Attendu |
|---|---|
| Login thomas.martin | La page de choix s'affiche avec les mêmes noeuds que la requête pgAdmin |
| Choix de Roller 5 | Le token contient node 9200005 et les rôles de thomas sur ce noeud |
| Valeur du select modifiée en 2700015 dans les outils du navigateur | Échec, message Contexte non autorisé, ligne Noeud refuse dans les logs |
| Formulaire renvoyé sans le champ puma_csrf | Échec, message Requete invalide |
| Utilisateur sans aucun rôle sur PUMA | Échec, message Aucun contexte disponible |
| Création d'utilisateur sur 9200005 puis sur 2700015 | PERMIT puis DENY, comme avec le flux actuel |

Logs utiles :

```
docker logs env-pingfederate-1 2>&1 | grep NodeSelectionAdapter
```

Si l'adapter signale qu'aucun utilisateur n'est présent dans les attributs chaînés, la ligne de log affiche les clés reçues : il suffit alors d'ajuster le nom de l'attribut lu dans chainedUid.

## 6. Points d'attention

1. Le token final arrive dans la SPA avec le noeud et les rôles. C'est un écart par rapport à l'engagement pris avec David, sauf si l'échange du code passe par le backend.
2. Le déploiement du jar est perdu si le conteneur est recréé, faute de volume persistant sur /opt/out.
3. Les identifiants de la base sont dans le code ou l'environnement du conteneur : acceptable pour le POC, à remplacer par le data store de PingFederate ou un coffre en cible.
