# Threat model

Protected assets are profile identity fields, age/role boundaries, optional feedback history, and the integrity of recommendations and support copy.

| Risk | Current control | Residual limitation |
|---|---|---|
| Read copied profile files | AES-GCM per profile; keys in Keychain | A compromised logged-in Mac may defeat application controls |
| Swap or roll back a record | Authenticated index points to immutable generations | No cross-device rollback protection |
| Keychain unavailable | Fail-closed workspace screen, retry, static Support, and a labeled memory-only guest session that never touches locked data | Guest choices disappear when the session ends; saved profiles still require Keychain repair |
| Guest data persists unexpectedly | Guest state is held only by `AppStore` and checkout persistence returns false | Process-memory inspection remains possible on a compromised logged-in Mac |
| Partial write or delete | Write generation then atomically replace index; keys-first delete | Crash testing is local, not independently audited |
| Infer intimate state | No passive sensing, free text, mood score, or gameplay input | Selected need and checkout still reveal limited context locally |
| Hide help behind app state | Static support route outside profile/recommendation flow | PaceBack cannot verify that an external service answers |
| Manipulative engagement | Finite games; no score, timer, streak, currency, loss, or notification loop | Formal dark-pattern review remains pending |
| Misleading health claims | Prohibited-copy checks and explicit limitations | Human review is still required for releases |

Independent security, accessibility, pediatric, privacy, and clinical/domain reviews remain pending.
