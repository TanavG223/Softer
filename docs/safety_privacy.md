# Safety and privacy

Status: implementation contract for an unvalidated macOS prototype, not a clinical, security, HIPAA, COPPA, FDA, or privacy certification.

Softer stores a display name, age band, role, settings, and a bounded ledger containing selected need, activity, optional checkout, and timestamp. It intentionally excludes journal text, inferred mood, game performance, support usage, contacts, sensors, browsing, dwell time, and advertising identifiers.

Each profile record is AES-GCM encrypted with a separate random key held in macOS Keychain. The authenticated encrypted index acts as the commit pointer. A missing or inaccessible key never falls back to plaintext or silently resets the workspace. Profile deletion destroys the Keychain key before removing ciphertext.

Teen, adult, and older-adult users may instead choose a clearly labeled guest session. The guest profile, selected activities, game state, and optional check-outs remain in process memory only. They are not written to the encrypted repository, and leaving the guest session discards them. Starting a guest session does not unlock, overwrite, delete, or treat an unavailable encrypted workspace as empty.

There is no account, tracker, analytics SDK, ad SDK, chatbot, backend, model download, or intentional app network request. A user can explicitly open a support webpage or invoke a system call/text handler; Softer does not send the person’s profile or interaction history.

The app cannot detect crisis or keep someone safe. Static support routes and the memory-only guest path remain available even when the encrypted workspace is unavailable. Child paths are caregiver-operated and deliberately limited pending pediatric review; guest mode does not expose the child profiles that require caregiver setup.
