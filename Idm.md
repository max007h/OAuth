
What IDM covers natively
  1. Convert union/chain/regroupment/vendor to a relationship graph
  2. Role + assignment: a role attached to a node (managed
     organization) is inherited by its members and by child nodes
  3. Propagation on update — materialisation at write time,
     entitlements written to PingDirectory
  4. Delegated administration and privileges for partner managers
  5. REST endpoints for a custom business UI

Not covered — to be confirmed with Ping
  6. Role scoped to a node — the propagated entitlement is a flat
     set of actions; the originating node does not travel with it.
     Salesman on 2480004 + Viewer on 2700010 yields the union.
  7. Negative exclusion per node, without multiplying role variants
  8. Runtime decision (REQ-5) — which component answers
     "can this user do this action on this target"
     




- The Excel file shared before the workshop contains sample PoC data
  for one partner: 1 Union, 2 Chains, 7 Regroupments, 21 Agreements
- Not representative of production volumes — to be confirmed



# Partner Authorization — Context, Problem, Solution

*Ping AuthZ workshop, Aug 13 2026 · Vendor_Hierarchy_UCR.xlsx · Ping IDM Basics deck*

---

## 1. Context

### 1.1 Scope

- Partner business apps must enforce rights against a partner organisation hierarchy
- Users are partner employees (salespeople, shop managers, regional managers) — not our customers
- Each user acts only on the part of the organisation they are assigned to

### 1.2 Hierarchy

```mermaid
graph TD
    U["Union<br/>9300001 · ROLLER"]
    C["Chain<br/>9100001 · ROLLER GMBH & CO. KG"]
    R["Regroupment<br/>9200001 · ROLLER 1"]
    A["Vendor / Agreement<br/>2541202 · account H"]
    U --> C --> R --> A
```

- Current dataset: 1 Union, 2 Chains, 7 Regroupments, 21 Agreements
- Each spreadsheet row is a leaf carrying its full ancestor path
- Ping's own slide adds: not all partners have all levels configured
- Ping's own slide adds: a user's scope can span separate hierarchies (vendor 3000030 sits in the POCO tree)

### 1.3 Requirements

| # | Requirement | Type |
|---|---|---|
| R1 | Assign business apps to hierarchy levels | Administration |
| R2 | Create roles, group permissions into them | Administration |
| R3 | Assign roles at hierarchy levels, edit permissions | Administration |
| R4 | Assign roles to partner users | Administration |
| R5 | App retrieves role definition at runtime by selected context | **Runtime** |

### 1.4 Workshop outcome (Aug 13)

- PingAuthorize ruled out — assessed as a centralised policy engine, not an administration tool
- PingIDM advised instead; demo showed vendor structure down to user, with profiles, roles, entitlements
- PoC to be run, split into CF and Central streams; follow-up in 2 weeks
- Open risks flagged: remote IdP support, IDM pricing, Phase 1 due end of 2026

---

## 2. Problem

### 2.1 Three functions are being treated as two

- **Administer** — create, assign, delegate → IDM, no debate
- **Resolve** — compute effective rights, propagate inheritance → IDM, confirmed by their slides
- **Decide** — permit or deny at the moment of the click → **not covered by anyone**

R1 to R4 were assessed. R5 was not. IDM produces the data; it does not consume it at runtime.

### 2.2 Consequences if enforcement stays undefined

- No central audit trail of authorization decisions
- One enforcement implementation per business application, with guaranteed drift
- Delay between a right being revoked and the revocation taking effect
- No contextual decision possible (amount, time of day, risk level)

### 2.3 Two axes, not one

- **Role** = what the user can do — inherited downward from the assignment node
- **Scope** = where the user may do it — assigned upward from the leaves
- Both must hold. Reference case:

| Action | Target 2700014 | Why |
|---|---|---|
| `contract.update` | **DENY** | role reaches target, but target not in operational scope |
| `report.read` | **PERMIT** | reporting scope is the regroupment 9200005 |

Same user, same target, opposite answers. Any model that cannot produce both is wrong.

### 2.4 Model gaps revealed by Ping's slide 2

| Gap | Evidence | Impact |
|---|---|---|
| Multiple hierarchies | User 3 reaches vendor 3000030 in POCO tree | Flat row alone is insufficient |
| Variable depth | "not all partners have all levels configured" | Fixed 4-level model not guaranteed |
| Role per (vendor, app) | "vendor 2480004 as BusinessApp:Salesman", "2700010 as BusinessApp:Viewer" | Scope is a triple, not a vendor list |
| Negative exclusions per node | "vendors below Roller2 and vendor 2541202 don't grant download stock list within that role" | Materialised roles multiply combinatorially |
| Custom List | (2700015, 2700017, 2700010) across three regroupments | Not a hierarchy level — needs explicit reverse index |
| Cross-shop user visibility | employee of 2541202 must later work for 2283003, different shop manager | Delegated admin scope is its own model |

### 2.5 Blocking question

- **Does one Agreement Number correspond to exactly one vendor?**
- If 1:1 → each row flat and complete, membership test against four values
- If 1:N → path belongs to the agreement, runtime context must be the Agreement Number, vendor→agreements index required, reporting per vendor double-counts
- This determines the primary key of every managed object in IDM
- Not detectable in testing — surfaces months after go-live, in reconciliation

### 2.6 Data point to confirm

- Regroupment 9200004 (ROLLER 4) appears under both chains (2700006/2700007 under 9100001, 2700008 under 9100002)
- If confirmed, the hierarchy is a graph, not a tree

---

## 3. Solution

### 3.1 Component split

| Component | Job | On decision path |
|---|---|---|
| PingFederate | Authenticates, carries selected context in token | Yes |
| PingIDM | Managed objects, roles, assignments, propagation, delegated admin | No |
| PingDirectory | Stores resolved entitlements | Yes |
| Business app / backend | Enforcement point | Yes |
| PingAuthorize | Central decision point | **To be decided** |

```mermaid
graph TB
    subgraph admin["ADMINISTRATION"]
        UI["Admin UI<br/>partner manager"]
        IDM["PingIDM<br/>objects · roles · propagation"]
    end
    subgraph runtime["RUNTIME"]
        SPA["SPA<br/>partner user"]
        BE["Backend<br/>enforcement"]
    end
    PF["PingFederate"]
    PD[("PingDirectory<br/>resolved entitlements")]

    UI --> IDM
    IDM -->|"materialise"| PD
    SPA -->|"1 · login, pick context"| PF
    PF -->|"2 · token: sub + context"| SPA
    SPA -->|"3 · call + token"| BE
    BE -->|"4 · read entitlements"| PD
    BE -->|"5 · response"| SPA

    style IDM fill:#3F9A8C,color:#fff
    style PD fill:#1B3A6B,color:#fff
```

### 3.2 What IDM covers natively

- `managed/organization` typed union / chain / regroupment / vendor — the hierarchy as a relationship graph
- `managed/role` typed profile / role, linked to `managed/entitlement`
- Virtual property mode **Relationship** — traverses the relationship graph on update, i.e. materialisation at write time
- Assignment propagation down the organisation graph
- Delegated administration and privileges for partner managers
- REST-first endpoints for a custom business UI
- Object update hooks for custom logic

### 3.3 What we still build

- Business UI on the REST API — the IDM console targets IAM admins, not shop managers
- Custom List membership and its reverse index (agreement → lists)
- Scope-per-dimension rule (operational vs reporting)
- Enforcement logic in each business application, unless a central PDP is chosen

### 3.4 Token

```json
{
  "sub": "user1",
  "aud": "contract-app",
  "scope": "contracts reports",
  "partner_context": "9300001",
  "partner_level": "union"
}
```

- Two flat claims — no RAR required
- Context is a user choice, signed by the AS, and re-validated at enforcement
- Scope lists stay out of the token: they would freeze until expiry, so a revoked right would survive until next login
- Token size independent of perimeter size (1 agreement or 300)

### 3.5 Decision rule

```
parents(t) = { t, regroupment(t), chain(t), union(t) } + customLists(t)

hasRole = a grant g exists where
             g.node ∈ parents(target)
             AND action ∈ permissions(g.role)

inScope = action is operational
             ? opScope     ∩ parents(target) ≠ ∅
             : reportScope ∩ parents(target) ≠ ∅

PERMIT if hasRole AND inScope   ·   DENY otherwise
```

- Combining algorithm: deny unless permit
- No rule may widen a scope

### 3.6 Volume handling

- Test membership, never transport the list
- Store scope by node, not by leaf — `opScope: 9200005` covers six agreements in one value
- Index `groupedRetailerNo`, `chainRetailerNo`, `unionRetailerNo` for the reverse query (context selector)
- Partial perimeters (5 of 6 agreements) still require enumeration → needs an `opScopeExclude` attribute

### 3.7 Operational rules

- Cache on ancestors only, 5–15 s. Never cache scopes.
- Degraded mode: no answer from the directory → deny. No permissive fallback.
- Propagation delay must be measured and formally accepted, not discovered.

---

## 4. Sequencing

| Step | Action | Exit criteria |
|---|---|---|
| 0 | Answer the Agreement Number question | Primary key fixed |
| 1 | Model the hierarchy as IDM managed objects | Slide-2 cases represented (multi-hierarchy, variable depth, custom list, exclusions) |
| 2 | Configure propagation, measure it | Propagation delay figure, under realistic volume |
| 3 | Run requirement scenarios end to end, no UI | R5 demonstrated, including the DENY/PERMIT pair on 2700014 |
| 4 | Decide the enforcement point | Central PDP vs per-application, decided explicitly |
| 5 | Business UI and delegated admin | — |

Step 1 data must be organised by lifecycle, not by "static vs dynamic":

| Data | Written by | Frequency |
|---|---|---|
| Hierarchy | source system | rare, batch |
| Custom Lists | business | medium |
| Roles → permissions | business | medium |
| User assignments | partner manager | frequent |

---

## 5. Open questions for the follow-up

1. Does one Agreement Number correspond to exactly one vendor?
2. Where is the decision enforced at runtime — centrally, or per application?
3. How does IDM materialise a role carrying negative exclusions per node, without combinatorial explosion?
4. How are multiple hierarchies and variable depth handled in a single user's scope?
5. How are Custom Lists created and maintained?
6. What propagation delay is acceptable between a revoked right and its effect?
7. Does IDM support the remote IdP use case (raised by David N., still open)?
 
