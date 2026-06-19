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


<mxfile host="65bd71144e">
    <diagram id="PingFederate-Workflow" name="Workflow PingFederate Kafka">
        <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
            <root>
                <mxCell id="0"/>
                <mxCell id="1" parent="0"/>
                
                <!-- CONTAINER: PingFederate -->
                <mxCell id="pf_container" value="PingFederate" style="swimlane;whiteSpace=wrap;html=1;childLayout=stackLayout;horizontal=1;startSize=40;horizontalStack=0;fillColor=#ffffff;strokeColor=#000000;fontStyle=1;fontSize=14;align=center;" vertex="1" parent="1">
                    <mxGeometry x="320" y="40" width="440" height="740" as="geometry"/>
                </mxCell>
                
                <!-- 1. Custom IdP Adapter -->
                <mxCell id="step1" value="&lt;b&gt;1. Custom IdP Adapter (Java)&lt;/b&gt;&lt;br&gt;Validation attributs PAR + whitelist pays" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#FFE5CC;strokeColor=#D79B00;fontSize=12;" vertex="1" parent="pf_container">
                    <mxGeometry x="30" y="60" width="380" height="60" as="geometry"/>
                </mxCell>
                
                <!-- 2. Authentication Policy -->
                <mxCell id="step2" value="&lt;b&gt;2. Authentication Policy&lt;/b&gt;&lt;br&gt;OPTION B : OGNL / Policy Node (deconseille)" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#DAE8FC;strokeColor=#6C8EBF;fontSize=12;" vertex="1" parent="pf_container">
                    <mxGeometry x="30" y="200" width="380" height="60" as="geometry"/>
                </mxCell>
                
                <!-- Authentification utilisateur -->
                <mxCell id="step3" value="&lt;b&gt;Authentification utilisateur&lt;/b&gt;&lt;br&gt;HTMLFormAdapter / credentials" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E1F5FE;strokeColor=#00B0FF;fontSize=12;" vertex="1" parent="pf_container">
                    <mxGeometry x="30" y="340" width="380" height="60" as="geometry"/>
                </mxCell>
                
                <!-- Publication evenement Kafka -->
                <mxCell id="step4" value="&lt;b&gt;Publication evenement Kafka&lt;/b&gt;&lt;br&gt;Dans Adapter (postAuthn) OU Plugin Post-Token separe" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E8D1F5;strokeColor=#9933FF;fontSize=12;" vertex="1" parent="pf_container">
                    <mxGeometry x="30" y="490" width="380" height="60" as="geometry"/>
                </mxCell>
                
                <!-- 3. Policy Contract Mapping -->
                <mxCell id="step5" value="&lt;b&gt;3. Policy Contract Mapping&lt;/b&gt;&lt;br&gt;TROP TARD pour validation - apres authn" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#F5F5F5;strokeColor=#CCCCCC;fontSize=12;" vertex="1" parent="pf_container">
                    <mxGeometry x="30" y="630" width="380" height="60" as="geometry"/>
                </mxCell>

                <!-- EXTERNAL: Front-end (Left) -->
                <mxCell id="frontend" value="Front-end" style="swimlane;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#006699;fontStyle=1;fontSize=13;" vertex="1" parent="1">
                    <mxGeometry x="30" y="60" width="190" height="150" as="geometry"/>
                </mxCell>
                <mxCell id="spa1" value="SPA 1&lt;br&gt;&lt;font size=&quot;1&quot;&gt;attr1, attr2, attr3&lt;/font&gt;" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E1F5FE;strokeColor=#00B0FF;" vertex="1" parent="frontend">
                    <mxGeometry x="15" y="40" width="160" height="40" as="geometry"/>
                </mxCell>
                <mxCell id="spa2" value="SPA 2 / SPA 3&lt;br&gt;&lt;font size=&quot;1&quot;&gt;attr1, attr2, attrX&lt;/font&gt;" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E1F5FE;strokeColor=#00B0FF;" vertex="1" parent="frontend">
                    <mxGeometry x="15" y="95" width="160" height="40" as="geometry"/>
                </mxCell>

                <!-- EXTERNAL: Erreur OAuth (Top Right) -->
                <mxCell id="err_oauth" value="&lt;b&gt;Erreur OAuth&lt;/b&gt;&lt;br&gt;400 invalid_request" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#FADBD8;strokeColor=#CD6155;" vertex="1" parent="1">
                    <mxGeometry x="830" y="100" width="130" height="50" as="geometry"/>
                </mxCell>

                <!-- EXTERNAL: SPA recoit token (Middle Right) -->
                <mxCell id="spa_token" value="SPA recoit token" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E1F5FE;strokeColor=#00B0FF;" vertex="1" parent="1">
                    <mxGeometry x="830" y="380" width="150" height="50" as="geometry"/>
                </mxCell>

                <!-- EXTERNAL: Kafka Topic (Bottom Right) -->
                <mxCell id="kafka_topic" value="&lt;b&gt;Kafka Topic&lt;/b&gt;&lt;br&gt;pf.authn.events" style="rounded=0;whiteSpace=wrap;html=1;fillColor=#E8D1F5;strokeColor=#9933FF;" vertex="1" parent="1">
                    <mxGeometry x="830" y="530" width="150" height="60" as="geometry"/>
                </mxCell>

                <!-- CONNECTIONS & LABELS -->
                <!-- Front-end -> Step 1 -->
                <mxCell id="edge1" value="PAR POST&lt;br&gt;(params custom)" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;strokeColor=#006699;labelBackgroundColor=none;fontSize=10;" edge="1" parent="1" source="frontend" target="step1">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- Step 1 -> Erreur OAuth -->
                <mxCell id="edge2" value="REJECT" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;strokeColor=#CD6155;fontColor=#CD6155;labelBackgroundColor=none;fontStyle=1;" edge="1" parent="1" source="step1" target="err_oauth">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- Step 1 -> Step 2 -->
                <mxCell id="edge3" value="OPTION A : Validation ici (recommande)&lt;br&gt;&lt;font color=&quot;#27ae60&quot;&gt;attributs OK&lt;/font&gt;" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;strokeColor=#27ae60;fontSize=10;fontColor=#D79B00;align=center;" edge="1" parent="1" source="step1" target="step2">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- Step 2 -> Step 3 -->
                <mxCell id="edge4" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;strokeColor=#000000;" edge="1" parent="1" source="step2" target="step3">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- Step 3 -> Step 4 -->
                <mxCell id="edge5" value="AUTH SUCCESS" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;strokeColor=#27ae60;fontColor=#27ae60;fontStyle=1;fontSize=10;" edge="1" parent="1" source="step3" target="step4">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- Step 4 -> Step 5 -->
                <mxCell id="edge6" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;strokeColor=#000000;" edge="1" parent="1" source="step4" target="step5">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- Step 3 -> SPA recoit token -->
                <mxCell id="edge7" value="token JWT" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;strokeColor=#27ae60;fontColor=#27ae60;fontSize=10;" edge="1" parent="1" source="step3" target="spa_token">
                    <mxGeometry x="-0.2" relative="1" as="geometry">
                        <mxPoint x="740" y="410" as="sourcePoint"/>
                    </mxGeometry>
                </mxCell>

                <!-- Step 4 -> Kafka Topic -->
                <mxCell id="edge8" value="" style="edgeStyle=orthogonalEdgeStyle;rounded=0;orthogonalLoop=1;jettySize=auto;html=1;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;strokeColor=#9933FF;" edge="1" parent="1" source="step4" target="kafka_topic">
                    <mxGeometry relative="1" as="geometry"/>
                </mxCell>

                <!-- LEGEND BOX -->
                <mxCell id="legend" value="Legende" style="swimlane;whiteSpace=wrap;html=1;fillColor=#ffffff;strokeColor=#CCCCCC;fontStyle=1;fontSize=12;" vertex="1" parent="1">
                    <mxGeometry x="30" y="600" width="220" height="150" as="geometry"/>
                </mxCell>
                <mxCell id="leg_optA" value="" style="whiteSpace=wrap;html=1;fillColor=#FFE5CC;strokeColor=#D79B00;" vertex="1" parent="legend">
                    <mxGeometry x="15" y="35" width="20" height="15" as="geometry"/>
                </mxCell>
                <mxCell id="leg_lblA" value="Option A : recommandee" style="text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=11;" vertex="1" parent="legend">
                    <mxGeometry x="45" y="32" width="160" height="20" as="geometry"/>
                </mxCell>
                <mxCell id="leg_optB" value="" style="whiteSpace=wrap;html=1;fillColor=#DAE8FC;strokeColor=#6C8EBF;" vertex="1" parent="legend">
                    <mxGeometry x="15" y="60" width="20" height="15" as="geometry"/>
                </mxCell>
                <mxCell id="leg_lblB" value="Option B : deconseille (OGNL)" style="text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=11;" vertex="1" parent="legend">
                    <mxGeometry x="45" y="57" width="160" height="20" as="geometry"/>
                </mxCell>
                <mxCell id="leg_optC" value="" style="whiteSpace=wrap;html=1;fillColor=#F5F5F5;strokeColor=#CCCCCC;" vertex="1" parent="legend">
                    <mxGeometry x="15" y="85" width="20" height="15" as="geometry"/>
                </mxCell>
                <mxCell id="leg_lblC" value="Option C : trop tard" style="text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=11;" vertex="1" parent="legend">
                    <mxGeometry x="45" y="82" width="160" height="20" as="geometry"/>
                </mxCell>
                <mxCell id="leg_optD" value="" style="whiteSpace=wrap;html=1;fillColor=#E8D1F5;strokeColor=#9933FF;" vertex="1" parent="legend">
                    <mxGeometry x="15" y="110" width="20" height="15" as="geometry"/>
                </mxCell>
                <mxCell id="leg_lblD" value="Publication Kafka" style="text;html=1;align=left;verticalAlign=middle;whiteSpace=wrap;rounded=0;fontSize=11;" vertex="1" parent="legend">
                    <mxGeometry x="45" y="107" width="160" height="20" as="geometry"/>
                </mxCell>
            </root>
        </mxGraphModel>
    </diagram>
</mxfile>
























<?xml version="1.0" encoding="UTF-8"?>
<mxGraphModel dx="1422" dy="762" grid="0" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" pageWidth="1169" pageHeight="827" math="0" shadow="0">
  <root>
    <mxCell id="0" />
    <mxCell id="1" parent="0" />

    <!-- PingFederate container -->
    <mxCell id="pf" value="PingFederate" style="swimlane;startSize=30;fillColor=#f5f5f5;strokeColor=#666666;fontColor=#333333;fontStyle=1;fontSize=13;" vertex="1" parent="1">
      <mxGeometry x="280" y="40" width="560" height="620" as="geometry" />
    </mxCell>

    <!-- 1. Custom IdP Adapter -->
    <mxCell id="adapter" value="&lt;b&gt;1. Custom IdP Adapter (Java)&lt;/b&gt;&lt;br/&gt;Validation attributs PAR + whitelist pays" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFE0B2;strokeColor=#E65100;fontSize=11;align=center;" vertex="1" parent="pf">
      <mxGeometry x="80" y="60" width="380" height="70" as="geometry" />
    </mxCell>

    <!-- Option A label -->
    <mxCell id="optA" value="OPTION A : Validation ici (recommande)&lt;br/&gt;attributs OK" style="text;html=1;strokeColor=none;fillColor=none;align=center;fontSize=9;fontColor=#2E7D32;fontStyle=2;" vertex="1" parent="pf">
      <mxGeometry x="80" y="140" width="380" height="30" as="geometry" />
    </mxCell>

    <!-- 2. Authentication Policy -->
    <mxCell id="policy" value="&lt;b&gt;2. Authentication Policy&lt;/b&gt;&lt;br/&gt;OPTION B : OGNL / Policy Node (deconseille)" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#BBDEFB;strokeColor=#1565C0;fontSize=11;align=center;" vertex="1" parent="pf">
      <mxGeometry x="80" y="180" width="380" height="70" as="geometry" />
    </mxCell>

    <!-- Authentification utilisateur -->
    <mxCell id="authn" value="&lt;b&gt;Authentification utilisateur&lt;/b&gt;&lt;br/&gt;HTMLFormAdapter / credentials" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2F1;strokeColor=#00695C;fontSize=11;align=center;" vertex="1" parent="pf">
      <mxGeometry x="80" y="300" width="380" height="70" as="geometry" />
    </mxCell>

    <!-- AUTH SUCCESS label -->
    <mxCell id="authSuccess" value="AUTH SUCCESS" style="text;html=1;strokeColor=none;fillColor=none;align=center;fontSize=9;fontColor=#2E7D32;fontStyle=2;" vertex="1" parent="pf">
      <mxGeometry x="80" y="378" width="380" height="20" as="geometry" />
    </mxCell>

    <!-- Publication evenement Kafka -->
    <mxCell id="kafka" value="&lt;b&gt;Publication evenement Kafka&lt;/b&gt;&lt;br/&gt;Dans Adapter (postAuthn) OU Plugin Post-Token separe" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE7F6;strokeColor=#6A1B9A;fontSize=11;align=center;" vertex="1" parent="pf">
      <mxGeometry x="80" y="405" width="380" height="70" as="geometry" />
    </mxCell>

    <!-- 3. Policy Contract Mapping -->
    <mxCell id="contract" value="&lt;b&gt;3. Policy Contract Mapping&lt;/b&gt;&lt;br/&gt;TROP TARD pour validation - apres authn" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#F3E5F5;strokeColor=#880E4F;fontSize=11;align=center;" vertex="1" parent="pf">
      <mxGeometry x="80" y="525" width="380" height="70" as="geometry" />
    </mxCell>

    <!-- Front-end box -->
    <mxCell id="frontend" value="&lt;b&gt;Front-end&lt;/b&gt;" style="swimlane;startSize=25;fillColor=#E3F2FD;strokeColor=#1565C0;fontSize=11;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="40" y="80" width="180" height="130" as="geometry" />
    </mxCell>

    <mxCell id="spa1" value="SPA 1&lt;br/&gt;attr1, attr2, attr3" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#E3F2FD;strokeColor=#1565C0;fontSize=10;align=center;" vertex="1" parent="frontend">
      <mxGeometry x="15" y="35" width="150" height="35" as="geometry" />
    </mxCell>

    <mxCell id="spa2" value="SPA 2 / SPA 3&lt;br/&gt;attr1, attr2, attrX" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#E3F2FD;strokeColor=#1565C0;fontSize=10;align=center;" vertex="1" parent="frontend">
      <mxGeometry x="15" y="80" width="150" height="35" as="geometry" />
    </mxCell>

    <!-- Erreur OAuth -->
    <mxCell id="error" value="&lt;b&gt;Erreur OAuth&lt;/b&gt;&lt;br/&gt;400 invalid_request" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#FFEBEE;strokeColor=#B71C1C;fontColor=#B71C1C;fontSize=11;align=center;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="920" y="95" width="170" height="60" as="geometry" />
    </mxCell>

    <!-- SPA recoit token -->
    <mxCell id="tokenbox" value="SPA recoit token" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#E0F2F1;strokeColor=#00695C;fontSize=11;align=center;" vertex="1" parent="1">
      <mxGeometry x="920" y="320" width="170" height="50" as="geometry" />
    </mxCell>

    <!-- Kafka Topic -->
    <mxCell id="kafkatopic" value="&lt;b&gt;Kafka Topic&lt;/b&gt;&lt;br/&gt;pf.authn.events" style="rounded=1;whiteSpace=wrap;html=1;fillColor=#EDE7F6;strokeColor=#6A1B9A;fontSize=11;align=center;" vertex="1" parent="1">
      <mxGeometry x="920" y="430" width="170" height="60" as="geometry" />
    </mxCell>

    <!-- Legende -->
    <mxCell id="legend" value="&lt;b&gt;Legende&lt;/b&gt;" style="swimlane;startSize=25;fillColor=#f5f5f5;strokeColor=#666666;fontSize=11;fontStyle=1;" vertex="1" parent="1">
      <mxGeometry x="40" y="580" width="200" height="120" as="geometry" />
    </mxCell>
    <mxCell id="leg1" value="Option A : recommandee" style="text;html=1;strokeColor=none;fillColor=#FFE0B2;fontSize=9;align=left;" vertex="1" parent="legend">
      <mxGeometry x="10" y="30" width="175" height="20" as="geometry" />
    </mxCell>
    <mxCell id="leg2" value="Option B : deconseille (OGNL)" style="text;html=1;strokeColor=none;fillColor=#BBDEFB;fontSize=9;align=left;" vertex="1" parent="legend">
      <mxGeometry x="10" y="52" width="175" height="20" as="geometry" />
    </mxCell>
    <mxCell id="leg3" value="Option C : trop tard" style="text;html=1;strokeColor=none;fillColor=#F3E5F5;fontSize=9;align=left;" vertex="1" parent="legend">
      <mxGeometry x="10" y="74" width="175" height="20" as="geometry" />
    </mxCell>
    <mxCell id="leg4" value="Publication Kafka" style="text;html=1;strokeColor=none;fillColor=#EDE7F6;fontSize=9;align=left;" vertex="1" parent="legend">
      <mxGeometry x="10" y="96" width="175" height="20" as="geometry" />
    </mxCell>

    <!-- ARROWS -->

    <!-- SPA -> adapter (PAR POST) -->
    <mxCell id="e1" value="PAR POST&lt;br/&gt;(params custom)" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#1565C0;fontColor=#1565C0;fontSize=9;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" source="frontend" target="adapter" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- adapter -> error (REJECT) -->
    <mxCell id="e2" value="REJECT" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#B71C1C;fontColor=#B71C1C;fontSize=9;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" source="adapter" target="error" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- adapter -> policy (vertical) -->
    <mxCell id="e3" value="" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#2E7D32;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" source="adapter" target="policy" parent="pf">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- policy -> authn (vertical) -->
    <mxCell id="e4" value="" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#333333;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" source="policy" target="authn" parent="pf">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- authn -> kafka (vertical) -->
    <mxCell id="e5" value="" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#2E7D32;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" source="authn" target="kafka" parent="pf">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- kafka -> contract (vertical) -->
    <mxCell id="e6" value="" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#333333;exitX=0.5;exitY=1;exitDx=0;exitDy=0;entryX=0.5;entryY=0;entryDx=0;entryDy=0;" edge="1" source="kafka" target="contract" parent="pf">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- authn -> SPA token JWT -->
    <mxCell id="e7" value="token JWT" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#00695C;fontColor=#00695C;fontSize=9;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" source="authn" target="tokenbox" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

    <!-- kafka -> Kafka Topic -->
    <mxCell id="e8" value="" style="edgeStyle=orthogonalEdgeStyle;html=1;strokeColor=#6A1B9A;exitX=1;exitY=0.5;exitDx=0;exitDy=0;entryX=0;entryY=0.5;entryDx=0;entryDy=0;" edge="1" source="kafka" target="kafkatopic" parent="1">
      <mxGeometry relative="1" as="geometry" />
    </mxCell>

  </root>
</mxGraphModel>
