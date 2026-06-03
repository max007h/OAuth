docker exec env-pingfederate-1 grep -r "puma-portal" /opt/out/instance/server/default/data/ 2>/dev/null

docker exec env-pingfederate-1 cat /opt/out/instance/server/default/data/oauth-clients/0/2faf3053c30c13380aa110ff25e4a87bdfa83996.xml
import com.nimbusds.jwt.SignedJWT;
import com.nimbusds.jwt.JWTClaimsSet;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;


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
