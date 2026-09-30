# Notation SecD - Réponse HCL AppScan 360 - Annexe 02 (exigences techniques)

Document évalué : HCL - Annexe 02 - Grille_Reponse_Exigences_Techniques (21.09.2026), onglet E-TECHNIQUE.
Lignes couvertes : E-TECHNIQUE_1 à 28.
Barème : 0 à 4. La colonne "Type" reprend la colonne B de la grille (DAST, IAST ou COMMUN).

## 1. Tableau de notation

| Réf | Type | ARCHI | EXP | CICD | SECD | Commentaire SECD |
|---|---|---|---|---|---|---|
| 1 | DAST | 4 | 3 | | 3 | Web et API avec spec OK. Shadow API via licence distincte Salt. HAR et AsyncAPI non cités |
| 2 | DAST | 4 | 4 | | 4 | Scan dans GitLab, blocage par seuil, SARIF vers le Security Dashboard |
| 3 | IAST | 4 | 4 | 4 | 3 | Reprise mot pour mot de l'exigence, versions à vérifier en POC (Go, PHP) |
| 4 | COMMUN | 4 | 4 | | 3 | En-têtes et TLS OK, réponse mélangée avec la sécurité du produit lui-même |
| 5 | COMMUN | 4 | 2 | 4 | 3 | Formats OK, différentiel par filtre "nouveaux problèmes", pas de rapport natif |
| 6 | COMMUN | 4 | 4 | | 4 | Journalisation complète, lien pipeline GitLab (branche, SHA, environnement) |
| 7 | COMMUN | 4 | 4 | | 4 | On-premise sur Kubernetes. OpenShift non cité, SQL Server requis |
| 8 | COMMUN | 4 | 2 | 3 | 3 | OIDC et SAML natifs. Mapping des groupes IdP à scripter via API |
| 9 | DAST | 4 | 4 | | 4 | Import OpenAPI/Swagger et test autonome des endpoints |
| 10 | COMMUN | 4 | 4 | | 3 | Actif/passif avec RPO 4 h, RTO non chiffré. Pas d'abaques par volume ni IOPS |
| 11 | COMMUN | 4 | 4 | | 4 | Mises à jour hors ligne et via proxy en liste blanche |
| 12 | COMMUN | 4 | | | 3 | Scanners DAST (Presence) bien décrits, agent IAST non décrit |
| 13 | COMMUN | 4 | 3 | | 3 | REST et SOAP OK. gRPC prévu T1 2027, pas d'AsyncAPI, MQTT, AMQP |
| 14 | DAST | 4 | 4 | | 4 | Renouvellement automatique et silencieux des jetons |
| 15 | DAST | 1 | 2 | | 2 | Pas d'arrêt sur x % d'erreurs, seulement des états d'erreur configurables |
| 16 | COMMUN | 4 | 4 | | 4 | RBAC, politiques réservées aux rôles sécurité et admin |
| 17 | COMMUN | 2 | 2 | 2 | 2 | Pas de connecteur coffre-fort natif, développement en prestation |
| 18 | COMMUN | 4 | 4 | | 2 | Aucun chiffre fourni, mesure renvoyée au POC |
| 19 | DAST | 4 | 4 | 3 | 4 | Scanners distribués, scans parallèles. Mode bloquant du pipeline à préciser |
| 20 | IAST | 4 | 4 | | 4 | Fichier et ligne exacte, source-sink, analyse du compilé Java et .NET |
| 21 | DAST | 4 | 4 | 3 | 3 | GitLab, Jenkins, Azure DevOps, GitHub, CLI. Mode XL Release à préciser |
| 22 | COMMUN | 4 | | | 2 | Abaques non fournis, engagement à les produire pendant le POC |
| 23 | COMMUN | 4 | 4 | | 2 | Inaltérabilité non native, UTC et temps réel renvoyés à la conception |
| 24 | DAST | 4 | 4 | | 4 | Basic, clés API, OAuth2 |
| 25 | COMMUN | 4 | 4 | 4 | 4 | API REST documentée, Swagger disponible |
| 26 | COMMUN | 4 | 4 | 4 | 4 | RBAC, séparation admin pipelines et équipes consommatrices |
| 27 | COMMUN | 4 | 4 | | 2 | Matrice de flux non fournie, renvoyée à la conception |
| 28 | COMMUN | 4 | 4 | | 4 | Projets isolés par application, aucune donnée partagée |

## 2. Réponses aux commentaires des autres évaluateurs

- **Réf 1 (EXP : "l'option API est-elle dans l'offre ?").** HCL le confirme : la découverte des API non documentées nécessite une licence distincte, "AppScan API Security", basée sur Salt Security. Si cette licence n'est pas chiffrée dans l'offre, elle n'est pas incluse. La même question conditionne la note de l'exigence fonctionnelle E-FONC-GENERALES-06 (ligne Excel 12).
- **Réf 5 (EXP : pas de référence au rapport différentiel).** HCL mentionne un "filtrage des nouveaux problèmes détectés". Ça permet d'obtenir une vue différentielle, mais ce n'est pas le rapport différentiel natif demandé. D'où 3 plutôt que 2.
- **Réf 7 (CICD : compatibilité OpenShift ?).** HCL cite Kubernetes, RHEL et Ubuntu Pro, sans mentionner OpenShift. La question est légitime et doit être posée. À noter aussi : la base Microsoft SQL Server est à la charge de LBP (licence, exploitation, compétences DBA).
- **Réf 8 (EXP : expliquer la phrase de l'éditeur).** Le SSO fonctionne en OIDC et en SAML. En revanche, AppScan ne sait pas lire automatiquement les groupes de l'annuaire pour en déduire les rôles. Il faut appeler l'endpoint "User Roles" de leur API pour tenir la correspondance à jour, donc écrire et maintenir un script de synchronisation. D'où 3 : c'est mieux que Black Duck (qui n'a pas OIDC), mais le mapping sur les groupes d'annuaire n'est pas natif.
- **Réf 19 (CICD : le scan est-il bloquant, comment le pipeline connaît la fin du scan ?).** C'est une vraie question, car un scan DAST peut durer plusieurs heures. Il faut savoir si le plugin GitLab attend la fin du scan (job bloquant) ou s'il lance le scan puis récupère les résultats plus tard (polling ou webhook). Ça ne change pas la note de l'exigence, qui porte sur la parallélisation, mais c'est à clarifier avec HCL.
- **Réf 20 (EXP : la dernière phrase est-elle un plus ?).** Oui. "Analyse des résultats de compilation Java et .NET" signifie que la localisation fonctionne sur le code compilé (bytecode Java, assemblies .NET) même sans le code source. C'est exactement la seconde partie de l'exigence ("Bytecode pour les langages managés"). La note de 4 est justifiée.
- **Réf 21 (CICD : helper GitLab, plugin XL Release ou simple appel API/CLI ?).** HCL cite GitLab, un CLI et une prise en charge "spécifique" de XL Release, sans préciser s'il existe un vrai plugin XL Release. 3 en attendant la réponse, 4 si un plugin existe.
- **Réf 22 (EXP : pas de références, mais engagement à les fournir, "soit 0 soit 4").** On note ce qui est fourni aujourd'hui. Les abaques ne sont pas dans la réponse, mais l'éditeur s'engage à les produire pendant le POC sur des applications représentatives de LBP. D'où 2 : ni 0, car l'engagement est écrit et opposable, ni 4, car rien n'est livré. La note pourra être révisée après le POC.

## 3. Points de vigilance

- **IAST, contradiction entre les deux annexes.** Dans l'Annexe 02 (réf 3), HCL recopie mot pour mot les langages et versions de l'exigence : Java 8+, Python 3.8+, Node.js 16+, .NET Core 6+, Go, PHP. Dans l'Annexe 03 (E-FONC-GENERALES-44), il donne une liste de langages SAST (Cobol, Apex, Flutter). Une réponse qui reprend exactement l'exigence n'apporte aucune preuve. En revanche, elle engage l'éditeur par écrit, et c'est un levier contractuel. Le support de Go et PHP par l'agent IAST est à vérifier en priorité.
- **Agent IAST jamais décrit.** La réf 12 décrit les scanners DAST (AppScan Presence), pas le déploiement de l'agent IAST : injection en Kubernetes, conteneur, VM, IIS, flux réseau vers le serveur.
- **Beaucoup d'éléments renvoyés au POC ou à la conception** : abaques de temps de scan (22), consommation CPU, mémoire et latence (18), matrice de flux (27), UTC, rétention et export temps réel des journaux (23). Il faut en faire des livrables datés avant le POC, sinon l'évaluation reposera sur des promesses.
- **Coffre-fort de secrets (17).** Le point est plus sensible chez HCL que chez Black Duck, parce que le DAST a besoin d'identifiants de test pour les scans authentifiés. Sans connecteur natif, ces identifiants passeront par des scripts CI ou par un développement en prestation.
- **Couverture "à 100 %" de l'OWASP Top 10 (2).** C'est une affirmation marketing à relativiser. Certaines catégories, comme les défauts de conception, ne sont pas détectables par un scanner.
- **Réf 4.** La réponse décrit en partie la sécurité propre de la plateforme (mots de passe de 14 caractères, MFA) au lieu des contrôles faits sur les applications scannées. Les tests d'en-têtes HTTP et de TLS sont bien couverts.

## 4. Questions à envoyer à HCL

1. La licence AppScan API Security (Salt Security) est-elle incluse dans l'offre chiffrée ? Est-elle déployable intégralement on-premise ?
2. Pouvez-vous confirmer, avec la documentation de référence, le support par l'agent IAST de Java 8+, Python 3.8+, Node.js 16+, .NET Core 6+, Go et PHP ?
3. Comment l'agent IAST est-il déployé (Kubernetes, OpenShift, conteneur, VM, IIS) et quels flux réseau utilise-t-il ?
4. AppScan 360 est-il supporté sur OpenShift ?
5. Le plugin GitLab attend-il la fin du scan DAST, ou fonctionne-t-il en asynchrone ? Existe-t-il un plugin XL Release ?
6. Pouvez-vous fournir avant le POC la matrice de flux, les abaques de temps de scan et de dimensionnement, et le protocole de mesure de performance IAST ?
7. Quel est le RTO garanti en architecture actif/passif ?

## 5. Conclusion globale HCL (Annexes 02 et 03)

### DAST : oui, solide

La réponse technique confirme l'annexe fonctionnelle. Découverte web et API, intégration GitLab avec SARIF et blocage du pipeline, renouvellement silencieux des jetons, authentifications standard, scanners distribués déployables en interne. Les seules faiblesses DAST sont l'arrêt sur taux d'erreur (15), l'absence de connecteur coffre-fort (17) et la découverte d'API non documentées sous licence séparée (1).

### IAST : engagé par écrit, pas démontré

HCL s'engage par écrit sur les langages et versions exigés, et sa réponse sur la traçabilité source-sink est crédible. Mais l'agent IAST n'est jamais décrit techniquement, et les deux annexes se contredisent sur les langages. L'IAST HCL reste la principale inconnue du dossier.

### Outil unique : HCL est le seul candidat viable des deux, sous condition

| Critère | Black Duck (Seeker) | HCL AppScan 360 |
|---|---|---|
| DAST | Non proposé | Complet |
| IAST | Très bien documenté, versions Node.js et Python plus élevées | Engagé par écrit, non démontré |
| Intégration GitLab | API REST uniquement | Plugin et SARIF |
| SSO plateforme | SAML seulement | OIDC et SAML |
| Précision de la réponse | Chiffres et ports fournis | Nombreux renvois au POC |
| Outil unique | Non | Oui, si l'IAST est validé |

Black Duck a rendu la réponse la plus précise et la plus honnête, mais il ne couvre pas le DAST. HCL couvre les deux besoins, avec une réponse plus commerciale et plusieurs points repoussés au POC.

### Recommandation

1. Retenir HCL comme candidat principal pour l'objectif d'outil unique.
2. Conditionner l'entrée en POC à la réception des livrables promis (matrice de flux, abaques, protocole de mesure) et aux réponses écrites sur l'IAST, la licence Salt et OpenShift.
3. Construire le POC HCL autour de l'IAST : vérification des langages et versions du parc (Go et PHP compris), déploiement de l'agent, surcoût CPU, mémoire et latence, puis corrélation avec le DAST.
4. Si l'IAST HCL ne tient pas ses engagements en POC, la question du couple HCL (DAST) et Black Duck (IAST) se posera. L'objectif d'outil unique devra alors être revu avec le client.
