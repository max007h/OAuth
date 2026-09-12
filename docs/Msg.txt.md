docker inspect env-pingdirectory-1 --format '{{json .Mounts}}' | python3 -m json.tool



docker exec env-pingauthorizepap-1 grep -rl "1443" /opt/out/instance/config/ 2>/dev/null
docker exec env-pingauthorizepap-1 env | grep -i port



docker exec env-pingauthorizepap-1 sh -c \
  "netstat -tln 2>/dev/null || ss -tln 2>/dev/null || cat /proc/net/tcp"

docker inspect env-pingauthorizepap-1 \
  --format '{{json .Config.Healthcheck}}'




curl -k -X POST https://localhost:7443/governance-engine \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"domain":"PUMA","service":"PUMA.Administration","action":"assign",
       "attributes":{"targetNode":"2700010",
                     "targetNodeParents":"2700010,9200005,9100002,9300001,CL_A"}}'




# Mesures complementaires SAST / SCA

## Contexte

Apres relecture du fichier de mesures, je voulais partager un point d'attention avant qu'on fige les specifications avec l'equipe orchestrateur.

Le jeu actuel decrit surtout l'activite de notre outillage : combien de scans ont tourne, combien de findings ils remontent, quelle part du parc est couverte. C'est necessaire et ca constitue une bonne base pour la phase 2. En l'etat, ca ne nous permettra pas de repondre a la question qui nous sera posee en comite : est-ce que notre exposition diminue ?

Il manque d'abord la dimension temporelle. Aujourd'hui, une vulnerabilite critique detectee il y a deux jours et une autre ouverte depuis plus d'un an sont comptees de la meme facon. Tant qu'on ne conserve pas la date de premiere detection et la date de correction, on ne peut produire ni delai de remediation, ni taux de respect d'un SLA, ni age de la dette, c'est-a-dire exactement ce qui nous sera demande dans le cadre du pilotage reglementaire.

Il manque ensuite la dimension de flux. Toutes les mesures sont des photographies a l'instant T. Un stock qui reste stable d'un mois sur l'autre peut aussi bien vouloir dire que rien ne bouge que deux cents vulnerabilites creees et deux cents corrigees. Ce sont deux situations tres differentes, qui appellent des decisions opposees.

Ces deux manques relevent du meme prerequis technique : persister un etat par vulnerabilite (cle stable, date de premiere detection, date de correction, statut) plutot que des compteurs agreges a chaque scan. L'ajustement est a porter cote orchestrateur, en amont de l'indexation Splunk, et il conditionne tous les indicateurs de pilotage qu'on pourra construire ensuite.

Les huit mesures ci-dessous s'appuient sur ce principe.

## Tableau des mesures

| Type | Mesure | Description de synthese | Source de donnees | Commentaire | Formule de calcul |
|---|---|---|---|---|---|
| SAST | SAST_13 | Ecart entre le nombre de vulnerabilites introduites et le nombre de vulnerabilites corrigees sur les 30 derniers jours glissants, sur le perimetre des codes sources deployes en production | SAST_01 (evenements de scan) + Global_03 (deploiements). Pas de CMDB. Cible : index splunk | Suppose que l'orchestrateur emette des evenements de transition (introduite / corrigee) par comparaison au scan precedent du meme module, et non le seul listing brut des findings. Fenetre glissante ancree a minuit (-30d@d vers @d) pour que la valeur ne bouge pas en cours de journee. Seules les corrections effectives sont comptees : derogations et faux positifs exclus, sinon l'indicateur s'ameliore en fermant des tickets | Nb(introduites, 30 j) moins Nb(corrigees, 30 j). Resultat positif : la dette croit |
| SCA | SCA_09 | Ecart entre le nombre de vulnerabilites de composants tiers introduites et corrigees sur les 30 derniers jours glissants, sur le perimetre des codes sources deployes en production | SCA_01 (evenements de scan) + Global_03 (deploiements). Pas de CMDB. Cible : index splunk | Meme principe que SAST_13. Cle d'identite stable : module + composant + CVE. A noter qu'une CVE peut apparaitre sans nouveau build, quand elle est publiee apres le dernier scan. C'est une introduction legitime, elle doit etre comptabilisee | Nb(introduites, 30 j) moins Nb(corrigees, 30 j) |
| SAST | SAST_14 | Nombre de vulnerabilites de criticite critique, encore ouvertes, portees par des codes sources deployes en production appartenant a une application exposee a Internet | SAST_01 + Global_01 / Global_03 pour le rattachement module vers CCX, enrichi par la CMDB (attribut Expose a Internet, classification DICT) par jointure sur le CCX. Cible : index splunk | L'exposition ne vient pas de l'outil de scan mais de la CMDB. Le mapping CCX vers CMDB figure aujourd'hui en option dans Global_01 : il doit passer en prerequis ferme, sinon la mesure n'est pas calculable. Pas d'alternative fiable cote POP a ce stade, c'est a arbitrer avant la phase 2 | Nb distinct(vulnerabilite) ou criticite = critique ET statut = ouvert ET expose_internet = vrai |
| SAST | SAST_15 | Nombre de vulnerabilites de criticite critique, encore ouvertes, portees par des codes sources deployes en production n'appartenant pas a une application exposee a Internet | Identique a SAST_14, CMDB requise | Sert de contrepoint : verifie que la priorisation sur le perimetre expose ne se fait pas au detriment du reste du parc. Techniquement une mesure unique avec l'exposition en dimension suffirait, les deux lignes ne se justifient que si le comite suit deux valeurs distinctes dans le temps | Nb distinct(vulnerabilite) ou criticite = critique ET statut = ouvert ET expose_internet = faux |
| SCA | SCA_10 | Nombre de vulnerabilites de composants tiers de criticite critique (CVSS de 9 a 10), encore ouvertes, sur des codes sources deployes en production appartenant a une application exposee a Internet | SCA_01 + Global_01 / Global_03, enrichi par la CMDB via le CCX. Cible : index splunk | Meme prerequis CMDB que SAST_14. Ajouter l'attribut correctif disponible en dimension permet de separer ce qui est actionnable par nos equipes de ce qui depend de l'editeur | Nb distinct(module + composant + CVE) ou CVSS de 9 a 10 ET statut = ouvert ET expose_internet = vrai |
| SCA | SCA_11 | Nombre de vulnerabilites de composants tiers de criticite critique (CVSS de 9 a 10), encore ouvertes, sur des codes sources deployes en production n'appartenant pas a une application exposee a Internet | Identique a SCA_10, CMDB requise | Meme remarque que pour SAST_15 | Nb distinct(module + composant + CVE) ou CVSS de 9 a 10 ET statut = ouvert ET expose_internet = faux |
| SAST | SAST_16 | Nombre de vulnerabilites ouvertes depuis plus de 90 jours a compter de leur premiere detection, sur les codes sources deployes en production, ventile par niveau de criticite | Etat de vulnerabilite persiste par l'orchestrateur (derive de SAST_01). Pas de CMDB, sauf pour la ventilation par filiere : POP n'ayant pas la connaissance des filieres a date, cette ventilation passerait par la CMDB. Cible : index splunk | Restituable directement dans Splunk des lors que la date de premiere detection est persistee. Le recalcul a la volee sur l'historique brut fonctionne mais devient couteux au-dela de quelques mois : prevoir un summary index ou un KV Store rafraichi a chaque scan. Le seuil de 90 jours est a aligner sur les SLA de remediation une fois ceux-ci formalises. Restitution en barres empilees par criticite | Nb distinct(vulnerabilite) ou statut = ouvert ET (date du jour moins date de premiere detection) superieur a 90 j, groupe par criticite |
| SCA | SCA_12 | Nombre de vulnerabilites de composants tiers ouvertes depuis plus de 90 jours a compter de leur premiere detection, sur les codes sources deployes en production, ventile par niveau de criticite | Etat de vulnerabilite persiste par l'orchestrateur (derive de SCA_01). Pas de CMDB hors ventilation par filiere. Cible : index splunk | Meme principe que SAST_16. L'anciennete se compte a partir de la premiere detection sur le module, pas de la date de publication de la CVE | Nb distinct(module + composant + CVE) ou statut = ouvert ET (date du jour moins date de premiere detection) superieur a 90 j, groupe par criticite |

## Points d'arbitrage

Deux sujets transverses conditionnent l'ensemble.

Les quatre mesures d'exposition (SAST_14, SAST_15, SCA_10, SCA_11) reposent toutes sur le meme rapprochement CMDB via le CCX. Tant qu'il reste optionnel, aucune des quatre n'est produite.

Les huit mesures reposent sur l'objet d'etat par vulnerabilite cote orchestrateur. C'est le seul developpement reellement nouveau demande, et il est mutualise.
