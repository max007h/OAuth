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
