7# Problème : l'héritage contourne les restrictions

## En bref

- Un rôle affecté sur un noeud s'applique à tous ses descendants. C'est voulu : une seule affectation sur l'union couvre tous ses points de vente, y compris les futurs.
- Pour retirer une permission sur un point de vente précis, la spec prévoit une spécialisation du rôle sur ce noeud. Par exemple, R13 SELLER spécialisé sur Vendor 2, sans stocklist.download.
- Cette restriction est attachée à un rôle, pas au noeud. Elle ne protège donc que contre ce rôle.
- Si on affecte plus tard sur l'union un autre rôle qui porte la même permission, ce rôle descend complet jusqu'à Vendor 2, et les permissions s'additionnent.
- Résultat : l'utilisateur retrouve stocklist.download sur Vendor 2, alors que personne n'a modifié la restriction. Le contournement ne vient pas d'une erreur de saisie, il découle mécaniquement du modèle.
- Le même effet se produit si une permission est ajoutée plus tard à un rôle global : elle descend sur tous les noeuds spécialisés qui ne l'ont pas explicitement retirée.

## Illustration

En rouge : la nouvelle affectation et son effet. En orange : le noeud spécialisé.

```mermaid
flowchart TD
    NEW["Nouvelle affectation<br/>R14 SALES_MANAGER pour thomas"]:::nouveau
    U["Union JLR<br/>R13 SELLER pour thomas"]
    CA["Chaîne A<br/>hérite R13 et R14"]
    CB["Chaîne B<br/>hérite R13 et R14"]
    V1["Vendor 1<br/>hérite R13 et R14"]
    V2["Vendor 2<br/>Spécialisation de R13 :<br/>retire stocklist.download<br/>---<br/>R14 hérité : stocklist.download"]:::specialise
    V3["Vendor 3<br/>hérite R13 et R14"]
    V4["Vendor 4<br/>hérite R13 et R14"]
    RES["Résultat sur Vendor 2<br/>stocklist.download redevient accessible"]:::nouveau

    NEW -. ajoutée sur .-> U
    U --> CA
    U --> CB
    CA --> V1
    CA --> V2
    CB --> V3
    CB --> V4
    V2 -.-> RES

    classDef nouveau fill:#FCEBEB,stroke:#A32D2D,color:#791F1F
    classDef specialise fill:#FAEEDA,stroke:#854F0B,color:#633806
```

## Rôles et permissions de l'exemple

| Rôle | Permissions |
|---|---|
| R13 SELLER | stocklist.download, quote.create, customer.edit |
| R14 SALES_MANAGER (nouvelle affectation) | stocklist.download, request.approve |
| Spécialisation de R13 sur Vendor 2 | retire stocklist.download |

## Ce qui se passe sur Vendor 2

| Étape | Rôles reçus sur Vendor 2 | stocklist.download |
|---|---|---|
| Avant | R13 spécialisé | Refusé |
| Après l'affectation de R14 sur l'union | R13 spécialisé + R14 hérité complet | **Autorisé** |

Les permissions indiquées sont simplifiées pour l'exemple et doivent être alignées sur le catalogue réel.



# Solution : des rôles qui s'additionnent, sans retrait

On ne retire plus aucune permission sur un noeud, il n'y a donc plus de spécialisation. Une affectation reste simple : un utilisateur, un rôle et un noeud. Elle vaut pour ce noeud et pour tous ses descendants.

Chaque permission sensible est isolée dans un petit rôle à part. Dans l'exemple, le téléchargement du stock n'existe que dans STOCK_DOWNLOAD, et dans aucun autre rôle. Pour qu'un point de vente n'ait pas cette permission, il suffit de ne pas poser STOCK_DOWNLOAD au-dessus de lui et de le donner uniquement là où il est autorisé.

Un rôle affecté plus tard sur l'union ne peut plus ramener le téléchargement sur Vendor 2, puisqu'il ne le contient pas. La restriction tient sans aucun mécanisme de retrait, et ce que l'on lit dans les affectations correspond exactement à ce que l'utilisateur obtient.

## Illustration

Même hiérarchie et même nouvelle affectation que dans le problème. En rouge, la nouvelle affectation. En bleu foncé, les affectations directes de STOCK_DOWNLOAD, posées uniquement là où le téléchargement est autorisé. En bleu clair, les noeuds qui en bénéficient. En vert, le noeud protégé.

STOCK_DOWNLOAD n'est pas affecté sur la chaîne A, sinon il descendrait aussi sur Vendor 2. Il est donc affecté directement sur Vendor 1, ce qui explique que Vendor 1 l'ait et pas son voisin Vendor 2.

```mermaid
flowchart TD
    NEW["Nouvelle affectation<br/>SALES_MANAGER pour thomas"]:::nouveau
    AB["Affectation directe<br/>STOCK_DOWNLOAD pour thomas"]:::affect
    A1["Affectation directe<br/>STOCK_DOWNLOAD pour thomas"]:::affect
    U["Union JLR<br/>SELLER pour thomas"]
    CA["Chaîne A<br/>hérite SELLER et SALES_MANAGER"]
    CB["Chaîne B<br/>hérite SELLER et SALES_MANAGER<br/>reçoit STOCK_DOWNLOAD"]:::download
    V1["Vendor 1<br/>hérite SELLER et SALES_MANAGER<br/>reçoit STOCK_DOWNLOAD"]:::download
    V2["Vendor 2<br/>hérite SELLER et SALES_MANAGER<br/>aucun STOCK_DOWNLOAD"]:::protege
    V3["Vendor 3<br/>hérite SELLER, SALES_MANAGER<br/>et STOCK_DOWNLOAD de la chaîne B"]:::download
    V4["Vendor 4<br/>hérite SELLER, SALES_MANAGER<br/>et STOCK_DOWNLOAD de la chaîne B"]:::download
    RES["Résultat sur Vendor 2<br/>stocklist.download reste refusé"]:::protege

    NEW -. ajoutée sur .-> U
    AB -. ajoutée sur .-> CB
    A1 -. ajoutée sur .-> V1
    U --> CA
    U --> CB
    CA --> V1
    CA --> V2
    CB --> V3
    CB --> V4
    V2 -.-> RES

    classDef nouveau fill:#FCEBEB,stroke:#A32D2D,color:#791F1F
    classDef affect fill:#B5D4F4,stroke:#185FA5,color:#042C53
    classDef download fill:#E6F1FB,stroke:#185FA5,color:#0C447C
    classDef protege fill:#EAF3DE,stroke:#3B6D11,color:#27500A
```

## Rôles et permissions

| Rôle | Permissions |
|---|---|
| SELLER | quote.create, customer.edit |
| SALES_MANAGER (nouvelle affectation) | request.approve |
| STOCK_DOWNLOAD | stocklist.download |

## Affectations de thomas

| Rôle | Noeud | Portée |
|---|---|---|
| SELLER | Union JLR | Tous les points de vente de l'union |
| SALES_MANAGER | Union JLR | Tous les points de vente de l'union (nouvelle affectation) |
| STOCK_DOWNLOAD | Vendor 1 | Vendor 1 uniquement |
| STOCK_DOWNLOAD | Chaîne B | Vendor 3, Vendor 4 et les futurs points de vente de la chaîne B |

## Ce qui se passe sur Vendor 2

| Étape | Rôles reçus sur Vendor 2 | stocklist.download |
|---|---|---|
| Avant | SELLER | Refusé |
| Après l'affectation de SALES_MANAGER sur l'union | SELLER et SALES_MANAGER | Toujours refusé |

## Ce que la solution demande

Elle repose sur une règle de catalogue simple : une permission sensible n'appartient qu'à un seul rôle. Cette règle peut être contrôlée automatiquement en base.

Un point de vente ajouté plus tard sous la chaîne A ne reçoit pas le téléchargement du stock tant qu'on ne le lui donne pas. Le comportement est donc fermé par défaut.

Une restriction locale se traite en affectant le petit rôle plus bas, uniquement là où il est autorisé. Le coût dépend du nombre de restrictions qui existent réellement, chiffre à confirmer avec le métier.

Les permissions sont simplifiées pour l'exemple et seront alignées sur le catalogue réel.



# Solution : restreindre en choisissant où l'on affecte

On reprend exactement les mêmes données que dans le problème. R13 SELLER et R14 SALES_MANAGER contiennent tous les deux stocklist.download, et Vendor 2 ne doit pas l'avoir.

Il n'y a plus de spécialisation et plus aucun retrait. Une affectation reste simple : un utilisateur, un rôle et un noeud, valable pour ce noeud et tous ses descendants. Chaque rôle qui contient la permission à restreindre existe aussi en version limitée, sans cette permission.

La règle est la suivante : au-dessus d'un noeud restreint, on n'affecte que la version limitée. La version complète est affectée plus bas, uniquement sur les noeuds où elle est autorisée. Vendor 2 ne reçoit donc jamais la version complète, ni de son parent ni de l'union.

Quand R14 est affecté à thomas, il suit la même règle que R13 : R14L sur l'union, R14 complet sur la chaîne B et sur Vendor 1. Le contenu de R14 ne change pas, seul l'endroit où on l'affecte compte.

## Illustration

En bleu foncé, les affectations de thomas. En bleu clair, les noeuds qui reçoivent les rôles complets. En vert, le noeud protégé.

```mermaid
flowchart TD
    AU["Affectations sur l'union<br/>R13L et R14L (nouveau)"]:::affect
    AB["Affectations sur la chaîne B<br/>R13 et R14 (nouveau)"]:::affect
    A1["Affectations sur Vendor 1<br/>R13 et R14 (nouveau)"]:::affect
    U["Union JLR"]
    CA["Chaîne A<br/>hérite R13L et R14L"]
    CB["Chaîne B<br/>hérite R13L et R14L<br/>reçoit R13 et R14"]:::download
    V1["Vendor 1<br/>hérite R13L et R14L<br/>reçoit R13 et R14"]:::download
    V2["Vendor 2<br/>hérite R13L et R14L uniquement"]:::protege
    V3["Vendor 3<br/>hérite R13 et R14 de la chaîne B"]:::download
    V4["Vendor 4<br/>hérite R13 et R14 de la chaîne B"]:::download
    RES["Résultat sur Vendor 2<br/>stocklist.download reste refusé"]:::protege

    AU -.-> U
    AB -.-> CB
    A1 -.-> V1
    U --> CA
    U --> CB
    CA --> V1
    CA --> V2
    CB --> V3
    CB --> V4
    V2 -.-> RES

    classDef affect fill:#B5D4F4,stroke:#185FA5,color:#042C53
    classDef download fill:#E6F1FB,stroke:#185FA5,color:#0C447C
    classDef protege fill:#EAF3DE,stroke:#3B6D11,color:#27500A
```

Vendor 1 reçoit R13 et R14 par une affectation directe. Ils ne viennent pas de la chaîne A, sinon ils descendraient aussi sur Vendor 2.

## Rôles et permissions

| Code | Rôle | Permissions |
|---|---|---|
| R13 | SELLER | stocklist.download, quote.create, customer.edit |
| R13L | SELLER_LIMITED | quote.create, customer.edit |
| R14 | SALES_MANAGER | stocklist.download, request.approve |
| R14L | SALES_MANAGER_LIMITED | request.approve |

R13 et R14 sont identiques à ceux du problème. R13L et R14L sont des codes proposés.

## Affectations de thomas

| Rôle | Noeud | Portée |
|---|---|---|
| R13L | Union JLR | Tous les points de vente de l'union |
| R13 | Chaîne B | Vendor 3, Vendor 4 et les futurs points de vente de la chaîne B |
| R13 | Vendor 1 | Vendor 1 uniquement |
| R14L | Union JLR | Tous les points de vente de l'union (nouvelle affectation) |
| R14 | Chaîne B | Vendor 3, Vendor 4 et les futurs points de vente de la chaîne B (nouvelle affectation) |
| R14 | Vendor 1 | Vendor 1 uniquement (nouvelle affectation) |

## Ce qui se passe sur Vendor 2

| Étape | Rôles reçus sur Vendor 2 | stocklist.download |
|---|---|---|
| Avant | R13L | Refusé |
| Après l'affectation de R14 | R13L et R14L | Toujours refusé |

## Ce que la solution demande

La restriction ne repose plus sur un mécanisme caché mais sur l'endroit où l'on affecte. Ce que l'on lit dans les affectations correspond exactement à ce que l'utilisateur obtient.

En contrepartie, affecter par erreur R14 complet sur l'union redonnerait le téléchargement sur Vendor 2. Ce ne serait plus un contournement silencieux mais une affectation visible, que l'écran d'affectation peut signaler en affichant les noeuds concernés.

Un point de vente ajouté plus tard sous la chaîne A ne reçoit que les versions limitées tant qu'on ne lui affecte pas les rôles complets. Le comportement est donc fermé par défaut.

Le coût dépend du nombre de restrictions qui existent réellement, chiffre à confirmer avec le métier.

Les permissions sont simplifiées pour l'exemple et seront alignées sur le catalogue réel.



