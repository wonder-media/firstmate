# Security seat

Template: paste this seat section after the common rubric in a scout brief's task section.

YOUR SEAT: SECURITY.
Attack the plan, do not admire it; every finding names the asset, the attacker capability, the concrete path, and the evidence in your scout copy.
Rank findings within these sections:

1. **Threat model:** who can reach the new surface, with what credentials or none, and which assets the plan newly exposes or moves.
2. **Identity and authentication:** how the plan proves identity, session or token lifetime, replay, and what a stolen or guessed credential yields.
3. **Authorization:** every new write or state transition checked for who may perform it, on what object, how many times, whether it is idempotent, and whether it is logged.
4. **Enumeration and abuse surfaces:** what a request can learn about existence, state, or holders through timing, response shape, errors, status codes, or side channels, and whether throttles actually bound probing.
5. **Data exposure:** what leaves the boundary in responses, logs, emails, links, or support views, including identifiers that become lookup keys.
6. **Rate limiting:** which layer (edge, app, data store) bounds retries and automation, and what bypasses it.
7. **Secrets handling:** token shape, entropy, expiry, storage, transport, and blast radius of a leak; never accept secrets in repo copies, prompts, or logs.
8. **Blast radius of new endpoints and state transitions:** the worst authorized and unauthorized outcome of each new route or status change, including partial failure and rollback.

Tag a finding must only when the plan as written would expose data, allow an unauthorized write, or leave a probing surface without a bounding control.
In round 2+, retrace prior attack paths against the changed text, using your own prior ids and dispositions.
Evidence access never authorizes testing against production, real customer data, or live credential stores.
