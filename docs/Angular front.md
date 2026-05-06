async verifySession(): Promise<Record<string, any> | null> {
  const token = this.getToken();
  if (!token) return null;

  try {
    const resp = await fetch('http://localhost:9032/idp/userinfo.openid', {
      method: 'GET',
      headers: { 'Authorization': 'Bearer ' + token },
    });
    if (!resp.ok) return null;
    return await resp.json();
  } catch {
    return null;
  }
}


proxy.conf.json
{
  "/as": {
    "target": "http://localhost:9032",
    "secure": false,
    "changeOrigin": true
  },
  "/idp": {
    "target": "http://localhost:9032",
    "secure": false,
    "changeOrigin": true
  }
}



# Banking Angular POC — PAR + RAR

## Structure du projet

```
src/app/
├── core/
│   ├── auth.config.ts
│   ├── auth.service.ts
│   ├── transfer.service.ts
│   └── log.service.ts
├── features/
│   ├── callback/
│   │   └── callback.component.ts
│   ├── virement/
│   │   ├── virement.component.ts
│   │   ├── virement.component.html
│   │   └── virement.component.css
│   └── historique/
│       ├── historique.component.ts
│       ├── historique.component.html
│       └── historique.component.css
├── app.component.ts
├── app.component.html
├── app.component.css
├── app.routes.ts
└── app.config.ts
```

---

## Création du projet

```bash
npm install -g @angular/cli
ng new banking-app --standalone --routing=true --style=css
cd banking-app
mkdir -p src/app/core src/app/features/virement src/app/features/historique src/app/features/callback
ng serve
```

---

## `src/index.html` — ajouter dans `<head>`

```html
<style>
  body { margin: 0; background: #f5f5f5; }
</style>
```

---

## `src/app/app.config.ts`

```typescript
import { ApplicationConfig } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';
import { routes } from './app.routes';

export const appConfig: ApplicationConfig = {
  providers: [
    provideRouter(routes),
    provideHttpClient(),
  ],
};
```

---

## `src/app/app.routes.ts`

```typescript
import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: 'virement', pathMatch: 'full' },
  {
    path: 'virement',
    loadComponent: () =>
      import('./features/virement/virement.component').then(m => m.VirementComponent),
  },
  {
    path: 'historique',
    loadComponent: () =>
      import('./features/historique/historique.component').then(m => m.HistoriqueComponent),
  },
  {
    path: 'callback',
    loadComponent: () =>
      import('./features/callback/callback.component').then(m => m.CallbackComponent),
  },
];
```

---

## `src/app/app.component.ts`

```typescript
import { Component } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive],
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.css'],
})
export class AppComponent {}
```

---

## `src/app/app.component.html`

```html
<nav>
  <span class="brand">Banking POC</span>
  <div>
    <a routerLink="/virement"   routerLinkActive="active">Virement</a>
    <a routerLink="/historique" routerLinkActive="active">Historique</a>
  </div>
</nav>

<div class="main">
  <router-outlet />
</div>
```

---

## `src/app/app.component.css`

```css
* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: monospace;
  background: #f5f5f5;
  color: #222;
}

nav {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 1.5rem;
  height: 50px;
  background: #fff;
  border-bottom: 1px solid #ddd;
}

.brand {
  font-size: .9rem;
  font-weight: bold;
  text-transform: uppercase;
  letter-spacing: .1em;
}

nav a {
  color: #555;
  text-decoration: none;
  margin-left: 1.5rem;
  font-size: .9rem;
}

nav a.active { color: #000; font-weight: bold; }

.main {
  max-width: 860px;
  margin: 2rem auto;
  padding: 0 1rem;
}
```

---

## `src/app/core/auth.config.ts`

```typescript
// Constantes OAuth2 / PingFederate - centralisees ici
export const AUTH_CONFIG = {
  PF:        'https://localhost:9031',
  PROXY:     'http://localhost:9032',
  CLIENT:    'banking-spa',
  REDIRECT:  'http://localhost:4200',
  SCOPE:     'openid payment:read banking_transfert',
  VERIFIER:  'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
  CHALLENGE: 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
};
```

---

## `src/app/core/auth.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AUTH_CONFIG } from './auth.config';

export interface TokenData {
  access_token:  string;
  id_token:      string;
  refresh_token: string;
  expires_in:    number;
}

@Injectable({ providedIn: 'root' })
export class AuthService {

  // Decode un JWT et retourne le payload
  decodeJwt(token: string): Record<string, any> | null {
    try {
      const payload = token.split('.')[1];
      return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
    } catch {
      return null;
    }
  }

  isTokenExpired(): boolean {
    const expiry = sessionStorage.getItem('token_expiry');
    if (!expiry) return true;
    return Date.now() > parseInt(expiry);
  }

  saveToken(data: TokenData): void {
    const lastRar = sessionStorage.getItem('last_rar') || '{}';
    sessionStorage.setItem('access_token',   data.access_token  || '');
    sessionStorage.setItem('id_token',       data.id_token      || '');
    sessionStorage.setItem('refresh_token',  data.refresh_token || '');
    sessionStorage.setItem('token_expiry',   String(Date.now() + ((data.expires_in || 300) * 1000)));
    sessionStorage.setItem('consent_stored', lastRar);
  }

  getToken():   string | null { return sessionStorage.getItem('access_token');  }
  getIdToken(): string | null { return sessionStorage.getItem('id_token');      }
  getConsent(): string | null { return sessionStorage.getItem('consent_stored'); }

  clearSession(): void {
    sessionStorage.clear();
  }

  // Echange le code authorization contre un token
  async exchangeCode(code: string): Promise<TokenData> {
    const body = new URLSearchParams({
      grant_type:    'authorization_code',
      client_id:     AUTH_CONFIG.CLIENT,
      code,
      redirect_uri:  AUTH_CONFIG.REDIRECT,
      code_verifier: AUTH_CONFIG.VERIFIER,
    });

    const resp = await fetch(AUTH_CONFIG.PROXY + '/as/token.oauth2', {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    body.toString(),
    });

    return resp.json();
  }

  // Appel userinfo pour verifier que la session Ping est encore active
  async verifySession(): Promise<Record<string, any> | null> {
    const token = this.getToken();
    if (!token) return null;

    const resp = await fetch(AUTH_CONFIG.PROXY + '/idp/userinfo.openid', {
      headers: { 'Authorization': 'Bearer ' + token },
    });

    if (resp.status === 401) return null;
    return resp.json();
  }

  // Construit l'URL pour le prompt=none (test session SSO sans interaction)
  buildSilentUrl(): string {
    const params = new URLSearchParams({
      client_id:             AUTH_CONFIG.CLIENT,
      response_type:         'code',
      redirect_uri:          AUTH_CONFIG.REDIRECT,
      scope:                 AUTH_CONFIG.SCOPE,
      code_challenge:        AUTH_CONFIG.CHALLENGE,
      code_challenge_method: 'S256',
      prompt:                'none',
      state:                 Math.random().toString(36).substring(2),
    });
    return AUTH_CONFIG.PF + '/as/authorization.oauth2?' + params.toString();
  }

  // Logout SLO Ping
  logout(): void {
    const idToken = this.getIdToken();
    this.clearSession();
    if (idToken) {
      const url = AUTH_CONFIG.PF + '/idp/startSLO.ping?id_token_hint=' + idToken
        + '&post_logout_redirect_uri=' + encodeURIComponent(AUTH_CONFIG.REDIRECT);
      window.location.href = url;
    }
  }
}
```

---

## `src/app/core/transfer.service.ts`

```typescript
import { Injectable } from '@angular/core';
import { AUTH_CONFIG } from './auth.config';

export interface TransferPayload {
  iban:     string;
  amount:   number;
  currency: string;
  label:    string;
}

@Injectable({ providedIn: 'root' })
export class TransferService {

  // Construit le JSON RAR pour authorization_details
  buildRar(payload: TransferPayload): string {
    return JSON.stringify([{
      type:     'bankingTransfert',
      iban:     payload.iban,
      amount:   payload.amount,
      currency: payload.currency,
      label:    payload.label,
    }]);
  }

  // Envoie la requete PAR puis redirige vers Ping pour consentement
  async initierVirement(payload: TransferPayload): Promise<void> {
    const rarValue = this.buildRar(payload);

    const body = new URLSearchParams({
      client_id:             AUTH_CONFIG.CLIENT,
      response_type:         'code',
      redirect_uri:          AUTH_CONFIG.REDIRECT,
      scope:                 AUTH_CONFIG.SCOPE,
      code_challenge:        AUTH_CONFIG.CHALLENGE,
      code_challenge_method: 'S256',
      authorization_details: rarValue,
    });

    const resp = await fetch(AUTH_CONFIG.PROXY + '/as/par.oauth2', {
      method:  'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body:    body.toString(),
    });

    const data = await resp.json();

    // Sauvegarde le RAR avant la redirection pour l'afficher apres retour
    sessionStorage.setItem('last_rar', rarValue);

    window.location.href = AUTH_CONFIG.PF + '/as/authorization.oauth2?client_id='
      + AUTH_CONFIG.CLIENT + '&request_uri=' + encodeURIComponent(data.request_uri);
  }
}
```

---

## `src/app/core/log.service.ts`

```typescript
import { Injectable, signal } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class LogService {
  // Signal reactif - les composants voient les nouveaux logs automatiquement
  entries = signal<string[]>([]);

  add(msg: string): void {
    const t = new Date().toLocaleTimeString();
    this.entries.update(prev => ['[' + t + '] ' + msg, ...prev]);
  }

  clear(): void {
    this.entries.set([]);
  }
}
```

---

## `src/app/features/callback/callback.component.ts`

```typescript
import { Component, OnInit } from '@angular/core';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';
import { LogService } from '../../core/log.service';

@Component({
  selector: 'app-callback',
  standalone: true,
  template: `<p style="padding:2rem;font-family:monospace;color:#888">Traitement du callback...</p>`,
})
export class CallbackComponent implements OnInit {

  constructor(
    private auth:   AuthService,
    private log:    LogService,
    private router: Router,
  ) {}

  async ngOnInit() {
    const params = new URLSearchParams(window.location.search);
    const code   = params.get('code');
    const error  = params.get('error');

    if (error) {
      this.log.add('Erreur callback : ' + error + ' - ' + (params.get('error_description') || ''));
      this.router.navigate(['/virement']);
      return;
    }

    if (code) {
      this.log.add('Code recu - echange token...');
      try {
        const data = await this.auth.exchangeCode(code);
        this.auth.saveToken(data);
        this.log.add('Token exchange OK');
      } catch (e) {
        this.log.add('Erreur token exchange: ' + e);
      }
      // Enleve le ?code= de l'URL
      window.history.replaceState({}, '', '/virement');
      this.router.navigate(['/virement']);
    }
  }
}
```

---

## `src/app/features/virement/virement.component.ts`

```typescript
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import { TransferService, TransferPayload } from '../../core/transfer.service';
import { LogService } from '../../core/log.service';

@Component({
  selector: 'app-virement',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './virement.component.html',
  styleUrls: ['./virement.component.css'],
})
export class VirementComponent {

  form: TransferPayload = {
    iban:     'FR7630004000031234567890143',
    amount:   15000,
    currency: 'EUR',
    label:    'loyer',
  };

  loading = false;

  get token()          { return this.auth.getToken(); }
  get idToken()        { return this.auth.getIdToken(); }
  get consent()        { return this.auth.getConsent(); }
  get tokenExpired()   { return this.auth.isTokenExpired(); }
  get logs()           { return this.logService.entries(); }

  get tokenDecoded() {
    const t = this.token;
    return t ? this.auth.decodeJwt(t) : null;
  }

  get idTokenDecoded() {
    const t = this.idToken;
    return t ? this.auth.decodeJwt(t) : null;
  }

  constructor(
    private auth:        AuthService,
    private transfer:    TransferService,
    private logService:  LogService,
  ) {}

  async verifierSession() {
    this.logService.add('Appel /userinfo...');
    const data = await this.auth.verifySession();
    if (data) {
      this.logService.add('Session active : ' + JSON.stringify(data));
    } else {
      this.logService.add('Session expiree ou pas de token');
    }
  }

  faireRequeteSilencieuse() {
    this.logService.add('Test prompt=none...');
    const silentUrl = this.auth.buildSilentUrl();

    let iframe = document.getElementById('silent-iframe') as HTMLIFrameElement;
    if (!iframe) {
      iframe = document.createElement('iframe');
      iframe.id = 'silent-iframe';
      iframe.style.display = 'none';
      document.body.appendChild(iframe);
    }

    iframe.onload = () => {
      try {
        const iUrl = new URL(iframe.contentWindow!.location.href);
        const code = iUrl.searchParams.get('code');
        const err  = iUrl.searchParams.get('error');

        if (code)                        this.logService.add('prompt=none OK - session SSO active');
        else if (err === 'login_required')   this.logService.add('prompt=none - session expiree');
        else if (err === 'consent_required') this.logService.add('prompt=none - consentement requis');
        else                             this.logService.add('prompt=none - reponse : ' + (err || 'inconnue'));
      } catch {
        this.logService.add('prompt=none - cross-origin bloque (normal)');
      }
    };

    iframe.src = silentUrl;
  }

  deconnecter() {
    this.logService.add('Deconnexion...');
    this.auth.logout();
  }

  async initier() {
    this.loading = true;
    this.logService.add('Initiation PAR + RAR...');
    try {
      await this.transfer.initierVirement(this.form);
    } catch (e) {
      this.logService.add('Erreur PAR: ' + e);
      this.loading = false;
    }
  }

  // Rejouer le meme virement - Ping ne redemande pas le consentement si memorise
  initierSansConsentement() {
    this.logService.add('Rejouer meme virement...');
    this.initier();
  }

  json(obj: any): string {
    return JSON.stringify(obj, null, 2);
  }
}
```

---

## `src/app/features/virement/virement.component.html`

```html
<div class="page">

  <!-- SESSION -->
  <div class="card">
    <h2>Etat Session et Consentement</h2>

    <div class="status-row">
      <div class="status-item">
        <span class="status-label">Authentification</span>
        <span class="badge" [ngClass]="{
          'badge-green': idTokenDecoded,
          'badge-red':  !idTokenDecoded
        }">
          {{ idTokenDecoded
            ? 'Authentifie (' + (idTokenDecoded['sub'] || idTokenDecoded['uid'] || 'N/A') + ')'
            : 'Non authentifie' }}
        </span>
      </div>

      <div class="status-item">
        <span class="status-label">Token</span>
        <span class="badge" [ngClass]="{
          'badge-green':  token && !tokenExpired,
          'badge-orange': token && tokenExpired,
          'badge-red':   !token
        }">
          {{ !token ? 'Absent' : tokenExpired ? 'Expire' : 'Valide' }}
        </span>
      </div>

      <div class="status-item">
        <span class="status-label">Consentement</span>
        <span class="badge" [ngClass]="{
          'badge-green': consent && consent !== '{}',
          'badge-red':  !consent || consent === '{}'
        }">
          {{ (consent && consent !== '{}') ? 'Memorise' : 'Aucun' }}
        </span>
      </div>
    </div>

    <div class="btn-row">
      <button (click)="verifierSession()">Verifier session</button>
      <button (click)="faireRequeteSilencieuse()">prompt=none</button>
      <button class="danger" (click)="deconnecter()">Deconnecter</button>
    </div>

    <div *ngIf="token">
      <label>Access Token</label>
      <textarea readonly rows="3">{{ token }}</textarea>
    </div>

    <div *ngIf="tokenDecoded">
      <label>Token decode (payload)</label>
      <textarea readonly rows="6">{{ json(tokenDecoded) }}</textarea>
    </div>

    <div *ngIf="consent && consent !== '{}'">
      <label>Consentement RAR stocke</label>
      <textarea readonly rows="4">{{ consent }}</textarea>
    </div>

    <div *ngIf="logs.length > 0">
      <label>Log</label>
      <div class="log-box">
        <div class="log-line" *ngFor="let line of logs">{{ line }}</div>
      </div>
    </div>
  </div>

  <!-- VIREMENT -->
  <div class="card">
    <h2>Initier un Virement</h2>

    <label>IBAN destinataire</label>
    <input type="text" [(ngModel)]="form.iban" />

    <div class="field-row">
      <div>
        <label>Montant</label>
        <input type="number" [(ngModel)]="form.amount" min="1" />
      </div>
      <div>
        <label>Devise</label>
        <select [(ngModel)]="form.currency">
          <option>EUR</option>
          <option>USD</option>
          <option>GBP</option>
        </select>
      </div>
    </div>

    <label>Libelle</label>
    <input type="text" [(ngModel)]="form.label" />

    <div class="btn-row">
      <button class="primary" (click)="initier()" [disabled]="loading">
        {{ loading ? 'Envoi...' : 'Initier le virement' }}
      </button>
      <button (click)="initierSansConsentement()">
        Rejouer (consentement deja donne ?)
      </button>
    </div>
  </div>

</div>
```

---

## `src/app/features/virement/virement.component.css`

```css
.card {
  background: #fff;
  border: 1px solid #ddd;
  padding: 1.5rem;
  margin-bottom: 1.5rem;
}

h2 {
  font-size: .85rem;
  text-transform: uppercase;
  color: #888;
  margin-bottom: 1rem;
  padding-bottom: .5rem;
  border-bottom: 1px solid #eee;
}

.status-row { display: flex; gap: 2rem; margin-bottom: 1rem; flex-wrap: wrap; }

.status-item { display: flex; flex-direction: column; gap: .25rem; }

.status-label { font-size: .7rem; color: #999; text-transform: uppercase; }

.badge { font-size: .75rem; padding: .15rem .5rem; border: 1px solid; }
.badge-green  { color: green;  border-color: green;  }
.badge-orange { color: orange; border-color: orange; }
.badge-red    { color: red;    border-color: red;    }

.btn-row { display: flex; gap: .5rem; flex-wrap: wrap; margin-bottom: 1rem; }

button {
  padding: .4rem .9rem;
  font-size: .8rem;
  font-family: monospace;
  cursor: pointer;
  border: 1px solid #aaa;
  background: #fff;
}

button:hover    { background: #f0f0f0; }
button:disabled { opacity: .5; cursor: default; }
button.primary  { background: #0055cc; color: #fff; border-color: #0055cc; }
button.primary:hover { background: #0044aa; }
button.danger   { color: red; border-color: red; }

label {
  display: block;
  font-size: .7rem;
  text-transform: uppercase;
  color: #999;
  margin-bottom: .3rem;
}

input, select, textarea {
  width: 100%;
  padding: .45rem .6rem;
  font-family: monospace;
  font-size: .875rem;
  border: 1px solid #ccc;
  background: #fafafa;
  margin-bottom: .9rem;
}

input:focus, select:focus { outline: none; border-color: #0055cc; }

textarea { resize: vertical; }

.field-row { display: grid; grid-template-columns: 2fr 1fr; gap: 1rem; }

.log-box {
  background: #fafafa;
  border: 1px solid #ddd;
  padding: .6rem;
  max-height: 180px;
  overflow-y: auto;
  font-size: .75rem;
  color: #555;
}

.log-line { padding: .1rem 0; border-bottom: 1px solid #eee; }
```

---

## `src/app/features/historique/historique.component.ts`

```typescript
import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../core/auth.service';

@Component({
  selector: 'app-historique',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './historique.component.html',
  styleUrls: ['./historique.component.css'],
})
export class HistoriqueComponent {

  // 'me' = virements de l'utilisateur connecte, 'all' = tous
  view: 'me' | 'all' = 'me';

  // Donnees mock - a remplacer par appel HTTP vers Spring Boot
  allTransfers = [
    { id: '1', fromIban: 'FR76...001', toIban: 'DE89...002', amount: 1500,  currency: 'EUR', label: 'Loyer',   date: '2026-05-01', status: 'COMPLETED', owner: 'Customer_1'    },
    { id: '2', fromIban: 'FR76...001', toIban: 'GB29...003', amount: 250,   currency: 'EUR', label: 'Facture', date: '2026-05-03', status: 'PENDING',   owner: 'Customer_1'    },
    { id: '3', fromIban: 'FR76...004', toIban: 'FR76...001', amount: 8000,  currency: 'EUR', label: 'Salaire', date: '2026-05-05', status: 'COMPLETED', owner: 'Approbateur_1' },
  ];

  get currentUser(): string {
    const token = this.auth.getIdToken();
    if (!token) return '';
    const decoded = this.auth.decodeJwt(token);
    return decoded ? (decoded['sub'] || decoded['uid'] || '') : '';
  }

  get transfers() {
    if (this.view === 'me') {
      return this.allTransfers.filter(t => t.owner === this.currentUser);
    }
    return this.allTransfers;
  }

  constructor(private auth: AuthService) {}

  switchView(v: 'me' | 'all') { this.view = v; }
}
```

---

## `src/app/features/historique/historique.component.html`

```html
<div class="card">
  <h2>Historique des virements</h2>

  <div class="tabs">
    <button class="tab" [class.active]="view === 'me'"  (click)="switchView('me')">Mes virements</button>
    <button class="tab" [class.active]="view === 'all'" (click)="switchView('all')">Tous les virements</button>
  </div>

  <table *ngIf="transfers.length > 0">
    <thead>
      <tr>
        <th>De</th>
        <th>Vers</th>
        <th>Montant</th>
        <th>Libelle</th>
        <th>Date</th>
        <th>Statut</th>
      </tr>
    </thead>
    <tbody>
      <tr *ngFor="let t of transfers">
        <td>{{ t.fromIban }}</td>
        <td>{{ t.toIban }}</td>
        <td>{{ t.amount | number }} {{ t.currency }}</td>
        <td>{{ t.label }}</td>
        <td>{{ t.date }}</td>
        <td>
          <span class="badge" [ngClass]="{
            'badge-green':  t.status === 'COMPLETED',
            'badge-orange': t.status === 'PENDING',
            'badge-red':    t.status === 'FAILED'
          }">{{ t.status }}</span>
        </td>
      </tr>
    </tbody>
  </table>

  <p class="empty" *ngIf="transfers.length === 0">Aucun virement trouve.</p>
</div>
```

---

## `src/app/features/historique/historique.component.css`

```css
.card {
  background: #fff;
  border: 1px solid #ddd;
  padding: 1.5rem;
}

h2 {
  font-size: .85rem;
  text-transform: uppercase;
  color: #888;
  margin-bottom: 1rem;
  padding-bottom: .5rem;
  border-bottom: 1px solid #eee;
}

.tabs { display: flex; gap: .5rem; margin-bottom: 1rem; }

.tab {
  padding: .35rem .9rem;
  font-size: .8rem;
  font-family: monospace;
  background: #fff;
  border: 1px solid #ccc;
  cursor: pointer;
}

.tab.active { border-color: #0055cc; color: #0055cc; font-weight: bold; }
.tab:hover  { background: #f5f5f5; }

table { width: 100%; border-collapse: collapse; font-size: .82rem; }

th {
  text-align: left;
  padding: .5rem .6rem;
  font-size: .7rem;
  text-transform: uppercase;
  color: #999;
  border-bottom: 1px solid #ddd;
}

td { padding: .55rem .6rem; border-bottom: 1px solid #eee; }

tr:hover td { background: #fafafa; }

.badge { font-size: .7rem; padding: .15rem .4rem; border: 1px solid; }
.badge-green  { color: green;  border-color: green;  }
.badge-orange { color: orange; border-color: orange; }
.badge-red    { color: red;    border-color: red;    }

.empty { color: #999; font-size: .85rem; padding: .75rem 0; }
```





‐------- on init virement




import { OnInit } from '@angular/core';

export class VirementComponent implements OnInit {

  async ngOnInit() {
    const params = new URLSearchParams(window.location.search);
    const code = params.get('code');

    if (code) {
      this.logService.add('Code recu - echange token...');
      try {
        const data = await this.auth.exchangeCode(code);
        this.auth.saveToken(data);
        this.logService.add('Token exchange OK');
        window.history.replaceState({}, '', '/virement');
      } catch (e) {
        this.logService.add('Erreur token exchange: ' + e);
      }
    }
  }
  // ...reste du code
}

