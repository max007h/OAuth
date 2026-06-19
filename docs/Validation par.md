# PAR Attribute Validation and Kafka Publication in PingFederate

## Context

SPAs send context attributes through a PAR request (Pushed Authorization Request).
These attributes must be validated as early as possible inside PingFederate.
Valid attributes are published to a Kafka topic for logging and history of authorization events.

Core rule: **tracked = validated = published to Kafka**.
No unvalidated attribute may reach Kafka.
No undeclared attribute may be tracked.

---

## Global workflow diagram

![Workflow PingFederate PAR Kafka](workflow_pf_kafka.png)

---

## Three points where PingFederate can check attributes

### Option A - Custom IdP Adapter (Java) - Recommended

**When**: before and after user authentication.

The Custom IdP Adapter is the earliest point available. It catches the
authorization request resolved from the PAR, checks the attributes, and can
publish the Kafka event after the authentication succeeds, using a
post-authn hook.

Pros:
- Earliest possible check point
- Direct access to custom PAR parameters through `getAdditionalParameters()`
- Typed Java logic, easy to test, stored in Git
- One single adapter can serve many SPAs
- Returns a clean OAuth error when rejecting (`400 invalid_request`)
- Can publish to Kafka from the same component after authn success

Cons:
- Requires Java development
- PingFederate must restart after every JAR update
- The Kafka client library must be added to the PF classpath

### Option B - Authentication Policy with OGNL - Not recommended

**When**: during the authentication flow.

Policy Nodes and OGNL expressions let you branch and check the
authentication flow without writing compiled Java code.

Pros:
- Can be changed without restarting PF
- Visible in the admin UI

Cons:
- OGNL is hard to maintain, test, and track in version control
- Not suited for complex check logic (country lists, patterns, etc.)
- Publishing to Kafka from OGNL is very hard, almost impossible to do cleanly
- Not recommended for a banking context under DORA

### Option C - Policy Contract Mapping - Too late

**When**: after the user has authenticated.

Policy Contract Mapping runs after the user has logged in. It is useful
for mapping attributes into the token, but not for checking security
parameters early.

Why it is rejected: too late to block a bad request properly. The user
has already seen the login screen.

---

## Where to publish the Kafka event

### Must validation and publication be in the same Java component?

No. These are two separate jobs and can be split.

Three possible setups:

**Setup 1 - Everything in the Custom IdP Adapter (Java)**

Validation and Kafka publication live in the same JAR.
The `postAuthnStep()` hook publishes the event after authn success.

```
[Custom Adapter]
  - initiateAuthnRequest() : checks PAR attributes
  - postAuthnStep()        : publishes the Kafka event if authn is OK
```

Pro: one single component, all logic in one place.
Con: the JAR carries the Kafka dependency (kafka-clients).
Recommended as a starting point.

**Setup 2 - Validation in the Custom Adapter, publication in a separate Post-Token Plugin**

PingFederate supports plugins of type `TokenCreationPlugin` or
`AccessTokenAttributeContract` that run after the token is issued.
Kafka publication can be placed there.

```
[Custom Adapter]          [Post-Token Plugin]
  - checks PAR params -->   - publishes to Kafka using token claims
  - stores attributes       - reads subject, client_id, attributes
    in the PF session         mapped in the ATM
```

Pro: clear split of responsibilities, two independent JARs.
Con: two components to maintain, PAR attributes must be passed through
the PF session to reach the second plugin.

**Setup 3 - Validation in the Custom Adapter, publication in Spring Boot**

The Spring Boot Resource Server gets the JWT with attributes mapped into
claims. It publishes the Kafka event after checking the token and running
the business logic.

```
[Custom Adapter]     [PingFederate ATM]     [Spring Boot]
  - checks PAR    --> maps attributes    --> checks token
                       into JWT claims        publishes to Kafka
```

Pro: Spring Boot natively handles Kafka (Spring Kafka), retry, and
dead-letter queues. Simpler to run in production.
Con: PAR attributes must be explicitly mapped in the ATM to show up in
the JWT.

### Recommendation

For a first POC: **Setup 1** (everything in the Custom Adapter).
For a production multi-SPA setup: **Setup 3** (publication in Spring
Boot), with attributes mapped into the JWT through the PingFederate ATM.

---

## Attribute check logic

### Strict whitelist rule

```
For each attribute received in the PAR:

  Is it on the list of declared attributes (whitelist)?
  |
  NO  --> REJECT (400 invalid_request)
  |
  YES --> Check format, value, and rules
          |
          FAIL --> REJECT (400 invalid_request)
          |
          PASS --> Include it in the Kafka event
```

No undeclared attribute is allowed through. SPA teams must explicitly
declare their attributes in the adapter configuration.

### Sample check rules

```java
// Inside Custom Adapter - initiateAuthnRequest()
HttpServletRequest req = authnAdapterRequest.getHttpRequest();
Map<String, String> params = authnAdapterRequest.getAdditionalParameters();

// Common required attributes
String country = params.get("pays");
String channel = params.get("canal");
String userId  = params.get("userId");

// Country check (blocklist)
List<String> blockedCountries = List.of("KP", "IR", "SY", "CU");
if (country == null || blockedCountries.contains(country.toUpperCase())) {
    throw new AuthnAdapterException("invalid or blocked country: " + country);
}

// Channel check
List<String> allowedChannels = List.of("web", "mobile", "api");
if (channel == null || !allowedChannels.contains(channel)) {
    throw new AuthnAdapterException("channel not allowed: " + channel);
}

// userId format check
if (userId == null || !userId.matches("[a-zA-Z0-9_-]{3,64}")) {
    throw new AuthnAdapterException("userId has a bad format");
}
```

### Kafka publication after authn success

**Note for the POC**: there is no real Kafka producer yet. Publication is
simulated with a simple console trace (`System.out` / logger). This lets
you test the validation flow end to end before adding the real
`kafka-clients` dependency.

```java
// Inside Custom Adapter - postAuthnStep(), runs after authn success
private void publishKafkaEvent(Map<String, String> attributes, String subject) {
    String event = "{"
        + "\"event_type\":\"authn_success\","
        + "\"subject\":\"" + subject + "\","
        + "\"canal\":\"" + attributes.get("canal") + "\","
        + "\"userId\":\"" + attributes.get("userId") + "\","
        + "\"timestamp\":\"" + java.time.Instant.now() + "\""
        + "}";

    // POC: trace only, no real Kafka call yet
    System.out.println("[KAFKA SIMULATION] topic=pf.authn.events event=" + event);

    /*
     * Real production code (commented out for the POC):
     *
     * ProducerRecord<String, String> record =
     *     new ProducerRecord<>("pf.authn.events", subject, event);
     * kafkaProducer.send(record, (meta, ex) -> {
     *     if (ex != null) logger.severe("Kafka send failed: " + ex.getMessage());
     *     else logger.info("Kafka OK offset=" + meta.offset());
     * });
     */
}
```

---

## Multi-SPA setup with shared and specific attributes

### Situation

```
SPA 1 --> country, channel, userId
SPA 2 --> country, channel, userId, branch
SPA 3 --> country, channel, userId, contract
```

Shared attributes: country, channel, userId
Specific attributes: branch (SPA 2), contract (SPA 3)

### Per-client adapter configuration

The adapter exposes a config screen inside PingFederate. Each adapter
instance (or one shared instance with per-client_id config) declares the
required attributes and the allowed optional attributes.

```
KafkaContextAdapter instance:
  required_attributes = country, channel, userId
  optional_attributes_per_client:
    spa2 = branch
    spa3 = contract
  blocked_countries = KP, IR, SY, CU
  kafka_topic = pf.authn.events
```

### Kafka event structure

```json
{
  "event_type": "authn_success",
  "timestamp": "2026-06-14T10:00:00Z",
  "client_id": "spa2",
  "subject": "user456",
  "attributes": {
    "country": "DE",
    "channel": "mobile",
    "userId": "456",
    "branch": "75001"
  }
}
```

---

## Reading PAR parameters inside the Custom Adapter

This is a key technical point to confirm on PingFederate 13.x.

Attributes sent in the PAR (step 1) must be reachable inside the adapter
(step 2, after the request_uri is resolved).

```java
// Recommended method on PF 13
Map<String, String> additionalParams =
    authnAdapterRequest.getAdditionalParameters();

// First debug step: print every available param
additionalParams.forEach((k, v) ->
    logger.info("[KafkaAdapter] PAR param found: {} = {}", k, v));
```

If `getAdditionalParameters()` does not return the custom PAR
parameters, a fallback through the PF session can be used:

```java
// Store during pre-authn
HttpSession session = request.getSession();
session.setAttribute("ctx_country", request.getParameter("pays"));
session.setAttribute("ctx_channel", request.getParameter("canal"));

// Read back after authn success
String country = (String) session.getAttribute("ctx_country");
String channel = (String) session.getAttribute("ctx_channel");
```

---

## Decision summary

| Question | Decision |
|---|---|
| Where to check attributes? | Custom IdP Adapter (earliest point) |
| Where to publish to Kafka? | In the Adapter (postAuthn) or in Spring Boot |
| Same JAR for check and publish? | Not required, recommended for the POC |
| Unknown attributes? | REJECT (strict whitelist) |
| Valid attributes not declared in the ATM? | Do not publish to Kafka |
| Reading PAR params in the Adapter? | Through getAdditionalParameters() - confirm on PF13 |
| Is RAR enabled? | No - attributes are sent as custom query params |
| Is PingAuthorize used? | Not in the current scope |
| Kafka publication in the POC? | Simulated with a console trace, no real producer yet |




Custom IdP Adapter — Source Code Walkthrough
A working example of a PingFederate IdP Adapter that validates PAR parameters before the login screen is shown.
The adapter below implements the IdpAuthenticationAdapterV2 interface from the PingFederate SDK. It intercepts the authorization request immediately after PingFederate resolves the request_uri (PAR), and before the user sees any login form.
Two parameters are validated:
canal must be one of web, mobile, or api, and must not exceed 10 characters. userId must match the pattern [a-zA-Z0-9_\-]{3,64} — alphanumeric, hyphens and underscores allowed, between 3 and 64 characters.
If either check fails, the adapter returns AUTHN_STATUS.FAILURE immediately, and the user never reaches the login screen. If both checks pass, a simulated Kafka event is printed to the container logs ([KAFKA SIMULATION] topic=pf.authn.events), and the adapter returns AUTHN_STATUS.SUCCESS to hand off to the next node in the policy (HTMLFormAdapter).



Problem
When a client application sends a PAR request to PingFederate, the custom parameters included in that request (such as canal and userId) are not validated by PingFederate itself. They are passed through as-is into the authorization flow.
This creates a risk: if those parameters are consumed downstream by a Kafka publisher, a SIEM ingestion pipeline, or any logging system, unvalidated or malformed data enters those systems without any prior check. A client could send an oversized value, an unexpected format, or an unauthorized channel identifier, and that data would be recorded as-is in audit logs or event streams.
The requirement is therefore to validate these parameters at the earliest possible point inside PingFederate, before any downstream system is allowed to consume them, and to reject the request immediately with a proper OAuth error if validation fails.


