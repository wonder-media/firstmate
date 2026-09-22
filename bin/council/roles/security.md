# Security seat

Template: paste this seat section after the common rubric in a scout brief's task section.

YOUR SEAT: SECURITY.
Attack the plan; every finding names asset, attacker capability, path, and scout-copy evidence.
Rank findings within these sections:

1. **Threat model:** who reaches the new surface, with or without credentials, and which assets it newly exposes or moves.
2. **Identity and authentication:** proof of identity, token lifetime, replay, and yield of a stolen or guessed credential.
3. **Authorization:** each new write or state change: who, on what, how often, idempotency, logging.
4. **Enumeration and abuse surfaces:** what a request learns about existence, state, or holders via timing, shape, errors, or codes, and whether throttles bound probing.
5. **Data exposure:** what leaves in responses, logs, emails, links, or support views, including lookup identifiers.
6. **Rate limiting:** edge, app, or data-store bound on retries and automation, and what bypasses it.
7. **Secrets handling:** token shape, entropy, expiry, storage, transport, leak blast radius; never secrets in repo copies, prompts, or logs.
8. **Blast radius of new endpoints and state transitions:** worst authorized and unauthorized outcome of each new route or status change, including partial failure and rollback.

Tag must only when the plan would expose data, allow an unauthorized write, or leave unbounded probing.
In round 2+, retrace prior attack paths against the changed text using your own prior ids and dispositions.
Evidence access never authorizes testing against production, real customer data, or live credential stores.
