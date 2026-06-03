ldapsearch -h localhost -p 1389 \
  -D "cn=administrator,dc=example,dc=com" \
  -w 2FederateM0re \
  -b "dc=example,dc=com" \
  "(objectClass=*)" dn




docker exec env-pingfederate-1 grep -r "puma-portal" /opt/out/instance/server/default/data/ 2>/dev/null

docker exec env-pingfederate-1 cat /opt/out/instance/server/default/data/oauth-clients/0/2faf3053c30c13380aa110ff25e4a87bdfa83996.xml
import com.nimbusds.jwt.SignedJWT;
import com.nimbusds.jwt.JWTClaimsSet;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;

curl -k https://localhost:1443/scim/v2/Users \
  -u "cn=administrator,dc=example,dc=com:2FederateM0re"


private void createViaLdap(CreateUserRequest req) throws NamingException {
    Hashtable<String, String> env = new Hashtable<>();
    env.put(Context.INITIAL_CONTEXT_FACTORY, "com.sun.jndi.ldap.LdapCtxFactory");
    env.put(Context.PROVIDER_URL, "ldap://" + host + ":" + ldapPort);
    env.put(Context.SECURITY_AUTHENTICATION, "simple");
    env.put(Context.SECURITY_PRINCIPAL, adminDn);
    env.put(Context.SECURITY_CREDENTIALS, adminPassword);

    DirContext ctx = new InitialDirContext(env);

    Attributes attrs = new BasicAttributes(true);
    BasicAttribute oc = new BasicAttribute("objectClass");
    oc.add("top");
    oc.add("person");
    oc.add("organizationalPerson");
    oc.add("inetOrgPerson");
    attrs.put(oc);
    attrs.put(new BasicAttribute("uid", req.uid()));
    attrs.put(new BasicAttribute("cn", req.firstName() + " " + req.lastName()));
    attrs.put(new BasicAttribute("sn", req.lastName()));
    attrs.put(new BasicAttribute("givenName", req.firstName()));
    attrs.put(new BasicAttribute("mail", req.email()));
    attrs.put(new BasicAttribute("userPassword", "Changeme123!"));

    String dn = "uid=" + req.uid() + ",ou=people,dc=example,dc=com";
    ctx.createSubcontext(dn, attrs);
    ctx.close();
}
  


@Bean
public JwtDecoder jwtDecoder() {
    return token -> {
        try {
            SignedJWT jwt = SignedJWT.parse(token);
            JWTClaimsSet claims = jwt.getJWTClaimsSet();
            
            Map<String, Object> headers = jwt.getHeader().toJSONObject();
            Map<String, Object> claimsMap = claims.toJSONObject();
            
            return new Jwt(
                token,
                claims.getIssueTime().toInstant(),
                claims.getExpirationTime().toInstant(),
                headers,
                claimsMap
            );
        } catch (Exception e) {
            throw new JwtException("Parse error: " + e.getMessage());
        }
    };
}
