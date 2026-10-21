# Application partenaire (Rataweb), frontend

Interface Angular de l'application partenaire Rataweb.

## Prérequis

- Node.js 20.19 ou plus et npm
- Le backend Rataweb démarré
- PingFederate démarré, avec le client OAuth `rataweb-portal`

## 1. Installer les dépendances

```bash
npm ci
```

## 2. Vérifier la configuration

- l'URL du backend Rataweb dans la configuration de l'application
- la configuration OAuth : `client_id` `rataweb-portal`, et l'URL de redirection doit être exactement celle déclarée sur le client dans PingFederate

## 3. Démarrer

```bash
npx ng serve --port 4201
```

Le port 4201 évite le conflit avec le frontend PUMA, qui utilise le 4200. Si un autre port est déclaré dans l'URL de redirection PingFederate, utiliser celui-là.

## 4. Vérifier

Se connecter, choisir un noeud, ouvrir la liste des contrats, puis tester l'approbation avec un compte conseiller (refus) et un compte superviseur (accepté sous 20 000 euros).
