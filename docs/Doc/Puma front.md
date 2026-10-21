# PUMA, frontend

Portail d'administration PUMA en Angular 20 (composants standalone).

## Prérequis

- Node.js 20.19 ou plus (version requise par Angular 20)
- npm
- Le backend PUMA démarré (port 8081)
- PingFederate démarré, avec le client OAuth `puma-portal`

## 1. Installer les dépendances

```bash
npm ci
```

## 2. Vérifier la configuration

- `src/app/core/puma-api-v2.ts` : `API_BASE_V2` doit pointer vers le backend PUMA (`http://localhost:8081/api`)
- la configuration OAuth : `client_id` `puma-portal`, et l'URL de redirection doit être exactement celle déclarée sur le client dans PingFederate

## 3. Démarrer

```bash
npx ng serve
```

L'application est disponible sur `http://localhost:4200`. À l'ouverture, l'utilisateur est redirigé vers PingFederate pour se connecter, puis choisit son noeud de contexte.

## 4. Vérifier

Se connecter avec un compte manager, choisir un noeud, puis vérifier les pages Users, Roles et la création d'utilisateur.
