# Notation SecD - Réponse OpenText Fortify (via Atos) - Annexe 02 (exigences techniques)

Document évalué : Atos RFP DAST-IAST 2026 Annexe 02 - Grille_Reponse_Exigences_Techniques, onglet E-TECHNIQUE.
Solution proposée : OpenText Fortify DAST. Pas d'IAST : OpenText indique avoir retiré cette brique de son portefeuille.
Barème : 0 à 4.

## 1. Pondération proposée

| Niveau | Signification | Traitement |
|---|---|---|
| Mandatory | Exigence éliminatoire | Hors barème : conforme (note de 3 ou plus) ou éliminé |
| P0 | Très important | Coefficient 3 |
| P1 | Importance moyenne | Coefficient 2 |
| P2 | Peu important, confort | Coefficient 1 |

Les coefficients sont une proposition, à valider en groupe avant la consolidation. La même pondération doit s'appliquer à tous les éditeurs.

## 2. Tableau de notation OpenText Fortify

"Notes existantes" reprend le contenu actuel de la colonne "Note de 0 à 4". La colonne "Commentaire" de la grille Atos était vide sur toutes les lignes.

| Ligne | Réf | Type | Notes existantes | SECD | Pondération | Commentaire SECD |
|---|---|---|---|---|---|---|
| 7 | E-TECHNIQUE_1 | DAST | Archi : 2 / EXP : 3 | 3 | P0 | Web et API avec spec très complets (HAR, macros, gRPC, Postman). Shadow API limitées au crawl, découverte autonome en roadmap S2 2027. Pas d'AsyncAPI |
| 8 | E-TECHNIQUE_2 | DAST | Archi : 4 / EXP : 4 | 4 | Mandatory | Scan GitLab via fcli, Security Gate intégrée, SARIF vers le Security Dashboard |
| 9 | E-TECHNIQUE_3 | IAST | Archi : 1 | 0 | Mandatory | Pas d'IAST, retiré du portefeuille. Alternatives proposées (corrélation SAST-DAST, FAST, ingestion IAST tiers) qui ne répondent pas à l'exigence |
| 10 | E-TECHNIQUE_4 | COMMUN | Archi : 4 | 4 | P1 | En-têtes HTTP, TLS, authentification, données sensibles, CWE et OWASP |
| 11 | E-TECHNIQUE_5 | COMMUN | Archi : 4 | 4 | P1 | Tous les formats, gabarit avec logo et C2, rapport différentiel natif (New, Reintroduced, Removed) |
| 12 | E-TECHNIQUE_6 | COMMUN | Archi : 4 | 4 | P1 | Journal natif, métadonnées GitLab (branche, SHA, environnement) via fcli, export SIEM |
| 13 | E-TECHNIQUE_7 | COMMUN | Archi : 4 | 4 | Mandatory | Tous les composants on-premise, aucune dépendance SaaS |
| 14 | E-TECHNIQUE_8 | COMMUN | Archi : 4 | 3 | P1 | SAML et synchronisation des groupes LDAP/AD. OIDC non mentionné |
| 15 | E-TECHNIQUE_9 | DAST | Archi : 4 | 4 | P0 | Import autonome OpenAPI 2.x/3.x, WSDL, Postman |
| 16 | E-TECHNIQUE_10 | COMMUN | Archi : 4 | 2 | P1 | HA actif/passif annoncée sans RPO ni RTO. Abaques CPU, RAM, IOPS non fournis |
| 17 | E-TECHNIQUE_11 | COMMUN | Archi : 4 | 4 | P1 | Mise à jour via flux sortant unique en liste blanche ou paquet hors ligne |
| 18 | E-TECHNIQUE_12 | COMMUN | Archi : 4 | 4 | P1 | Ferme de moteurs en réseau interne. Binaires, Docker, Helm, OpenShift supporté |
| 19 | E-TECHNIQUE_13 | COMMUN | Archi : 2 | 3 | P0 | REST et SOAP OK, plus GraphQL, gRPC, WebSocket. Pas d'AsyncAPI, MQTT, AMQP |
| 20 | E-TECHNIQUE_14 | DAST | Archi : 4 | 4 | P0 | Rejeu automatique de la macro de login, scans longs couverts |
| 21 | E-TECHNIQUE_15 | DAST | Archi : 4 | 4 | P2 | Arrêt sur seuil d'erreurs configurable, throttling, durée maximale |
| 22 | E-TECHNIQUE_16 | COMMUN | Archi : 4 | 4 | P0 | Statuts avec justification obligatoire, historique, RBAC sur les politiques |
| 23 | E-TECHNIQUE_17 | COMMUN | Archi : 2 | 2 | P1 | Pas de connecteur coffre-fort natif. HashiCorp Vault en roadmap S2 2026 |
| 24 | E-TECHNIQUE_18 | COMMUN | Archi : 0 | 0 | P0 | Sans objet faute d'IAST. Abaques DAST renvoyés à la volumétrie |
| 25 | E-TECHNIQUE_19 | DAST | Archi : 4 | 4 | Mandatory | Montée en charge horizontale, pas d'agent bloquant, plusieurs moteurs par application |
| 26 | E-TECHNIQUE_20 | IAST | Archi : 1 | 1 | P0 | Pas d'IAST. Ligne de code obtenue par corrélation SAST-DAST, qui suppose une licence SAST |
| 27 | E-TECHNIQUE_21 | DAST | Archi : 4 | 4 | P0 | CLI fcli officielle et API REST, GitLab et XL Release via CLI |
| 28 | E-TECHNIQUE_22 | COMMUN | Archi : 4 | 2 | P2 | Ordres de grandeur promis, non fournis |
| 29 | E-TECHNIQUE_23 | COMMUN | Archi : 4 | 3 | P0 | Audit trail complet avec succès/échec, export JSON et Syslog. Inaltérabilité et UTC non précisés |
| 30 | E-TECHNIQUE_24 | DAST | Archi : 4 | 4 | Mandatory | Basic, clé API (en-tête ou paramètre), OAuth2, formulaires |
| 31 | E-TECHNIQUE_25 | COMMUN | Archi : 4 | 4 | P0 | API REST documentée, fcli open source maintenue par OpenText |
| 32 | E-TECHNIQUE_26 | COMMUN | Archi : 4 | 4 | P1 | RBAC, séparation admin pipelines et consommateurs |
| 33 | E-TECHNIQUE_27 | COMMUN | Archi : 4 | 2 | P1 | Matrice de flux promise, non fournie |
| 34 | E-TECHNIQUE_28 | COMMUN | Archi : 4 | 4 | P1 | Projet isolé par application et version |

### Points marquants de la réponse Fortify

- **Pas d'IAST, et c'est assumé.** OpenText écrit avoir retiré l'IAST de son portefeuille, en jugeant le maintien des agents trop lourd. La réponse est honnête, mais les deux exigences IAST mandatory ou P0 tombent (E-TECHNIQUE_3 et 20), ainsi que la mesure d'overhead (E-TECHNIQUE_18).
- **Le DAST le plus complet des trois offres** sur plusieurs points : arrêt sur seuil d'erreurs (15), rapport différentiel natif (5), OpenShift supporté explicitement (12), export Syslog natif (23), gRPC déjà disponible (13).
- **Ingestion d'IAST tiers (réf 3, point 3).** Fortify peut intégrer dans son tableau de bord les résultats d'un IAST d'un autre éditeur. C'est un argument fort pour un scénario à deux outils.
- **Roadmap à ne pas noter** : découverte autonome des API (S2 2027), détection IDOR/BOLA (S1 2027), connecteur HashiCorp Vault (S2 2026). Le connecteur Vault annoncé pour S2 2026 devrait déjà être disponible ou imminent : à vérifier. Ces engagements peuvent devenir des clauses contractuelles, mais ils ne comptent pas dans la note.
- **Réponse portée par Atos.** La matrice de flux est annoncée "fournie par OpenText/l'intégrateur" : il faut clarifier qui porte la responsabilité du déploiement et du support.
- **Archi à 2 sur E-TECHNIQUE_13.** Les deux protocoles obligatoires (REST, SOAP) sont couverts, et Fortify supporte même gRPC, contrairement à HCL. Je propose 3, à harmoniser avec Archi.

## 3. Synthèse comparative des trois éditeurs (Annexe 02)

### 3.1 Profil des offres

| | Black Duck (Seeker) | HCL AppScan 360 | OpenText Fortify (Atos) |
|---|---|---|---|
| DAST | Non proposé | Oui | Oui |
| IAST | Oui | Oui (à démontrer) | Non, retiré |
| Couverture | IAST seul | DAST et IAST | DAST seul |

### 3.2 Exigences Mandatory (conforme si note de 3 ou plus)

| Ligne | Réf | Exigence | Black Duck | HCL | Fortify |
|---|---|---|---|---|---|
| 8 | E-TECHNIQUE_2 | DAST dans GitLab, blocage, SARIF | 0 Éliminé | 4 | 4 |
| 9 | E-TECHNIQUE_3 | Instrumentation IAST, langages du parc | 3 | 3 (sous réserve POC) | 0 Éliminé |
| 13 | E-TECHNIQUE_7 | On-premise | 4 | 4 | 4 |
| 25 | E-TECHNIQUE_19 | Centaines d'applications en parallèle | 4 | 4 | 4 |
| 30 | E-TECHNIQUE_24 | Protocoles d'authentification DAST | 0 Éliminé | 4 | 4 |

HCL est le seul éditeur à passer toutes les exigences mandatory. Black Duck tombe sur le DAST, Fortify sur l'IAST.

### 3.3 Notes SECD par exigence

| Ligne | Réf | Pondération | Black Duck | HCL | Fortify |
|---|---|---|---|---|---|
| 7 | E-TECHNIQUE_1 | P0 | 0 | 3 | 3 |
| 8 | E-TECHNIQUE_2 | Mandatory | 0 | 4 | 4 |
| 9 | E-TECHNIQUE_3 | Mandatory | 3 | 3 | 0 |
| 10 | E-TECHNIQUE_4 | P1 | 2 | 3 | 4 |
| 11 | E-TECHNIQUE_5 | P1 | 3 | 3 | 4 |
| 12 | E-TECHNIQUE_6 | P1 | 3 | 4 | 4 |
| 13 | E-TECHNIQUE_7 | Mandatory | 4 | 4 | 4 |
| 14 | E-TECHNIQUE_8 | P1 | 3 | 3 | 3 |
| 15 | E-TECHNIQUE_9 | P0 | 0 | 4 | 4 |
| 16 | E-TECHNIQUE_10 | P1 | 3 | 3 | 2 |
| 17 | E-TECHNIQUE_11 | P1 | 4 | 4 | 4 |
| 18 | E-TECHNIQUE_12 | P1 | 4 | 3 | 4 |
| 19 | E-TECHNIQUE_13 | P0 | 2 | 3 | 3 |
| 20 | E-TECHNIQUE_14 | P0 | 0 | 4 | 4 |
| 21 | E-TECHNIQUE_15 | P2 | 0 | 2 | 4 |
| 22 | E-TECHNIQUE_16 | P0 | 4 | 4 | 4 |
| 23 | E-TECHNIQUE_17 | P1 | 3 | 2 | 2 |
| 24 | E-TECHNIQUE_18 | P0 | 2 | 2 | 0 |
| 25 | E-TECHNIQUE_19 | Mandatory | 4 | 4 | 4 |
| 26 | E-TECHNIQUE_20 | P0 | 4 | 4 | 1 |
| 27 | E-TECHNIQUE_21 | P0 | 2 | 3 | 4 |
| 28 | E-TECHNIQUE_22 | P2 | 3 | 2 | 2 |
| 29 | E-TECHNIQUE_23 | P0 | 2 | 2 | 3 |
| 30 | E-TECHNIQUE_24 | Mandatory | 0 | 4 | 4 |
| 31 | E-TECHNIQUE_25 | P0 | 4 | 4 | 4 |
| 32 | E-TECHNIQUE_26 | P1 | 4 | 4 | 4 |
| 33 | E-TECHNIQUE_27 | P1 | 4 | 2 | 2 |
| 34 | E-TECHNIQUE_28 | P1 | 4 | 4 | 4 |

Pour HCL, la note E-TECHNIQUE_21 peut passer à 4 si HCL confirme une intégration XL Release au moins par CLI, comme Fortify.

### 3.4 Score pondéré indicatif (hors Mandatory)

Calcul sur les exigences P0, P1 et P2 avec les coefficients 3, 2 et 1. Le maximum est de 216 points.

| | Black Duck | HCL | Fortify |
|---|---|---|---|
| Points P0 (x3) | 60 | 99 | 90 |
| Points P1 (x2) | 74 | 70 | 74 |
| Points P2 (x1) | 3 | 4 | 6 |
| **Total** | **137 / 216 (63 %)** | **173 / 216 (80 %)** | **170 / 216 (79 %)** |
| Mandatory | Éliminé (DAST) | Tous conformes | Éliminé (IAST) |

À lire avec prudence : Black Duck et Fortify perdent mécaniquement des points sur le moteur qu'ils ne proposent pas. Si le client accepte deux outils, il faudra recalculer par lot (lignes DAST et lignes IAST séparées).

## 4. Conclusion

### Outil unique : HCL est le seul candidat recevable

HCL est le seul éditeur à couvrir DAST et IAST et à passer toutes les exigences mandatory. Son score pondéré est le meilleur, à égalité pratique avec Fortify. Sa réserve principale reste l'IAST, engagé par écrit mais jamais décrit techniquement, et plusieurs livrables renvoyés au POC.

### Si le client accepte deux outils : Fortify (DAST) et Black Duck (IAST)

- **Fortify** a le DAST le plus mature et le mieux documenté : seuil d'erreurs, rapport différentiel natif, OpenShift, Syslog, gRPC.
- **Black Duck** a l'IAST le mieux documenté : versions, déploiement, dimensionnement chiffré.
- **Fortify sait ingérer les résultats d'un IAST tiers** dans son tableau de bord. Les deux outils peuvent donc partager une vue de risque unique, ce qui compense en partie l'absence de corrélation native.

En contrepartie : deux licences, deux plateformes à exploiter, deux intégrations GitLab, et une corrélation DAST/IAST moins fine que dans une plateforme unifiée.

### Recommandation

1. **Valider la pondération en groupe** avant la consolidation, pour que les scores soient défendables auprès des éditeurs.
2. **Lancer le POC HCL en priorité**, centré sur l'IAST, comme décidé.
3. **Garder le scénario Fortify et Black Duck en solution de repli** si l'IAST HCL ne tient pas ses engagements. Dans ce cas, il faudra tester en POC l'ingestion des résultats Seeker dans Fortify.
4. **Envoyer à Atos et OpenText les questions écrites** : disponibilité réelle du connecteur HashiCorp Vault (annoncé S2 2026), support d'OIDC, RPO et RTO en haute disponibilité, rôle exact d'Atos dans le déploiement et le support.
