import java.util.Map;
import java.util.Enumeration;
import javax.servlet.http.HttpServletRequest;

// ... Au tout début de ton lookupAuthN ...

LOG.info("=== DEBUG COMPLET DES STRUCTURES PAR ===");

// 1. Structure : Requête HTTP brute (GET courant)
try {
    LOG.info("[DEBUG 1] --- HTTP Request Parameters ---");
    if (req != null) {
        Enumeration<String> paramNames = req.getParameterNames();
        while (paramNames != null && paramNames.hasMoreElements()) {
            String name = paramNames.nextElement();
            LOG.info("[DEBUG 1] Param: " + name + " = " + req.getParameter(name));
        }
    }
} catch (Exception e) { LOG.info("[DEBUG 1] Échec lecture HTTP"); }


// 2. Structure : Le Chained Context standard
try {
    LOG.info("[DEBUG 2] --- Chained Context Map ---");
    Map<String, Object> chainedContext = (Map<String, Object>) inParameters.get("chainedContext");
    if (chainedContext != null) {
        for (Map.Entry<String, Object> entry : chainedContext.entrySet()) {
            LOG.info("[DEBUG 2] Key: " + entry.getKey() + " -> " + entry.getValue());
            if ("authnParameters".equals(entry.getKey()) && entry.getValue() instanceof Map) {
                Map<String, String> subMap = (Map<String, String>) entry.getValue();
                for (Map.Entry<String, String> subEntry : subMap.entrySet()) {
                    LOG.info("[DEBUG 2]   -> authnParameter SubKey: " + subEntry.getKey() + " = " + subEntry.getValue());
                }
            }
        }
    } else { LOG.info("[DEBUG 2] 'chainedContext' est null"); }
} catch (Exception e) { LOG.info("[DEBUG 2] Échec lecture ChainedContext"); }


// 3. Structure : Tracked HTTP Parameters (via l'interface globale)
try {
    LOG.info("[DEBUG 3] --- Tracked HTTP Parameters ---");
    Map<String, Object> trackedParams = (Map<String, Object>) inParameters.get("com.pingidentity.sdk.IdentitySelector.InParameter.TrackedHttpParameters");
    if (trackedParams != null) {
        for (Map.Entry<String, Object> entry : trackedParams.entrySet()) {
            LOG.info("[DEBUG 3] Tracked Key: " + entry.getKey() + " = " + entry.getValue());
        }
    } else { LOG.info("[DEBUG 3] 'TrackedHttpParameters' est null"); }
} catch (Exception e) { LOG.info("[DEBUG 3] Échec lecture TrackedParams"); }


// 4. Structure : LoginContext & Contextual Objects (Cache profond OAuth)
try {
    LOG.info("[DEBUG 4] --- Contextual Objects (Reflexion) ---");
    Map<String, Object> contextualObjects = (Map<String, Object>) inParameters.get("com.pingidentity.sdk.v2.LoginContext.ContextualObjects");
    if (contextualObjects != null) {
        for (Map.Entry<String, Object> entry : contextualObjects.entrySet()) {
            LOG.info("[DEBUG 4] Object Class: " + entry.getKey());
            if (entry.getKey().contains("AuthorizationRequest")) {
                Object oauthRequest = entry.getValue();
                java.lang.reflect.Method method = oauthRequest.getClass().getMethod("getRawParameters");
                Map<String, String> rawParams = (Map<String, String>) method.invoke(oauthRequest);
                for (Map.Entry<String, String> param : rawParams.entrySet()) {
                    LOG.info("[DEBUG 4]   -> PAR Raw Param: " + param.getKey() + " = " + param.getValue());
                }
            }
        }
    } else { LOG.info("[DEBUG 4] 'ContextualObjects' est null"); }
} catch (Exception e) { LOG.info("[DEBUG 4] Échec lecture ContextualObjects"); }

LOG.info("========================================");











import com.pingidentity.sdk.IdentitySelector;
import java.util.Map;

// ... Dans ton lookupAuthN ...

String canal = null;
String userId = null;

// Extraction depuis la map globale des paramètres traqués (Tracked HTTP Parameters)
// PingFederate y stocke automatiquement les valeurs du POST PAR si configurées dans la console Admin !
Map<String, Object> trackedParams = (Map<String, Object>) inParameters.get(IdentitySelector.IN_PARAMETER_TRACKED_HTTP_PARAMETERS);

if (trackedParams != null) {
    canal = (String) trackedParams.get("canal");
    userId = (String) trackedParams.get("userId");
}

// Fallback de sécurité (Au cas où IdentitySelector n'est pas alimenté)
if (canal == null || userId == null) {
    Map<String, Object> chainedContext = (Map<String, Object>) inParameters.get("chainedContext");
    if (chainedContext != null) {
        Map<String, String> authnParams = (Map<String, String>) chainedContext.get("authnParameters");
        if (authnParams != null) {
            if (canal == null) canal = authnParams.get("canal");
            if (userId == null) userId = authnParams.get("userId");
        }
    }
}

// Log final pour ton terminal
LOG.info("[ParValidationAdapter] Extraction découplée -> canal=" + canal + " userId=" + userId);






 









// --- REMPLACE TON BLOC DE RÉCUPÉRATION PAR CELUI-CI ---
String canal = null;
String userId = null;

// 1. Extraction depuis le contexte chaîné de PingFederate (Spécifique à PAR)
Map<String, Object> chainedContext = (Map<String, Object>) inParameters.get("chainedContext");
if (chainedContext != null) {
    // Dans un flux PAR, PingFederate stocke les paramètres d'autorisation 
    // dans une sous-map nommée "authnParameters" à l'intérieur du chainedContext
    Map<String, String> authnParams = (Map<String, String>) chainedContext.get("authnParameters");
    
    if (authnParams != null) {
        canal = authnParams.get("canal");
        userId = authnParams.get("userId");
    }
    
    // Fallback 1b : Si ce n'est pas dans authnParameters, on regarde à la racine du chainedContext
    if (canal == null) {
        canal = (String) chainedContext.get("canal");
    }
    if (userId == null) {
        userId = (String) chainedContext.get("userId");
    }
}

// 2. Fallback 2 : Si ce n'est pas un flux PAR (paramètres classiques passés en Query String ou POST direct)
if (canal == null) {
    canal = request.getParameter("canal");
    if (canal == null) {
        canal = (String) request.getAttribute("canal");
    }
}

if (userId == null) {
    userId = request.getParameter("userId");
    if (userId == null) {
        userId = (String) request.getAttribute("userId");
    }
}
// --- FIN DU BLOC ---


    
    
    
    
    
    
    
    
    
    
    
    
    
    // --- BLOC DE VALIDATION ET REJET STRICT ---
    String erreur = valider(canal, userId);
    if (erreur != null) {
        LOG.warning("[ParValidationAdapter] REJET STRATEGIC : " + erreur);
        
        // On lève l'exception : PingFederate arrête immédiatement le traitement,
        // journalise l'erreur et affiche la page d'erreur native (authn.error.template.html).
        throw new AuthnAdapterException("invalid_request: " + erreur);
    }

    // Si la validation passe, le code continue vers la simulation Kafka et le statut SUCCESS...
    simulerPublicationKafka(canal, userId);





@Override
public AuthnAdapterResponse lookupAuthN(HttpServletRequest request,
                                        HttpServletResponse response,
                                        Map<String, Object> inParameters) throws AuthnAdapterException, IOException {

    
    
    
    
    
    
    
    
    
    
    // --- Remplace la fin de ta méthode par ce bloc ---

    // 1. Initialisation de la réponse de succès
    AuthnAdapterResponse ok = new AuthnAdapterResponse();
    ok.setAuthnStatus(AUTHN_STATUS.SUCCESS);

    // 2. Préparation des attributs à transmettre à PingFederate
    Map<String, Object> attributeMap = new HashMap<>();
    
    // On associe l'userId validé au 'subject' attendu par défaut
    if (userId != null) {
        attributeMap.put("subject", userId);
    } else {
        attributeMap.put("subject", "unknown_user");
    }
    
    // Optionnel : Tu peux injecter d'autres variables si ton adaptateur les déclare
    attributeMap.put("canal", canal); 
    
    // On embarque la map dans la réponse
    ok.setAttributeMap(attributeMap);

    LOG.info("[ParValidationAdapter] Validation réussie. Transmission du statut SUCCESS pour l'utilisateur: " + userId);
    return ok;
}











simulerPublicationKafka(canal, userId);

String resumePath = (String) inParameters.get("resumePath");
if (resumePath != null) {
    response.sendRedirect(resumePath);
    return null;
}

AuthnAdapterResponse ok = new AuthnAdapterResponse();
ok.setAuthnStatus(AUTHN_STATUS.IN_PROGRESS);
return ok;









// Remplace
ok.setAuthnStatus(AUTHN_STATUS.SUCCESS);
ok.setAttributeMap(Collections.emptyMap());
return ok;

// Par
ok.setAuthnStatus(AUTHN_STATUS.IN_PROGRESS);
return ok;



// DEBUG - à supprimer après
java.util.Enumeration<String> attrs = request.getAttributeNames();
while (attrs.hasMoreElements()) {
    String attr = attrs.nextElement();
    LOG.info("[ParValidationAdapter] ATTR: " + attr + " = " + request.getAttribute(attr));
}
java.util.Enumeration<String> params = request.getParameterNames();
while (params.hasMoreElements()) {
    String param = params.nextElement();
    LOG.info("[ParValidationAdapter] PARAM: " + param + " = " + request.getParameter(param));
}





String canal = (String) request.getAttribute("canal");
String userId = (String) request.getAttribute("userId");
if (canal == null) canal = request.getParameter("canal");
if (userId == null) userId = request.getParameter("userId");




import javax.servlet.http.HttpSession;

HttpSession session = request.getSession(false);
String canal = null;
String userId = null;
if (session != null) {
    canal = (String) session.getAttribute("canal");
    userId = (String) session.getAttribute("userId");
}
// Fallback sur request.getParameter si session vide
if (canal == null) canal = request.getParameter("canal");
if (userId == null) userId = request.getParameter("userId");






pfidpadapterid: 'PocParValidatorAdapter'



rm -rf src/main/resources/META-INF
mkdir -p src/main/resources/PF-INF
echo "com.poc.adapter.ParValidationAdapter" > src/main/resources/PF-INF/idp-authn-adapters

cat src/main/resources/PF-INF/idp-authn-adapters





unzip -p opentoken-adapter.jar PF-INF/idp-authn-adapters

unzip -p opentoken-adapter.jar META-INF/pluginDescriptor.xml



docker cp env-pingfederate-1:/opt/out/instance/server/default/deploy/opentoken-adapter-2.9.1.jar ./opentoken-adapter.jar
unzip -l opentoken-adapter.jar | grep -E "PF-INF|META-INF"


unzip -p opentoken-adapter.jar META-INF/pluginDescriptor.xml




unzip -l target/poc-par-validation-adapter.jar | grep -E "ParValidationAdapter|META-INF/com.pingidentity"



docker exec env-pingfederate-1 ls -la /opt/out/instance/server/default/deploy/


docker logs env-pingfederate-1 2>&1 | grep -i ParValidation
docker logs env-pingfederate-1 2>&1 | grep -iE "error|exception" | grep -i deploy



docker cp target/poc-par-validation-adapter.jar env-pingfederate-1:/opt/out/instance/server/default/deploy/
docker restart env-pingfederate-1






@Override
public IdpAuthnAdapterDescriptor getAdapterDescriptor() {
    return new IdpAuthnAdapterDescriptor(
        this,
        "POC PAR Validation Adapter",
        Collections.emptySet(),
        false,
        false
    );
}




javap -p /tmp/pfsdk/org/sourceid/saml20/adapter/idp/authn/IdpAuthenticationAdapter.class | grep "public abstract"

unzip -o pingfederate-sdk.jar -d /tmp/pfsdk org/sourceid/saml20/adapter/ConfigurableAuthnAdapter.class
javap -p /tmp/pfsdk/org/sourceid/saml20/adapter/ConfigurableAuthnAdapter.class | grep "public abstract"




mkdir -p /tmp/pfsdk
unzip -o pingfederate-sdk.jar -d /tmp/pfsdk \
  com/pingidentity/sdk/IdpAuthenticationAdapterV2.class \
  com/pingidentity/sdk/AuthnAdapterResponse.class \
  com/pingidentity/sdk/AuthnAdapterResponse\$AUTHN_STATUS.class \
  org/sourceid/saml20/adapter/idp/authn/IdpAuthnAdapterDescriptor.class \
  org/sourceid/saml20/adapter/idp/authn/IdpAuthenticationAdapter.class

javap -p /tmp/pfsdk/com/pingidentity/sdk/IdpAuthenticationAdapterV2.class
javap -p /tmp/pfsdk/com/pingidentity/sdk/AuthnAdapterResponse.class
javap -p /tmp/pfsdk/org/sourceid/saml20/adapter/idp/authn/IdpAuthnAdapterDescriptor.class
javap -p /tmp/pfsdk/org/sourceid/saml20/adapter/idp/authn/IdpAuthenticationAdapter.class





docker exec <conteneur_pf> sh -c '
for j in $(find /opt -iname "*.jar" 2>/dev/null); do
  if unzip -l "$j" 2>/dev/null | grep -q "IdpAuthenticationAdapterV2.class"; then
    echo "$j"
  fi
done'



<dependency>
  <groupId>com.pingidentity</groupId>
  <artifactId>pf-authn-api-sdk</artifactId>
  <version>1.0.0.86</version>
  <scope>system</scope>
  <systemPath>${project.basedir}/pf-authn-api-sdk.jar</systemPath>
</dependency>



com.poc.adapter.ParValidationAdapter



src/main/resources/META-INF/com.pingidentity.sdk.IdpAuthenticationAdapter



mvn install:install-file \
  -Dfile=./pf-authn-api-sdk.jar \
  -DgroupId=com.pingidentity \
  -DartifactId=pf-authn-api-sdk \
  -Dversion=1.0.0.86 \
  -Dpackaging=jar







dn: cn=Directory Manager,cn=Root DNs,cn=config
changetype: modify
add: ds-cfg-default-root-privilege-name
ds-cfg-default-root-privilege-name: proxied-auth

docker cp proxied.ldif env-pingdirectory-1:/tmp/proxied.ldif && docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapmodify --filename /tmp/proxied.ldif




docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch --baseDN "cn=Directory Manager,cn=Root DNs,cn=config" --searchScope base "(objectclass=*)" ds-cfg-alternate-bind-dn ds-cfg-default-root-privilege-name


docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch --baseDN "cn=Root DNs,cn=config" --searchScope sub "(objectclass=*)" objectClass dn



docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch --hostname localhost --port 1636 --useSSL --trustAll --bindDN "cn=Directory Manager" --bindPassword 2FederateM0re --baseDN "cn=Root DNs,cn=config" --searchScope sub "(objectclass=*)" cn ds-cfg-alternate-bind-dn ds-cfg-default-root-privilege-name


docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re \
  --baseDN "cn=root dns,cn=config" \
  --searchScope sub "(objectclass=*)" dn




docker exec env-pingdirectory-1 /bin/sh -c \
  'printf "dn: cn=administrator,cn=root dns,cn=config\nchangetype: modify\nadd: ds-cfg-default-root-privilege-name\nds-cfg-default-root-privilege-name: proxied-auth\n" > /tmp/proxied.ldif'



dn: cn=administrator,cn=root dns,cn=config
changetype: modify
add: ds-cfg-default-root-privilege-name
ds-cfg-default-root-privilege-name: proxied-auth


docker cp /tmp/proxied.ldif env-pingdirectory-1:/tmp/proxied.ldif

# 3. Appliquer
docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapmodify \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re \
  --filename /tmp/proxied.ldif





docker exec env-pingdirectory-1 bash -c "cat > /tmp/proxied.ldif << 'EOF'
dn: cn=administrator,cn=root dns,cn=config
changetype: modify
add: ds-cfg-default-root-privilege-name
ds-cfg-default-root-privilege-name: proxied-auth
EOF"


Processing MODIFY request for cn=administrator,cn=root dns,cn=config
MODIFY operation successful for DN cn=administrator,cn=root dns,cn=config








docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapmodify \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re << 'EOF'
dn: cn=administrator,cn=root dns,cn=config
changetype: modify
add: ds-cfg-default-root-privilege-name
ds-cfg-default-root-privilege-name: proxied-auth
EOF



# Voir toutes les password policies
docker exec env-pingdirectory-1 /opt/out/instance/bin/dsconfig \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re \
  --no-prompt \
  list-password-policies



# Voir les détails de la policy par défaut
docker exec env-pingdirectory-1 /opt/out/instance/bin/dsconfig \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re \
  --no-prompt \
  get-password-policy-prop \
  --policy-name "Default Password Policy"






# Voir toutes les password policies
docker exec env-pingdirectory-1 /opt/out/instance/bin/dsconfig \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re \
  --no-prompt \
  list-password-policies


# Voir les détails de la policy par défaut
docker exec env-pingdirectory-1 /opt/out/instance/bin/dsconfig \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=administrator" --bindPassword 2FederateM0re \
  --no-prompt \
  get-password-policy-prop \
  --policy-name "Default Password Policy"



# Vérifier la password policy appliquée à l'utilisateur
docker exec env-pingdirectory-1 /opt/out/instance/bin/ldapsearch \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=Directory Manager" --bindPassword 2FederateM0re \
  --baseDN "uid=Customer_1,ou=people,dc=example,dc=com" \
  --searchScope base "(objectclass=*)" pwdPolicySubentry passwordPolicySubentry

# Tenter un reset direct en ldapmodify
docker exec env-pingdirectory-1 /opt/out/instance/bin/ldappasswordmodify \
  --hostname localhost --port 1636 --useSSL --trustAll \
  --bindDN "cn=Directory Manager" --bindPassword 2FederateM0re \
  --authzID "uid=Customer_1,ou=people,dc=example,dc=com" \
  --newPassword "Password1234!"







docker exec env-pingdirectory-1 /opt/out/instance/bin/dsconfig \
  set-root-dn-prop \
  --root-dn-name "administrator" \
  --add default-root-privilege-name:proxied-auth \
  --hostname localhost \
  --port 1636 \
  --useSSL \
  --trustAll \
  --bindDN "cn=Directory Manager" \
  --bindPassword 2FederateM0re \
  --no-prompt



ldapsearch -h localhost -p 1389 -D 'cn=administrator' -w 2FederateM0re -b 'ou=people,dc=example,dc=com' '(uid=thomas)' mail



ldappasswd -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w 2FederateM0re \
  -s "NewPassword123!" \
  "uid=Customer_1,ou=people,dc=example,dc=com"



https://localhost:9031/idp/startSSO.ping?AdapterId=HTMLFormAdapter



https://localhost:9031/ext/localIdentityProfiles/TEgOfvAak6lBLI7R/registration



docker inspect mailpit --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'


docker exec env-pingfederate-1 bash -c "echo 'QUIT' | nc mailpit 1025"

docker exec env-pingfederate-1 bash -c "cat /dev/null > /dev/tcp/mailpit/1025 && echo OK || echo FAIL"


docker inspect mailpit --format='{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}'
docker inspect env-pingfederate-1 --format='{{range .NetworkSettings.Networks}}{{.NetworkID}} {{end}}'


docker network connect env_default mailpit




docker pull dockerhub.artifactory-dogen.group.echonet/axllent/mailpit

docker run -d \
  --name mailpit \
  --network 1eee2513ab2f5bd156318606f41c3565c8a1cd8f4c50db0163a763f2e882bdb9 \
  -p 1026:1025 \
  -p 8025:8025 \
  dockerhub.artifactory-dogen.group.echonet/axllent/mailpit


  docker run -d \
  --name mailhog \
  --platform linux/amd64 \
  --network nom_du_reseau \
  -p 1025:1025 \
  -p 8025:8025 \
  dockerhub.artifactory-dogen.group.echonet/mailhog/mailhog



mailhog:
  image: mailhog/mailhog
  ports:
    - "1025:1025"
    - "8025:8025"



https://localhost:9031/idp/startSSO.ping?AdapterId=HTMLFormAdapter&ForceAuthn=true



https://localhost:9031/as/authorization.oauth2?client_id=puma-portal&response_type=code&scope=openid&prompt=login



https://localhost:9031/as/authorization.oauth2?client_id=puma-portal&response_type=code&scope=openid&acr_values=urn:pingidentity:self-service:password-reset



https://localhost:9031/ext/localIdentityProfiles/TEgOfvAak6lBLI7R/registration


https://localhost:9031/idp/startSSO.ping?PartnerSpId=PasswordResetPOC

https://localhost:9031/ext/localIdentityProfiles/PasswordResetPOC/registration

curl -k -s \
  -u "administrator:2FederateM0re" \
  -H "X-XSRF-Header: PingFederate" \
  "https://localhost:9999/pf-admin-api/v1/localIdentityProfiles" \
  | python3 -m json.tool

<dependency>
    <groupId>com.fasterxml.jackson.core</groupId>
    <artifactId>jackson-databind</artifactId>
</dependency>

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

curl -k -s \
  -u "administrator:2FederateM0re" \
  -H "X-XSRF-Header: PingFederate" \
  "https://localhost:9999/pf-admin-api/v1/version"

curl -k -s \
  -u "administrator:2FederateM0re" \
  -H "X-XSRF-Header: PingFederate" \
  "https://localhost:9999/pf-admin-api/v1/passwordResetLinks" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"username": "Customer_1"}'



# Feature : Liste Utilisateurs + Reset Password URL

---

## 1. Backend — `UserProvisioningService` : méthode `listUsers()`

```java
public List<Map<String, String>> listUsers() throws NamingException {
    Hashtable<String, String> env = new Hashtable<>();
    env.put(Context.INITIAL_CONTEXT_FACTORY, "com.sun.jndi.ldap.LdapCtxFactory");
    env.put(Context.PROVIDER_URL, "ldap://" + host + ":" + ldapPort);
    env.put(Context.SECURITY_AUTHENTICATION, "simple");
    env.put(Context.SECURITY_PRINCIPAL, "cn=administrator,dc=example,dc=com");
    env.put(Context.SECURITY_CREDENTIALS, "2FederateM0re");

    DirContext ctx = new InitialDirContext(env);

    SearchControls controls = new SearchControls();
    controls.setSearchScope(SearchControls.SUBTREE_SCOPE);
    controls.setReturningAttributes(new String[]{"uid", "cn", "mail", "givenName", "sn"});

    NamingEnumeration<SearchResult> results = ctx.search(
        "ou=people,dc=example,dc=com",
        "(objectClass=inetOrgPerson)",
        controls
    );

    List<Map<String, String>> users = new ArrayList<>();
    while (results.hasMore()) {
        SearchResult sr = results.next();
        Attributes attrs = sr.getAttributes();
        Map<String, String> user = new HashMap<>();
        user.put("uid",   getAttr(attrs, "uid"));
        user.put("cn",    getAttr(attrs, "cn"));
        user.put("mail",  getAttr(attrs, "mail"));
        user.put("firstName", getAttr(attrs, "givenName"));
        user.put("lastName",  getAttr(attrs, "sn"));
        users.add(user);
    }
    ctx.close();
    return users;
}

private String getAttr(Attributes attrs, String name) throws NamingException {
    Attribute a = attrs.get(name);
    return a != null ? (String) a.get() : "";
}
```

---

## 2. Backend — `UserController` : endpoint GET /api/users

```java
@GetMapping("/api/users")
public ResponseEntity<List<Map<String, String>>> listUsers() throws NamingException {
    return ResponseEntity.ok(userProvisioningService.listUsers());
}
```

---

## 3. Backend — `PingFederateService` : generatePasswordResetLink()

```java
@Service
public class PingFederateService {

    @Value("${pingfederate.admin-url}")
    private String adminUrl;

    @Value("${pingfederate.admin-user}")
    private String adminUser;

    @Value("${pingfederate.admin-password}")
    private String adminPassword;

    public String generatePasswordResetLink(String uid) throws Exception {
        HttpClient client = HttpClient.newBuilder()
                .sslContext(trustAllSslContext())
                .build();

        String body = "{\"username\": \"" + uid + "\"}";

        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(adminUrl + "/pf-admin-api/v1/passwordResetLinks"))
                .header("Content-Type", "application/json")
                .header("Authorization", basicAuth(adminUser, adminPassword))
                .header("X-XSRF-Header", "PingFederate")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();

        HttpResponse<String> response = client.send(request,
                HttpResponse.BodyHandlers.ofString());

        if (response.statusCode() != 200) {
            throw new RuntimeException("PingFederate error " 
                + response.statusCode() + ": " + response.body());
        }

        ObjectMapper mapper = new ObjectMapper();
        JsonNode json = mapper.readTree(response.body());
        return json.get("resetLink").asText();
    }

    private String basicAuth(String user, String pass) {
        return "Basic " + Base64.getEncoder()
                .encodeToString((user + ":" + pass).getBytes(StandardCharsets.UTF_8));
    }

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

---

## 4. application.yml — à ajouter

```yaml
pingfederate:
  admin-url: https://localhost:9999
  admin-user: administrator
  admin-password: 2FederateM0re
```

---

## 5. UserProvisioningService — appel reset link à la création

```java
@Autowired
private PingFederateService pingFederateService;

public void createUser(CreateUserRequest req) throws Exception {
    createViaLdap(req);
    addToGroup(req.uid(), req.role());
    try {
        String resetUrl = pingFederateService.generatePasswordResetLink(req.uid());
        log.info(">>> Password reset URL for [{}]: {}", req.uid(), resetUrl);
    } catch (Exception e) {
        log.warn("Could not generate reset link for {}: {}", req.uid(), e.getMessage());
    }
}
```

---

## 6. Angular — user-list.component.ts

```typescript
import { Component, OnInit } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { OAuthService } from 'angular-oauth2-oidc';

interface User {
  uid: string;
  cn: string;
  mail: string;
  firstName: string;
  lastName: string;
}

@Component({
  selector: 'app-user-list',
  templateUrl: './user-list.component.html',
  styleUrls: ['./user-list.component.css']
})
export class UserListComponent implements OnInit {
  users: User[] = [];
  loading = false;
  error = '';

  constructor(private http: HttpClient, private oauthService: OAuthService) {}

  ngOnInit(): void {
    this.loadUsers();
  }

  loadUsers(): void {
    this.loading = true;
    this.error = '';
    const headers = new HttpHeaders({
      Authorization: `Bearer ${this.oauthService.getAccessToken()}`
    });
    this.http.get<User[]>('http://localhost:8081/api/users', { headers })
      .subscribe({
        next: (data) => { this.users = data; this.loading = false; },
        error: (err) => { this.error = 'Erreur chargement'; this.loading = false; }
      });
  }
}
```

---

## 7. Angular — user-list.component.html

```html
<div class="container">
  <h2>Utilisateurs</h2>

  <div *ngIf="loading" class="loading">Chargement...</div>
  <div *ngIf="error" class="error">{{ error }}</div>

  <table *ngIf="!loading && users.length > 0">
    <thead>
      <tr>
        <th>UID</th>
        <th>Prénom</th>
        <th>Nom</th>
        <th>Email</th>
      </tr>
    </thead>
    <tbody>
      <tr *ngFor="let user of users">
        <td>{{ user.uid }}</td>
        <td>{{ user.firstName }}</td>
        <td>{{ user.lastName }}</td>
        <td>{{ user.mail }}</td>
      </tr>
    </tbody>
  </table>

  <p *ngIf="!loading && users.length === 0">Aucun utilisateur.</p>
</div>
```

---

## 8. Angular — routing (app-routing.module.ts)

```typescript
{ path: 'users', component: UserListComponent, canActivate: [AuthGuard] }
```

---

## 9. Angular — bouton dans la navbar

Dans ton composant navbar/header existant, ajoute :

```html
<button routerLink="/users">Liste utilisateurs</button>
<button (click)="logout()">Sign out</button>
```

---

## Imports Java nécessaires

```java
import javax.naming.*;
import javax.naming.directory.*;
import java.util.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.net.http.*;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.cert.X509Certificate;
import javax.net.ssl.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
```
