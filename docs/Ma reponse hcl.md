# Notation SecD - Réponse HCL AppScan 360 - PSC26 DAST/IAST

Document évalué : HCL - Annexe 03 - Grille_Reponse_Exigences_Fonctionnelles (21.09.2026), onglet E-FONC_1.
Périmètre de l'offre : DAST et IAST sur une plateforme unique (AppScan 360).
Barème : 0 à 4.

Colonne "Couvre" : ce que la réponse couvre réellement, toutes les lignes étant de type COMMUN.
D = DAST, I = IAST, Plateforme = fonction transverse de la console, Flou = réponse hors sujet ou non spécifique.

## 1. Tableau de notation

| Ligne | Exigence (résumé) | EXP | SECD | Couvre | Commentaire SECD |
|---|---|---|---|---|---|
| 7 | Tests interactifs et dynamiques web et API | 4 | 4 | D + I | DAST action-based et IAST, REST et SOAP |
| 8 | Tests de logique métier | 3 | 3 | D | Rejeu de séquences, pas de détection autonome |
| 9 | Tests de configuration et de durcissement | 4 | 3 | Flou | Réponse sur la gouvernance, tests en-têtes/TLS non décrits |
| 10 | Vulnérabilités des middlewares et composants tiers | 4 | 3 | D + SCA | S'appuie sur le SCA, périmètre de licence à clarifier |
| 11 | Espaces segmentés par application ou domaine | 4 | 4 | D + I | Applications et groupes d'actifs, réponse succincte |
| 12 | Découverte et cartographie, 4 modes actif/passif | 2 | 3 | D + I | Découverte API sans spec via Salt Security (tiers) |
| 13 | Méthodes d'authentification pour scan authentifié | 4 | 4 | D | Très complet : OAuth2/OIDC, SAML, MFA, certificats, scripts |
| 14 | Déport d'authentification vers IdP tiers | 4 | 4 | Plateforme | AD et OIDC, compatible Ping |
| 15 | Authentification transparente type SSO | 4 | 4 | Plateforme | SSO OIDC natif |
| 16 | Formats et langages à l'état de l'art IAST/DAST | 4 | 3 | D (+ I ?) | Langages cités plutôt SAST, couverture IAST à préciser |
| 17 | Adhérence aux référentiels (OWASP, CWE, CIS, STIG, NIST, ANSSI) | 4 | 3 | D + I | CIS, STIG, ANSSI, MITRE absents |
| 18 | Cotation CVSS, KEV, CWE, EPSS | 4 | 3 | D + I | CVSS 3.1 seul, CVSS 4.0 prévu, pas de KEV ni EPSS |
| 19 | Métriques d'affichage filtrables | 4 | 4 | D + I | Filtres et tableaux de bord personnalisables |
| 20 | Planification et ordonnancement des scans | 4 | 4 | D | Planification récurrente, CI/CD et API |
| 21 | Lancement manuel ou à la demande | 4 | 4 | D | Lancement manuel, exploration et éditeur de requêtes |
| 22 | Requalification humaine des vulnérabilités | 3 | 4 | D + I | Statuts natifs et commentaires, conforme à l'exigence |
| 23 | Champ de justification lors d'une requalification | 4 | 4 | D + I | Champs de justification configurables |
| 24 | Indicateurs sur les activités de requalification | 4 | 4 | D + I | Indicateurs de requalification annoncés, à démontrer |
| 25 | Génération et export de rapports | 4 | 4 | D + I | PDF, HTML, JSON, CSV, XML, SARIF |
| 26 | Pas de données sensibles métier dans les rapports | 4 | 3 | D + I | Masquage annoncé, à vérifier sur requêtes/réponses |
| 27 | Choix du format d'export | 4 | 4 | D + I | Formats multiples au choix |
| 28 | Rapports lisibles par un humain | 4 | 4 | D + I | Rapports lisibles avec remédiation |
| 29 | Éléments requête/réponse pour rejeu humain | 4 | 4 | D | Requête/réponse fournies, rejeu humain possible |
| 30 | Éléments de correction et remédiation | 4 | 4 | D + I | Remédiation et corrélation DAST/IAST annoncée |
| 31 | Formats exploitables par machine (VOC, RBVM) | 4 | 4 | D + I | SARIF, JSON, XML exploitables par un RBVM |
| 32 | Journalisation administration et utilisation | 4 | 4 | Plateforme | Journal d'audit complet, lecture seule |
| 33 | Journalisation des actions sur les vulnérabilités | 4 | 4 | D + I | Pistes d'audit sur les vulnérabilités |
| 34 | Export des journaux vers collecteurs | 4 | 3 | Plateforme | Export CSV/JSON, pas de flux continu ni Syslog |
| 35 | Format de journaux compatible SIEM | 4 | 3 | Plateforme | Réponse générique, format SIEM non précisé |
| 36 | Pas de données sensibles en clair dans les journaux | 4 | 4 | Plateforme | Masquage des données sensibles dans les journaux |
| 37 | Engagement sur les mises à jour produit | 4 | 4 | Plateforme | Trimestriel, correctifs sécurité sous 72 h |
| 38 | Mises à jour des méthodes de détection, vulnérabilités IA | 3 | 4 | D | Mises à jour quotidiennes, scan LLM et MCP |
| 39 | Solution en propre dans le SI du client | 4 | 4 | Plateforme | On-premise et air-gap |
| 40 | Indicateurs post-scan (succès, erreurs, fiabilité, performance) | 4 | 3 | Surtout SAST | Indicateurs de code source, peu sur DAST/IAST |
| 41 | Adéquation à la réglementation du secteur financier | 4 | 3 | Plateforme | Modèles DORA annoncés, pas de qualification ANSSI |
| 42 | Certifications de robustesse sécurité | 3 | 3 | Plateforme | ISO 27001, FIPS 140-3, pas de Critères Communs |

## 2. Points de vigilance

- **Mélange des briques DAST, IAST, SAST et SCA.** HCL vend une plateforme complète, et plusieurs réponses s'appuient sur des briques hors du périmètre de la consultation. C'est le cas des lignes 10 (SCA), 16 (langages SAST, dont Flutter) et 40 (lignes de code analysées, erreurs de syntaxe : ce sont des métriques SAST). Le contenu exact de la licence proposée est à confirmer.
- **IAST très peu détaillé.** Aucune ligne ne précise les langages supportés par l'agent IAST, ni leurs versions minimales. C'est le point le plus faible de la réponse.
- **Découverte d'API (ligne 12).** La découverte d'API sans spécification repose sur Salt Security, un produit tiers avec sa propre licence. La découverte passive (IAST) et la découverte active web (crawler) sont natives.
- **Affirmations à faire démontrer en POC :**
  - la résolution automatique de CAPTCHA (ligne 13) ;
  - le masquage des données sensibles dans les requêtes et réponses des rapports (ligne 26) ;
  - la corrélation DAST/IAST (ligne 30) ;
  - les indicateurs de requalification (ligne 24) ;
  - le fonctionnement des mises à jour en mode air-gap (ligne 38).
- **FIPS 140-3 (ligne 42).** Il s'agit d'une option de déploiement utilisant des modules cryptographiques validés, pas d'une certification de sécurité du produit.

## 3. Écarts avec la notation EXP, à discuter en consolidation

- **Ligne 22, remontée à 4.** EXP a mis 3 parce que Black Duck permet d'ajouter des statuts. L'exigence demande seulement une requalification humaine, et HCL y répond. Pour que le benchmark reste défendable, chaque éditeur doit être noté par rapport à l'exigence, pas par rapport à un concurrent.
- **Ligne 29, 4 confirmé.** L'exigence parle de rejeu "par un humain". L'absence de rejeu automatisé ne pénalise pas.
- **Ligne 31, 4 confirmé.** L'API est utile pour un RBVM, mais l'exigence porte sur les formats de fichier, et SARIF est un plus. L'API relève de l'annexe technique.
- **Ligne 12, remontée à 3.** Trois modes de découverte sur quatre sont natifs.
- **Ligne 38, remontée à 4.** Mises à jour quotidiennes et prise en charge des vulnérabilités LLM.
- **Lignes 9, 17, 18, 26, 34, 35, 40 et 41, descendues à 3.** Les réponses sont génériques ou incomplètes. Pour les lignes 17, 18 et 41, la note reste cohérente avec celle appliquée à Black Duck sur les mêmes lignes.

## 4. Questions écrites à envoyer à l'éditeur

1. Quels langages et quelles versions sont supportés par l'agent IAST, distinctement du SAST ?
2. Quelles briques (DAST, IAST, SAST, SCA) sont incluses dans l'offre chiffrée ?
3. Salt Security est-il inclus dans l'offre ? Sinon, quelle découverte d'API est native ?
4. Comment se font les mises à jour des règles en mode air-gap, y compris pour le SCA ?
5. Quel est le format natif des journaux d'audit (JSON, CEF, Syslog), et l'export vers le SIEM est-il continu ou manuel ?
6. KEV et EPSS sont-ils disponibles ? À quelle date CVSS 4.0 le sera-t-il ?

## 5. Conclusion

### DAST : oui

C'est le point fort de la réponse. HCL couvre le DAST de façon complète :

- authentification très riche (formulaires, OAuth2/OIDC avec refresh token, SAML, MFA TOTP, certificats client, scripts personnalisés) ;
- REST, SOAP et GraphQL, avec import OpenAPI et Postman ;
- scans planifiés et à la demande, exploration manuelle et éditeur de requêtes ;
- exports SARIF, JSON et XML.

La seule dépendance notable est Salt Security pour la découverte d'API non documentées.

### IAST : à confirmer

HCL propose bien un agent IAST, utilisé pour la découverte passive et la corrélation avec le DAST. Mais la réponse ne donne aucun détail vérifiable : ni langages, ni versions, ni fonctionnement de l'agent. Sur ce volet, la réponse est nettement moins précise que celle de Black Duck sur Seeker. Rien ne permet de conclure à une faiblesse, mais rien ne permet non plus de valider la couverture du parc.

### Outil unique : candidat sérieux, sous réserve

HCL est le seul des deux éditeurs analysés à couvrir DAST et IAST dans une même plateforme. C'est ce qui correspond à l'objectif d'un outil unique :

- le DAST apporte la vue attaquant, la découverte de surface et les applications non instrumentables ;
- l'IAST apporte la précision au niveau du code ;
- la corrélation des deux est annoncée nativement, ce que Black Duck ne peut pas offrir sans DAST.

Comparaison rapide avec Black Duck :

| Critère | Black Duck (Seeker) | HCL AppScan 360 |
|---|---|---|
| DAST | Non proposé | Complet |
| IAST | Très bien documenté | Peu documenté, à vérifier |
| Corrélation DAST/IAST | Impossible | Annoncée |
| SSO plateforme | SAML seulement | OIDC natif |
| Outil unique | Non en l'état | Oui, sous réserve IAST |

### Recommandation

1. Retenir HCL comme candidat principal pour l'objectif d'outil unique, après réponse aux questions écrites de la section 4.
2. Faire porter le POC en priorité sur l'IAST HCL : couverture des langages du parc, qualité de détection, surcoût CPU, mémoire et latence, et corrélation effective avec le DAST.
3. Vérifier que l'offre chiffrée n'inclut pas de briques inutiles (SAST, SCA) ou, à l'inverse, qu'elle ne suppose pas des briques non chiffrées (Salt Security).
4. Compléter la notation par l'Annexe 02 (exigences techniques) de HCL avant la conclusion définitive.
