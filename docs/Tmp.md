package com.poc.puma.security;

import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;

public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtDecoder jwtDecoder;

    public JwtAuthenticationFilter(JwtDecoder jwtDecoder) {
        this.jwtDecoder = jwtDecoder;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain)
            throws ServletException, IOException {

        String header = request.getHeader("Authorization");

        if (header != null && header.startsWith("Bearer ")) {
            String token = header.substring(7);
            try {
                Jwt jwt = jwtDecoder.decode(token);
                JwtAuthenticationToken authentication =
                    new JwtAuthenticationToken(jwt);
                org.springframework.security.core.context
                    .SecurityContextHolder.getContext()
                    .setAuthentication(authentication);
            } catch (Exception e) {
                response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                return;
            }
        }
        filterChain.doFilter(request, response);
    }
}








# PUMA Portal — Complete Source Code

## Architecture

```
[Browser :4200]
    │ Authorization Code + PKCE (RS256, no RAR, no PAR)
    ▼
[PingFederate :9031]
    │ isMemberOf claim in JWT
    ▼
[Spring Boot :8081]
    │ SCIM v2 + LDAP
    ▼
[PingDirectory :1636/:443]
```

---

## Frontend — Angular

### `auth.config.ts`

```typescript
// OAuth2 / PingFederate constants — PUMA Portal
export const AUTH_CONFIG = {
  PF:       'https://localhost:9031',
  CLIENT:   'puma-portal',
  REDIRECT: 'http://localhost:4200/callback',
  SCOPE:    'openid profile',
};
```

---

### `auth.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AUTH_CONFIG as C } from './auth.config';

export interface TokenData {
  access_token:  string;
  id_token:      string;
  expires_in:    number;
}

@Injectable({ providedIn: 'root' })
export class AuthService {

  // ── PKCE ────────────────────────────────────────────────
  private generateVerifier(): string {
    const arr = new Uint8Array(32);
    crypto.getRandomValues(arr);
    return btoa(String.fromCharCode(...arr))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  private async generateChallenge(verifier: string): Promise<string> {
    const enc  = new TextEncoder().encode(verifier);
    const hash = await crypto.subtle.digest('SHA-256', enc);
    return btoa(String.fromCharCode(...new Uint8Array(hash)))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  }

  // ── Login — redirect to PingFederate ────────────────────
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

  // ── Exchange authorization code for tokens ───────────────
  async exchangeCode(code: string): Promise<void> {
    const verifier = sessionStorage.getItem('pkce_verifier')!;

    const body = new URLSearchParams({
      grant_type:    'authorization_code',
      client_id:     C.CLIENT,
      code,
      redirect_uri:  C.REDIRECT,
      code_verifier: verifier,
    });

    // Use Python proxy on port 9032 (same pattern as banking-spa)
    const resp = await fetch('http://localhost:9032/as/token.oauth2', {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    body.toString(),
    });

    if (!resp.ok) {
      throw new Error(`Token exchange failed: ${resp.status}`);
    }

    const data: TokenData = await resp.json();
    sessionStorage.setItem('access_token', data.access_token);
    sessionStorage.setItem('id_token',     data.id_token ?? '');
    sessionStorage.setItem('token_expiry',
      String(Date.now() + (data.expires_in || 300) * 1000));
  }

  // ── JWT decode (no external lib) ────────────────────────
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

  // ── Role helpers ─────────────────────────────────────────
  isManager(): boolean {
    const token = this.getToken();
    if (!token) return false;
    const claims = this.decodeJwt(token);
    const groups: string[] = claims?.['isMemberOf'] ?? [];
    return groups.some(g => g.toUpperCase().includes('MANAGER'));
  }

  isCommercial(): boolean {
    const token = this.getToken();
    if (!token) return false;
    const claims = this.decodeJwt(token);
    const groups: string[] = claims?.['isMemberOf'] ?? [];
    return groups.some(g => g.toUpperCase().includes('COMMERCIAL'));
  }

  isAuthenticated(): boolean {
    return !!this.getToken();
  }

  isTokenExpired(): boolean {
    const expiry = sessionStorage.getItem('token_expiry');
    if (!expiry) return true;
    return Date.now() > parseInt(expiry);
  }

  // ── Token access ─────────────────────────────────────────
  getToken(): string | null {
    return sessionStorage.getItem('access_token');
  }

  getIdToken(): string | null {
    return sessionStorage.getItem('id_token');
  }

  // ── Logout — PingFederate SLO ────────────────────────────
  logout(): void {
    const idToken = this.getIdToken();
    sessionStorage.clear();
    if (idToken) {
      window.location.href =
        `${C.PF}/idp/startSLO.ping?id_token_hint=${idToken}` +
        `&post_logout_redirect_uri=${encodeURIComponent(C.REDIRECT)}`;
    } else {
      window.location.href = '/';
    }
  }

  clearSession(): void {
    sessionStorage.clear();
  }
}
```

---

### `manager.guard.ts`

```typescript
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from './auth.service';

export const managerGuard = () => {
  const auth   = inject(AuthService);
  const router = inject(Router);

  if (!auth.isAuthenticated() || auth.isTokenExpired()) {
    auth.login();
    return false;
  }

  if (auth.isManager()) return true;

  router.navigate(['/dashboard']);
  return false;
};
```

---

### `app.routes.ts`

```typescript
import { Routes } from '@angular/router';
import { managerGuard } from './manager.guard';

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
    path: 'dashboard',
    loadComponent: () =>
      import('./dashboard/dashboard.component').then(m => m.DashboardComponent),
  },
  {
    path: 'create-user',
    canActivate: [managerGuard],
    loadComponent: () =>
      import('./create-user/create-user.component')
        .then(m => m.CreateUserComponent),
  },
  {
    path: '**',
    redirectTo: '',
  },
];
```

---

### `home.component.ts`

```typescript
import { Component } from '@angular/core';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-home',
  standalone: true,
  template: `
    <div class="page">
      <div class="card">
        <div class="logo">PUMA</div>
        <p class="subtitle">User Provisioning Portal</p>
        <button class="btn-primary" (click)="login()">
          Sign in with PingFederate
        </button>
      </div>
    </div>
  `,
  styles: [`
    .page {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #f4f6f8;
    }
    .card {
      background: #fff;
      border: 1px solid #dde1e7;
      border-radius: 8px;
      padding: 48px 56px;
      text-align: center;
      width: 360px;
    }
    .logo {
      font-size: 36px;
      font-weight: 700;
      letter-spacing: 6px;
      color: #1a1a2e;
      margin-bottom: 8px;
    }
    .subtitle {
      font-size: 14px;
      color: #6b7280;
      margin-bottom: 32px;
    }
    .btn-primary {
      width: 100%;
      padding: 12px;
      background: #1a1a2e;
      color: #fff;
      border: none;
      border-radius: 6px;
      font-size: 15px;
      cursor: pointer;
      transition: background 0.2s;
    }
    .btn-primary:hover { background: #2d2d4e; }
  `],
})
export class HomeComponent {
  constructor(private auth: AuthService) {}
  login() { this.auth.login(); }
}
```

---

### `callback.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-callback',
  standalone: true,
  template: `
    <div class="page">
      <p>Signing in...</p>
    </div>
  `,
  styles: [`
    .page {
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      font-family: sans-serif;
      color: #6b7280;
    }
  `],
})
export class CallbackComponent implements OnInit {
  constructor(private auth: AuthService, private router: Router) {}

  async ngOnInit(): Promise<void> {
    const params = new URLSearchParams(window.location.search);
    const code   = params.get('code');
    const error  = params.get('error');

    if (error || !code) {
      console.error('OAuth error:', error);
      this.router.navigate(['/']);
      return;
    }

    try {
      await this.auth.exchangeCode(code);
      this.router.navigate(['/dashboard']);
    } catch (e) {
      console.error('Token exchange error:', e);
      this.router.navigate(['/']);
    }
  }
}
```

---

### `dashboard.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterModule } from '@angular/router';
import { AuthService } from '../auth.service';

@Component({
  selector: 'app-dashboard',
  standalone: true,
  imports: [CommonModule, RouterModule],
  template: `
    <div class="page">
      <div class="topbar">
        <span class="logo">PUMA</span>
        <button class="btn-logout" (click)="logout()">Sign out</button>
      </div>

      <div class="content">

        <!-- MANAGER VIEW -->
        <ng-container *ngIf="isManager">
          <div class="card">
            <h2>Welcome, Manager</h2>
            <p>You can create new commercial users.</p>
            <a routerLink="/create-user" class="btn-primary">
              Create a Commercial User
            </a>
          </div>
        </ng-container>

        <!-- COMMERCIAL VIEW -->
        <ng-container *ngIf="isCommercial && !isManager">
          <div class="card">
            <h2>Welcome</h2>
            <p class="role-msg">
              You are authenticated as <strong>Commercial</strong>.
            </p>
          </div>
        </ng-container>

        <!-- UNKNOWN ROLE -->
        <ng-container *ngIf="!isManager && !isCommercial">
          <div class="card">
            <h2>Access Restricted</h2>
            <p>Your account does not have an assigned role.</p>
          </div>
        </ng-container>

      </div>
    </div>
  `,
  styles: [`
    * { box-sizing: border-box; margin: 0; padding: 0; }
    .page { min-height: 100vh; background: #f4f6f8; font-family: sans-serif; }
    .topbar {
      background: #1a1a2e;
      color: #fff;
      padding: 0 32px;
      height: 56px;
      display: flex;
      align-items: center;
      justify-content: space-between;
    }
    .logo { font-weight: 700; letter-spacing: 4px; font-size: 18px; }
    .btn-logout {
      background: transparent;
      border: 1px solid rgba(255,255,255,0.4);
      color: #fff;
      padding: 6px 16px;
      border-radius: 4px;
      cursor: pointer;
      font-size: 13px;
    }
    .btn-logout:hover { background: rgba(255,255,255,0.1); }
    .content {
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 80px 24px;
    }
    .card {
      background: #fff;
      border: 1px solid #dde1e7;
      border-radius: 8px;
      padding: 48px 56px;
      text-align: center;
      max-width: 440px;
      width: 100%;
    }
    h2 { font-size: 22px; color: #1a1a2e; margin-bottom: 12px; }
    p { color: #6b7280; font-size: 15px; margin-bottom: 28px; }
    .role-msg { margin-bottom: 0; }
    .btn-primary {
      display: inline-block;
      padding: 12px 28px;
      background: #1a1a2e;
      color: #fff;
      border-radius: 6px;
      text-decoration: none;
      font-size: 15px;
      transition: background 0.2s;
    }
    .btn-primary:hover { background: #2d2d4e; }
  `],
})
export class DashboardComponent implements OnInit {
  isManager    = false;
  isCommercial = false;

  constructor(private auth: AuthService, private router: Router) {}

  ngOnInit(): void {
    if (!this.auth.isAuthenticated() || this.auth.isTokenExpired()) {
      this.router.navigate(['/']);
      return;
    }
    this.isManager    = this.auth.isManager();
    this.isCommercial = this.auth.isCommercial();
  }

  logout(): void { this.auth.logout(); }
}
```

---

### `create-user.component.ts`

```typescript
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../auth.service';

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
    <div class="page">
      <div class="topbar">
        <span class="logo">PUMA</span>
        <div class="topbar-actions">
          <a class="back" (click)="goBack()">← Back</a>
          <button class="btn-logout" (click)="logout()">Sign out</button>
        </div>
      </div>

      <div class="content">
        <div class="card">
          <h2>Create User</h2>
          <p class="subtitle">Fill in the details to provision a new user in PingDirectory.</p>

          <!-- SUCCESS -->
          <div class="alert success" *ngIf="successMessage">
            <strong>✓ User created</strong>
            <p>{{ successMessage }}</p>
            <p class="reset-url">
              The user must set their password at:<br>
              <a href="https://localhost:9031/ext/pwdreset" target="_blank">
                https://localhost:9031/ext/pwdreset
              </a>
            </p>
          </div>

          <!-- ERROR -->
          <div class="alert error" *ngIf="errorMessage">
            <strong>✗ Error</strong>
            <p>{{ errorMessage }}</p>
          </div>

          <!-- FORM -->
          <form (ngSubmit)="submit()" *ngIf="!successMessage">

            <div class="field">
              <label>Login (uid)</label>
              <input [(ngModel)]="form.uid" name="uid"
                     placeholder="e.g. jean.dupont" required />
            </div>

            <div class="row">
              <div class="field">
                <label>First Name</label>
                <input [(ngModel)]="form.firstName" name="firstName"
                       placeholder="Jean" required />
              </div>
              <div class="field">
                <label>Last Name</label>
                <input [(ngModel)]="form.lastName" name="lastName"
                       placeholder="Dupont" required />
              </div>
            </div>

            <div class="field">
              <label>Email</label>
              <input [(ngModel)]="form.email" name="email"
                     type="email" placeholder="jean.dupont@example.com" required />
            </div>

            <div class="field">
              <label>Role</label>
              <select [(ngModel)]="form.role" name="role">
                <option value="COMMERCIAL">Commercial</option>
                <option value="MANAGER">Manager</option>
              </select>
            </div>

            <button type="submit" class="btn-primary" [disabled]="loading">
              {{ loading ? 'Creating...' : 'Create User' }}
            </button>

          </form>

          <button class="btn-secondary" *ngIf="successMessage" (click)="reset()">
            Create another user
          </button>

        </div>
      </div>
    </div>
  `,
  styles: [`
    * { box-sizing: border-box; margin: 0; padding: 0; }
    .page { min-height: 100vh; background: #f4f6f8; font-family: sans-serif; }
    .topbar {
      background: #1a1a2e; color: #fff; padding: 0 32px; height: 56px;
      display: flex; align-items: center; justify-content: space-between;
    }
    .logo { font-weight: 700; letter-spacing: 4px; font-size: 18px; }
    .topbar-actions { display: flex; align-items: center; gap: 16px; }
    .back { color: rgba(255,255,255,0.7); font-size: 13px; cursor: pointer; }
    .back:hover { color: #fff; }
    .btn-logout {
      background: transparent; border: 1px solid rgba(255,255,255,0.4);
      color: #fff; padding: 6px 16px; border-radius: 4px; cursor: pointer; font-size: 13px;
    }
    .btn-logout:hover { background: rgba(255,255,255,0.1); }
    .content { display: flex; justify-content: center; padding: 48px 24px; }
    .card {
      background: #fff; border: 1px solid #dde1e7; border-radius: 8px;
      padding: 40px 48px; width: 100%; max-width: 520px;
    }
    h2 { font-size: 20px; color: #1a1a2e; margin-bottom: 6px; }
    .subtitle { font-size: 14px; color: #6b7280; margin-bottom: 28px; }
    .alert { border-radius: 6px; padding: 16px; margin-bottom: 24px; font-size: 14px; }
    .alert strong { display: block; margin-bottom: 4px; }
    .alert.success { background: #f0fdf4; border: 1px solid #bbf7d0; color: #166534; }
    .alert.error   { background: #fef2f2; border: 1px solid #fecaca; color: #991b1b; }
    .reset-url { margin-top: 8px; }
    .reset-url a { color: #166534; }
    .field { margin-bottom: 18px; }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
    label { display: block; font-size: 13px; font-weight: 600; color: #374151; margin-bottom: 6px; }
    input, select {
      width: 100%; padding: 10px 12px; border: 1px solid #d1d5db;
      border-radius: 6px; font-size: 14px; color: #111827; outline: none;
    }
    input:focus, select:focus { border-color: #1a1a2e; }
    .btn-primary {
      width: 100%; padding: 12px; background: #1a1a2e; color: #fff;
      border: none; border-radius: 6px; font-size: 15px; cursor: pointer;
      margin-top: 8px; transition: background 0.2s;
    }
    .btn-primary:hover:not(:disabled) { background: #2d2d4e; }
    .btn-primary:disabled { opacity: 0.6; cursor: not-allowed; }
    .btn-secondary {
      width: 100%; padding: 12px; background: transparent; color: #1a1a2e;
      border: 1px solid #1a1a2e; border-radius: 6px; font-size: 15px;
      cursor: pointer; margin-top: 8px;
    }
    .btn-secondary:hover { background: #f4f6f8; }
  `],
})
export class CreateUserComponent {
  form: CreateUserForm = {
    uid: '', firstName: '', lastName: '', email: '', role: 'COMMERCIAL'
  };
  loading        = false;
  successMessage = '';
  errorMessage   = '';

  constructor(private auth: AuthService, private router: Router) {}

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
          `User "${this.form.uid}" has been created with role ${this.form.role}.`;
      } else {
        this.errorMessage = await resp.text() || `Error ${resp.status}`;
      }
    } catch {
      this.errorMessage = 'Network error — is the backend running?';
    } finally {
      this.loading = false;
    }
  }

  reset(): void {
    this.successMessage = '';
    this.errorMessage   = '';
    this.form = { uid: '', firstName: '', lastName: '', email: '', role: 'COMMERCIAL' };
  }

  goBack(): void { this.router.navigate(['/dashboard']); }
  logout(): void { this.auth.logout(); }
}
```

---

## Backend — Spring Boot

### `application.yml`

```yaml
server:
  port: 8081

pingdirectory:
  host: 172.18.0.3
  ldap-port: 1636
  rest-port: 443
  base-dn: ou=people,dc=example,dc=com
  groups-dn: ou=groups,dc=example,dc=com
  admin-dn: cn=administrator
  admin-password: 2FederateM0re

spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://localhost:9031
          jwk-set-uri: https://localhost:9031/pf/JWKS

cors:
  allowed-origins: http://localhost:4200
```

---

### `SecurityConfig.java`

```java
package com.poc.puma.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import javax.net.ssl.*;
import java.security.cert.X509Certificate;
import java.util.List;

@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Value("${spring.security.oauth2.resourceserver.jwt.jwk-set-uri}")
    private String jwkSetUri;

    @Value("${cors.allowed-origins}")
    private String allowedOrigins;

    /**
     * RS256 via JWKS — downloads PingFederate public key at startup.
     * No shared secret needed.
     */
    @Bean
    public JwtDecoder jwtDecoder() throws Exception {
        // Trust all SSL certs (POC — PingFederate uses self-signed cert)
        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, new TrustManager[]{
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
                public void checkClientTrusted(X509Certificate[] c, String a) {}
                public void checkServerTrusted(X509Certificate[] c, String a) {}
            }
        }, null);
        HttpsURLConnection.setDefaultSSLSocketFactory(sslContext.getSocketFactory());
        HttpsURLConnection.setDefaultHostnameVerifier((h, s) -> true);

        return NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
    }

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
                oauth2.jwt(jwt -> {
                    try { jwt.decoder(jwtDecoder()); }
                    catch (Exception e) { throw new RuntimeException(e); }
                })
            );
        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of(allowedOrigins));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
```

---

### `CreateUserRequest.java`

```java
package com.poc.puma.model;

public record CreateUserRequest(
    String uid,
    String firstName,
    String lastName,
    String email,
    String role   // "COMMERCIAL" or "MANAGER"
) {}
```

---

### `UserController.java`

```java
package com.poc.puma.controller;

import com.poc.puma.model.CreateUserRequest;
import com.poc.puma.service.UserProvisioningService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/users")
public class UserController {

    @Autowired
    private UserProvisioningService userService;

    @PostMapping
    public ResponseEntity<?> createUser(
            @RequestBody CreateUserRequest req,
            JwtAuthenticationToken token) {

        // Backend enforces MANAGER role — never trust frontend alone
        List<String> groups =
            token.getToken().getClaimAsStringList("isMemberOf");

        boolean isManager = groups != null &&
            groups.stream().anyMatch(g ->
                g.toUpperCase().contains("MANAGER"));

        if (!isManager) {
            return ResponseEntity.status(403)
                .body("Access denied — MANAGER role required.");
        }

        if (!List.of("COMMERCIAL", "MANAGER").contains(req.role())) {
            return ResponseEntity.badRequest()
                .body("Invalid role. Allowed: COMMERCIAL, MANAGER");
        }

        if (req.uid() == null || req.uid().isBlank() ||
            req.email() == null || req.email().isBlank()) {
            return ResponseEntity.badRequest()
                .body("uid and email are required.");
        }

        try {
            userService.createUser(req);
        } catch (Exception e) {
            return ResponseEntity.status(500)
                .body("Provisioning error: " + e.getMessage());
        }

        return ResponseEntity.ok(Map.of(
            "message",       "User " + req.uid() + " created successfully.",
            "role",          req.role(),
            "passwordReset", "https://localhost:9031/ext/pwdreset",
            "instruction",   "The user must initialize their password at the URL above."
        ));
    }
}
```

---

### `UserProvisioningService.java`

```java
package com.poc.puma.service;

import com.poc.puma.model.CreateUserRequest;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.naming.Context;
import javax.naming.NamingException;
import javax.naming.directory.*;
import javax.net.ssl.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.Hashtable;

@Service
public class UserProvisioningService {

    @Value("${pingdirectory.host}")           private String host;
    @Value("${pingdirectory.ldap-port}")      private int ldapPort;
    @Value("${pingdirectory.rest-port}")      private int restPort;
    @Value("${pingdirectory.admin-dn}")       private String adminDn;
    @Value("${pingdirectory.admin-password}") private String adminPwd;

    public void createUser(CreateUserRequest req) throws Exception {
        createViaScim(req);
        addToGroup(req.uid(), req.role());
    }

    // ── SCIM v2 — create user ────────────────────────────────
    private void createViaScim(CreateUserRequest req) throws Exception {
        String url  = "https://" + host + ":" + restPort + "/scim/v2/Users";
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

        HttpClient client = HttpClient.newBuilder()
            .sslContext(trustAllSslContext())
            .build();

        HttpRequest httpReq = HttpRequest.newBuilder()
            .uri(URI.create(url))
            .header("Content-Type", "application/json")
            .header("Authorization", basicAuth(adminDn, adminPwd))
            .POST(HttpRequest.BodyPublishers.ofString(body))
            .build();

        HttpResponse<String> resp =
            client.send(httpReq, HttpResponse.BodyHandlers.ofString());

        if (resp.statusCode() != 201 && resp.statusCode() != 200) {
            throw new RuntimeException(
                "SCIM error " + resp.statusCode() + ": " + resp.body());
        }
    }

    // ── LDAP — add user to group ─────────────────────────────
    private void addToGroup(String uid, String role) throws NamingException {
        String groupDn  = "cn=" + role + ",ou=groups,dc=example,dc=com";
        String memberDn = "uid=" + uid  + ",ou=people,dc=example,dc=com";

        Hashtable<String, String> env = new Hashtable<>();
        env.put(Context.INITIAL_CONTEXT_FACTORY,
            "com.sun.jndi.ldap.LdapCtxFactory");
        env.put(Context.PROVIDER_URL, "ldaps://" + host + ":" + ldapPort);
        env.put(Context.SECURITY_AUTHENTICATION, "simple");
        env.put(Context.SECURITY_PRINCIPAL,   adminDn);
        env.put(Context.SECURITY_CREDENTIALS, adminPwd);

        DirContext ctx = new InitialDirContext(env);
        try {
            ModificationItem[] mods = {
                new ModificationItem(
                    DirContext.ADD_ATTRIBUTE,
                    new BasicAttribute("member", memberDn))
            };
            ctx.modifyAttributes(groupDn, mods);
        } finally {
            ctx.close();
        }
    }

    // ── Helpers ──────────────────────────────────────────────
    private String basicAuth(String user, String pass) {
        return "Basic " + Base64.getEncoder()
            .encodeToString((user + ":" + pass)
                .getBytes(StandardCharsets.UTF_8));
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

## Test Users

| User | Login | Password | Role |
|---|---|---|---|
| Thomas Martin | `thomas.martin` | `Password1234!` | MANAGER |
| Sophie Bernard | `sophie.bernard` | `Password1234!` | COMMERCIAL |

## Password Reset URL

```
https://localhost:9031/ext/pwdreset
```
