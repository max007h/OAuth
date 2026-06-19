# Validation des attributs PAR et publication Kafka dans PingFederate

## Contexte

Les SPA envoient des attributs de contexte via un PAR request (Pushed Authorization Request).
Ces attributs doivent etre valides le plus tot possible dans PingFederate.
Les attributs valides sont publies dans un topic Kafka a des fins de journalisation et d'historisation des evenements d'autorisation.

Regle fondamentale : **tracke = valide = publie dans Kafka**.
Aucun attribut non valide ne doit atteindre Kafka.
Aucun attribut non declare ne doit etre tracke.

---

## Diagramme du workflow global

![Workflow PingFederate PAR Kafka](workflow_pf_kafka.png)

---

## Les trois points d'intervention dans PingFederate

### Option A - Custom IdP Adapter (Java) - Recommande

**Moment** : avant et apres l'authentification utilisateur.

Le Custom IdP Adapter est le point le plus precoce. Il intercepte la requete
d'autorisation resolue depuis le PAR, valide les attributs, et peut publier
l'evenement Kafka apres le succes de l'authentification via un hook post-authn.

Avantages :
- Intervention la plus precoce possible
- Acces direct aux parametres PAR custom via `getAdditionalParameters()`
- Logique Java typee, testable, versionnee dans Git
- Un seul adapter configurable pour plusieurs SPA
- Erreur OAuth propre retournee en cas de rejet (`400 invalid_request`)
- Peut publier vers Kafka dans le meme composant apres authn success

Inconvenients :
- Developpement Java requis
- Redemarrage PingFederate necessaire apres chaque mise a jour du JAR
- Dependance Kafka client a integrer dans le classpath PF

### Option B - Authentication Policy avec OGNL - Deconseille

**Moment** : pendant le flow d'authentification.

Les Policy Nodes et expressions OGNL permettent d'intercepter et conditionner
le flow d'authentification sans developper de code Java compile.

Avantages :
- Configurable sans redemarrage PF
- Visible dans l'interface d'administration

Inconvenients :
- OGNL est difficile a maintenir, a tester et a versionner
- Pas adapte a une logique de validation complexe (listes de pays, patterns, etc.)
- La publication Kafka depuis OGNL est extremement complexe voire impossible proprement
- Deconseille pour un contexte bancaire sous DORA

### Option C - Policy Contract Mapping - Trop tard

**Moment** : apres l'authentification utilisateur.

Le Policy Contract Mapping intervient apres que l'utilisateur s'est authentifie.
Il est utile pour mapper des attributs dans le token mais pas pour valider
des parametres de securite en amont.

Raison du rejet : trop tard pour bloquer une requete malveillante proprement.
L'utilisateur a deja vu l'ecran de login.

---

## Ou publier l'evenement Kafka

### Faut-il absolument que validation et publication soient dans le meme composant Java ?

Non. Ce sont deux responsabilites distinctes et on peut les separer.

Trois approches possibles :

**Approche 1 - Tout dans le Custom IdP Adapter (Java)**

La validation et la publication Kafka sont dans le meme JAR.
Le hook `postAuthnStep()` publie l'evenement apres authn success.

```
[Custom Adapter]
  - initiateAuthnRequest() : valide les attributs PAR
  - postAuthnStep()        : publie l'evenement Kafka si authn OK
```

Avantage : un seul composant, logique complete en un endroit.
Inconvenient : le JAR embarque la dependance Kafka (kafka-clients).
Recommande pour commencer.

**Approche 2 - Validation dans le Custom Adapter, publication dans un Plugin Post-Token separe**

PingFederate permet d'enregistrer des plugins de type `TokenCreationPlugin`
ou `AccessTokenAttributeContract` qui s'executent apres emission du token.
La publication Kafka peut y etre placee.

```
[Custom Adapter]          [Post-Token Plugin]
  - validation PAR    -->   - publie Kafka avec claims du token
  - stocke attributs        - acces a subject, client_id, attributs
    en session PF             mappes dans l'ATM
```

Avantage : separation claire des responsabilites, deux JAR independants.
Inconvenient : deux composants a maintenir, les attributs PAR doivent etre
passes via la session PF vers le second plugin.

**Approche 3 - Validation dans le Custom Adapter, publication dans Spring Boot**

Le Resource Server Spring Boot recoit le token JWT avec les attributs mappes
dans les claims. Il publie l'evenement Kafka apres avoir valide le token
et execute la logique metier.

```
[Custom Adapter]     [PingFederate ATM]     [Spring Boot]
  - validation PAR --> mapper attributs  --> valide token
                       dans JWT claims       publie Kafka
```

Avantage : Spring Boot gere nativement Kafka (Spring Kafka), retry,
dead-letter queue. Plus simple operationnellement.
Inconvenient : les attributs PAR doivent etre explicitement mappes dans
l'ATM pour etre presents dans le JWT.

### Recommandation

Pour un premier POC : **Approche 1** (tout dans le Custom Adapter).
Pour une architecture production multi-SPA : **Approche 3** (publication dans Spring Boot),
les attributs etant mappes dans le JWT via l'ATM PingFederate.

---

## Logique de validation des attributs

### Principe whitelist stricte

```
Pour chaque attribut recu dans le PAR :

  Est-il dans la liste des attributs declares (whitelist) ?
  |
  NON --> REJECT (400 invalid_request)
  |
  OUI --> Valider format, valeur, contraintes
          |
          KO --> REJECT (400 invalid_request)
          |
          OK --> Inclure dans l'evenement Kafka
```

Aucun attribut non declare ne passe. Les equipes SPA doivent declarer
explicitement leurs attributs dans la configuration de l'adapter.

### Exemple de regles de validation

```java
// Dans Custom Adapter - initiateAuthnRequest()
HttpServletRequest req = authnAdapterRequest.getHttpRequest();
Map<String, String> params = authnAdapterRequest.getAdditionalParameters();

// Attributs obligatoires communs
String pays  = params.get("pays");
String canal = params.get("canal");
String userId = params.get("userId");

// Validation pays (liste noire)
List<String> paysBloquees = List.of("KP", "IR", "SY", "CU");
if (pays == null || paysBloquees.contains(pays.toUpperCase())) {
    throw new AuthnAdapterException("pays invalide ou bloque : " + pays);
}

// Validation canal
List<String> canauxAutorises = List.of("web", "mobile", "api");
if (canal == null || !canauxAutorises.contains(canal)) {
    throw new AuthnAdapterException("canal non autorise : " + canal);
}

// Validation userId (format)
if (userId == null || !userId.matches("[a-zA-Z0-9_-]{3,64}")) {
    throw new AuthnAdapterException("userId format invalide");
}
```

### Publication Kafka apres authn success

```java
// Dans Custom Adapter - postAuthnStep() ou lookupAuthN() apres succes
private void publierEvenementKafka(Map<String, String> attributs, String subject) {
    Map<String, Object> event = new LinkedHashMap<>();
    event.put("event_type", "authn_success");
    event.put("timestamp", Instant.now().toString());
    event.put("client_id", attributs.get("client_id"));
    event.put("subject", subject);
    event.put("pays", attributs.get("pays"));
    event.put("canal", attributs.get("canal"));
    event.put("userId", attributs.get("userId"));

    String payload = objectMapper.writeValueAsString(event);
    ProducerRecord<String, String> record =
        new ProducerRecord<>("pf.authn.events", subject, payload);
    kafkaProducer.send(record);
}
```

---

## Gestion multi-SPA avec attributs communs et specifiques

### Situation

```
SPA 1 --> pays, canal, userId
SPA 2 --> pays, canal, userId, agence
SPA 3 --> pays, canal, userId, contrat
```

Attributs communs : pays, canal, userId
Attributs specifiques : agence (SPA 2), contrat (SPA 3)

### Configuration de l'adapter par client

L'adapter expose une configuration declarative dans PingFederate.
Chaque instance d'adapter (ou la meme instance avec config par client_id)
declare les attributs obligatoires et les attributs optionnels autorises.

```
Instance KafkaContextAdapter :
  attributs_obligatoires = pays, canal, userId
  attributs_optionnels_par_client :
    spa2 = agence
    spa3 = contrat
  pays_bloques = KP, IR, SY, CU
  kafka_topic  = pf.authn.events
```

### Structure de l'evenement Kafka

```json
{
  "event_type": "authn_success",
  "timestamp": "2026-06-14T10:00:00Z",
  "client_id": "spa2",
  "subject": "user456",
  "attributs": {
    "pays": "DE",
    "canal": "mobile",
    "userId": "456",
    "agence": "75001"
  }
}
```

---

## Acces aux parametres PAR dans le Custom Adapter

Point technique critique a verifier sur PingFederate 13.x.

Les attributs envoyes dans le PAR (etape 1) doivent etre accessibles
dans l'adapter (etape 2, apres resolution du request_uri).

```java
// Methode recommandee sur PF 13
Map<String, String> additionalParams =
    authnAdapterRequest.getAdditionalParameters();

// Log de diagnostic a executer en premier
additionalParams.forEach((k, v) ->
    logger.info("[KafkaAdapter] PAR param disponible: {} = {}", k, v));
```

Si `getAdditionalParameters()` ne retourne pas les parametres PAR custom,
solution de repli via la session PF :

```java
// Stocker lors du pre-authn
HttpSession session = request.getSession();
session.setAttribute("ctx_pays",  request.getParameter("pays"));
session.setAttribute("ctx_canal", request.getParameter("canal"));

// Recuperer apres authn success
String pays  = (String) session.getAttribute("ctx_pays");
String canal = (String) session.getAttribute("ctx_canal");
```

---

## Recapitulatif des decisions

| Question | Decision |
|---|---|
| Ou valider les attributs ? | Custom IdP Adapter (le plus tot) |
| Ou publier vers Kafka ? | Dans l'Adapter (postAuthn) ou Spring Boot |
| Validation et publication dans le meme JAR ? | Non obligatoire, recommande pour POC |
| Attributs inconnus ? | REJECT (whitelist stricte) |
| Attributs valides non declares dans ATM ? | Ne pas publier dans Kafka |
| Acces aux params PAR dans l'Adapter ? | Via getAdditionalParameters() - a verifier PF13 |
| RAR active ? | Non - attributs en query params custom |
| PingAuthorize ? | Non dans le perimetre actuel |
