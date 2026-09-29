# Notation SecD - Réponse HCL AppScan 360 - Annexe 03 (suite)

Document évalué : HCL - Annexe 03 - Grille_Reponse_Exigences_Fonctionnelles (21.09.2026), onglet E-FONC_1.
Lignes couvertes : E-FONC-GENERALES-37 à 53 (lignes Excel 43 à 59).
Suite du fichier Notation_SecD_HCL_AppScan360_Annexe03.md, qui couvre les lignes Excel 7 à 42 (E-FONC-GENERALES-01 à 36).
Barème : 0 à 4.

Colonne "Couvre" : D = DAST, I = IAST, Plateforme = fonction transverse, SAST = réponse portant sur une brique hors périmètre.

## 1. Tableau de notation

| ID | Ligne Excel | Exigence (résumé) | EXP | SECD | Couvre | Commentaire SECD |
|---|---|---|---|---|---|---|
| 37 | 43 | Intégration écosystème (changement, inventaire, agrégateurs, SIEM) | 4 | 4 | Plateforme | Jira, ServiceNow, Azure DevOps, SIEM et API REST |
| 38 | 44 | Tableaux de bord agrégés et KPI | 4 | 4 | D + I | Tableaux de bord exécutifs, dédoublonnage, suivi par rescan |
| 39 | 45 | Détection des équipements filtrants (WAF) | 4 | 4 | D | Détection WAF, scan marqué "filtré", à démontrer |
| 40 | 46 | Abaques de dimensionnement | 4 | 3 | Plateforme | Abaques renvoyés à la documentation jointe, non chiffrés |
| 41 | 47 | Intégration dans des pipelines existants | 4 | 4 | D | Jenkins, Azure DevOps, GitLab, GitHub. IAST non cité |
| 42 | 48 | Intégration dans des pipelines nouvellement créés | 4 | 4 | D | Plugins et API pour nouveaux pipelines |
| 43 | 49 | Résultats JSON accessibles depuis la CI/CD | 4 | 4 | D + I | Résultats JSON exploitables dans le pipeline |
| 44 | 50 | Langages des filières officielles LBP | 4 | 2 | SAST | Liste SAST (Cobol, Apex), langages IAST non précisés |
| 45 | 51 | Lien entre vulnérabilité dynamique et interactive | 4 | 3 | D + I | Corrélation par dédoublonnage annoncée, mécanisme à démontrer |
| 46 | 52 | Blocage automatique du pipeline paramétrable | 4 | 4 | D + I | Politiques de seuil par périmètre et sévérité |
| 47 | 53 | Findings restitués dans le pipeline | 4 | 4 | D | Plugins natifs Jenkins, Azure DevOps, GitLab |
| 48 | 54 | Intégration avec des outils IA | 4 | 4 | Plateforme | ICA, IFA, Autofix, MCP. Flux vers OpenAI à maîtriser |
| 49 | 55 | Instrumentation pendant les tests CI/CD | 4 | 3 | I | Paraphrase de l'exigence, aucun détail sur l'agent |
| 50 | 56 | Aucune modification du code source | 4 | 4 | I | Instrumentation au runtime, sans modification du code |
| 51 | 57 | Findings liés à un chemin réellement exécuté | 2 | 2 | D | Répond par le DAST alors que l'exigence est IAST |
| 52 | 58 | Traçabilité complète du flux de données | 4 | 4 | I | Taint analysis source-sink, visualisation et pile d'appels |
| 53 | 59 | Bibliothèques vulnérables utilisées à l'exécution | 4 | 4 | I + SCA | SCA au runtime, inclusion dans la licence à confirmer |

## 2. Justifications des écarts avec EXP

- **40, 3 au lieu de 4.** HCL renvoie à une documentation publique et à un document joint, puis à un cadrage avec ses experts. Aucun chiffre n'apparaît dans la réponse. À comparer avec Black Duck, qui détaillait CPU, mémoire, base et bande passante par palier. Si le document joint contient réellement ces abaques, la note peut remonter à 4.
- **44, 2 au lieu de 4.** La liste de plus de 30 langages (Cobol, Apex, Flutter, C/C++, Swift) est celle du SAST. Un agent IAST ne peut pas instrumenter du Cobol ou du Flutter. Pour le DAST la question ne se pose pas, puisqu'il est indépendant du langage. Pour l'IAST, seul concerné par cette exigence, aucune liste de langages ni de versions n'est donnée. C'est le point le plus important à clarifier.
- **45, 3 au lieu de 4.** La réponse décrit un dédoublonnage des anomalies au sein d'une même application, via la gestion des issues. Ce n'est pas forcément une vraie corrélation DAST/IAST (même vulnérabilité reconnue par les deux moteurs, preuve d'exploitation et ligne de code réunies). À démontrer en POC, car c'est un avantage clé d'une plateforme unique.
- **49, 3 au lieu de 4.** La réponse reformule l'exigence sans aucun élément technique : ni mode de déploiement de l'agent, ni technologies supportées, ni injection automatique en Kubernetes.
- **51, 2 comme EXP.** L'exigence est taguée BUILD/IAST, mais HCL répond par le DAST. Or l'élimination structurelle des faux positifs liés à du code non exécuté est une propriété de l'IAST, pas du DAST. L'IAST HCL a probablement cette propriété par nature, mais la réponse ne le dit pas.

## 3. Points de vigilance

- **Intégration IA (48).** HCL cite l'intégration avec les endpoints OpenAI. Pour une banque, envoyer des findings, du code ou des requêtes vers un LLM externe pose un problème de fuite de données. Il faut confirmer que ces fonctions sont désactivables, et qu'un LLM hébergé en interne peut être utilisé à la place.
- **IAST absent des réponses CI/CD (41, 42, 47).** Les réponses citent SAST, DAST et SCA, jamais l'IAST. Il faut vérifier comment la security gate fonctionne avec l'IAST : ouverture et clôture de session, récupération des résultats de l'agent.
- **Point positif sur l'IAST (52).** C'est la première réponse réellement technique sur l'IAST : taint analysis, suivi des données contaminées de la source au sink, visualisation du parcours et pile d'appels complète. Elle montre qu'un vrai moteur IAST existe.
- **Plugin GitLab natif (47).** C'est un avantage net sur Black Duck, qui n'a qu'une intégration par API REST.

## 4. Questions complémentaires pour l'éditeur

1. Liste des langages, frameworks et versions minimales supportés par l'agent IAST, distincte de la liste SAST.
2. Modes de déploiement de l'agent IAST : conteneur, Kubernetes (injection automatique ?), VM, IIS.
3. Fonctionnement de la security gate IAST dans GitLab : comment le pipeline récupère-t-il les résultats de l'agent ?
4. Mécanisme exact de corrélation DAST/IAST, avec un exemple de finding corrélé.
5. Les fonctions IA peuvent-elles être désactivées, ou connectées à un LLM hébergé en interne ?
6. L'analyse SCA au runtime (53) est-elle incluse dans l'offre chiffrée ?

## 5. Conclusion mise à jour sur l'Annexe 03

### DAST : oui, confirmé

Les lignes 37 à 53 confirment la solidité du DAST : intégration CI/CD native (dont un plugin GitLab), blocage du pipeline par politiques, détection des WAF, résultats JSON exploitables.

### IAST : existant mais insuffisamment documenté

La ligne 52 montre un vrai moteur IAST avec taint analysis. Mais les lignes 44, 49 et 51 laissent les questions essentielles sans réponse : quels langages, quelles versions, quel mode de déploiement de l'agent. Pour un outil destiné à couvrir tout le parc applicatif, c'est un manque important.

### Outil unique : HCL reste le candidat principal

HCL reste le seul éditeur analysé à couvrir DAST et IAST dans une même plateforme. Mais la décision dépend des réponses sur l'IAST. Si l'agent IAST ne couvre pas les langages du parc (Java, .NET, Node.js, Python), HCL devient en pratique un DAST complété par un IAST partiel.

### Recommandation

1. Envoyer les questions écrites des deux fichiers avant toute conclusion.
2. Concentrer le POC HCL sur l'IAST : couverture des langages du parc, déploiement de l'agent, security gate IAST dans GitLab, corrélation effective avec le DAST.
3. Noter l'Annexe 02 (exigences techniques) de HCL pour consolider la conclusion.
