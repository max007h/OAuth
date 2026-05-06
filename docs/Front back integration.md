# Angular → Spring Boot — Envoyer et Lister Virements

## Ce qui change

- `transfer.service.ts` — ajouter methode POST vers backend
- `virement.component.ts` — appeler backend apres token exchange
- `historique.component.ts` — remplacer mock par appel HTTP reel
- `historique.component.html` — ajouter loading et erreur

---

## `src/app/core/transfer.service.ts`

Ajouter cette methode dans la classe `TransferService` :

```typescript
// Envoie le virement au backend Spring Boot apres avoir obtenu le token
async envoyerVirementBackend(payload: TransferPayload, token: string): Promise<any> {
  const resp = await fetch('http://localhost:8080/api/virements', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ' + token,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      toIban:   payload.iban,
      amount:   payload.amount,
      currency: payload.currency,
      label:    payload.label,
    }),
  });
  return resp.json();
}
```

---

## `src/app/features/virement/virement.component.ts`

Ajouter `OnInit` et modifier `ngOnInit` :

```typescript
import { Component, OnInit } from '@angular/core';
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
export class VirementComponent implements OnInit {

  form: TransferPayload = {
    iban:     'FR7630004000031234567890143',
    amount:   15000,
    currency: 'EUR',
    label:    'loyer',
  };

  loading = false;

  get token()        { return this.auth.getToken(); }
  get idToken()      { return this.auth.getIdToken(); }
  get consent()      { return this.auth.getConsent(); }
  get tokenExpired() { return this.auth.isTokenExpired(); }
  get logs()         { return this.logService.entries(); }

  get tokenDecoded() {
    const t = this.token;
    return t ? this.auth.decodeJwt(t) : null;
  }

  get idTokenDecoded() {
    const t = this.idToken;
    return t ? this.auth.decodeJwt(t) : null;
  }

  constructor(
    private auth:       AuthService,
    private transfer:   TransferService,
    private logService: LogService,
  ) {}

  async ngOnInit() {
    const params = new URLSearchParams(window.location.search);
    const code   = params.get('code');

    if (code) {
      this.logService.add('Code recu - echange token...');
      try {
        const data = await this.auth.exchangeCode(code);
        this.auth.saveToken(data);
        this.logService.add('Token exchange OK');

        // Recupere le RAR sauvegarde avant la redirection Ping
        const rar = sessionStorage.getItem('last_rar');
        if (rar) {
          const rarObj = JSON.parse(rar)[0];
          this.logService.add('Envoi virement au backend...');
          // await - on attend que le backend reponde avant de continuer
          const result = await this.transfer.envoyerVirementBackend(rarObj, data.access_token);
          this.logService.add('Virement backend : ' + JSON.stringify(result));
        }

        // Nettoie l URL - enleve ?code=xxx
        window.history.replaceState({}, '', '/virement');
      } catch (e) {
        this.logService.add('Erreur : ' + e);
      }
    }
  }

  async verifierSession() {
    this.logService.add('Appel /userinfo...');
    const data = await this.auth.verifySession();
    this.logService.add('Resultat : ' + JSON.stringify(data));
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
        else                             this.logService.add('prompt=none : ' + (err || 'inconnue'));
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

## `src/app/features/historique/historique.component.ts`

Remplacer completement le fichier :

```typescript
import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../core/auth.service';

@Component({
  selector: 'app-historique',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './historique.component.html',
  styleUrls: ['./historique.component.css'],
})
export class HistoriqueComponent implements OnInit {

  // 'me' = mes virements, 'all' = tous (APPROVERS seulement)
  view: 'me' | 'all' = 'me';
  transfers: any[] = [];
  loading = false;
  error = '';

  constructor(private auth: AuthService) {}

  async ngOnInit() {
    // Charge les virements au demarrage du composant
    await this.loadTransfers();
  }

  async switchView(v: 'me' | 'all') {
    this.view = v;
    // await - attend que les virements soient charges avant de continuer
    await this.loadTransfers();
  }

  async loadTransfers() {
    const token = this.auth.getToken();
    if (!token) {
      this.error = 'Pas de token - connectez-vous';
      return;
    }

    this.loading = true;
    this.error = '';

    // URL differente selon la vue
    const url = this.view === 'me'
      ? 'http://localhost:8080/api/virements/me'
      : 'http://localhost:8080/api/virements';

    try {
      const resp = await fetch(url, {
        headers: { 'Authorization': 'Bearer ' + token }
      });

      if (resp.status === 401) {
        this.error = 'Token invalide ou expire';
        this.transfers = [];
        return;
      }

      if (resp.status === 403) {
        this.error = 'Acces refuse - role APPROVERS requis';
        this.transfers = [];
        return;
      }

      // await - attend la reponse JSON avant de l afficher
      this.transfers = await resp.json();
    } catch (e) {
      this.error = 'Erreur backend : ' + e;
    } finally {
      this.loading = false;
    }
  }
}
```

---

## `src/app/features/historique/historique.component.html`

Remplacer completement le fichier :

```html
<div class="card">
  <h2>Historique des virements</h2>

  <div class="tabs">
    <button class="tab" [class.active]="view === 'me'"  (click)="switchView('me')">Mes virements</button>
    <button class="tab" [class.active]="view === 'all'" (click)="switchView('all')">Tous (APPROVERS)</button>
  </div>

  <p *ngIf="loading">Chargement...</p>

  <p *ngIf="error" style="color:red">{{ error }}</p>

  <table *ngIf="!loading && transfers.length > 0">
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
        <td>{{ t.amount }} {{ t.currency }}</td>
        <td>{{ t.label }}</td>
        <td>{{ t.createdAt | date:'dd/MM/yyyy HH:mm' }}</td>
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

  <p class="empty" *ngIf="!loading && transfers.length === 0 && !error">
    Aucun virement trouve.
  </p>
</div>
```

---

## Ordre de lancement

```bash
# Terminal 1 - Spring Boot
mvn spring-boot:run

# Terminal 2 - Proxy Python
python3 inject_cors_proxy_pingfederatr.py

# Terminal 3 - Angular
./start.sh
```

---

## Flow complet

```
1. Cliquer "Initier le virement"
2. Angular → PAR+RAR → Ping → page consentement
3. Utilisateur accepte → Ping → redirect avec ?code=xxx
4. Angular echange code → token JWT
5. Angular → POST /api/virements → Spring Boot → H2
6. Log affiche "Virement backend : {id: 1, status: COMPLETED}"
7. Aller sur Historique → GET /api/virements/me → Spring Boot → H2
8. Liste des virements affichee
```
