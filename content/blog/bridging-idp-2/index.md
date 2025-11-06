+++
title = "Use an External IdP and Still Issue Your Own Tokens (Part 2: OPAAL)"
description = "How OPAAL lets you accept an external IdP’s login and mint access tokens from your own auth server using a JWT bearer grant."
summary = "A practical bridge: verify the IdP’s ID token, map claims, and exchange for an access token your services trust."
slug = "bridging-idp-part-2"
date = 2024-12-01T03:43:00-05:00
draft = false
weight = 13
categories = ["HPC", "Operations"]
tags = ["auth", "OIDC", "JWT", "OpenCHAMI"]
contributors = ["David J. Allen (LANL)"]
lastmod = 2025-11-06
canonical = "/blog/bridging-idp-2/"
+++

In Part 1, we showed why you can’t just forward an external IdP’s ID token to your authorization server and expect it to work. The audience won’t match, and compliant servers must reject it. This post shows the working pattern in practice with OPAAL for OpenCHAMI.

OPAAL is a small bridge. It lets users authenticate with an external IdP you don’t control, then mints an access token from your own authorization server that your microservices trust. It does this by verifying the ID token, mapping claims you care about, and using a JWT bearer grant to ask your auth server for an access token.

What OPAAL does (and doesn’t)
OPAAL stands for “OIDC Provider Automated Authorization Login.” Think of it as a login broker, not an OIDC provider. It:
- Redirects users to the external IdP for login and consent.
- Receives and verifies the IdP’s ID token (via JWKS).
- Maps selected claims (subject, email, groups/roles) into a signed JWT assertion.
- Exchanges that assertion with your authorization server (e.g., Hydra) using a JWT bearer grant to mint an access token.

OPAAL does not try to be a full IdP or a general token issuer. It doesn’t replace Hydra, Authelia, or Keycloak. It’s a thin piece that lets you keep external login while issuing tokens your services understand.

End‑to‑end flow
Here’s the high‑level request path with OPAAL in the middle:

```mermaid
flowchart LR
	A[Browser: /login] -- redirect --> B[External IdP]
	B --> C[Consent]
	C -- id_token --> D[OPAAL]
	D -- signed assertion --> E[Auth Server (e.g., Hydra)]
	E -- access token --> F[OPAAL]
	F -- token/cookie --> G[Your App/API]
```

Why this works
The authorization server issues the access token, so audience, issuer, and signing keys match what your services expect. The external IdP is still the source of truth for user identity. OPAAL just proves to your auth server, via a signed assertion, that “this user just logged in with the IdP and here are the mapped claims.”

Claim mapping and token shape
Keep mapping simple and explicit:
- Subject: Use the IdP’s stable user ID (sub) as your internal subject or map it to a canonical form.
- Email/name: Optional, but helpful for logs and UIs.
- Group → scope/role: Map only groups you trust into access token scopes/roles. Avoid raw pass‑through.

You’ll configure your auth server to accept signed assertions from OPAAL (public key or client credential), and to include allowed mapped claims in the access token. The JWT bearer flow is defined in RFC 7523; access tokens as JWTs are covered in RFC 9068. Hydra documents the grant here: https://www.ory.sh/docs/hydra/guides/jwt

Operational notes
Short, real‑world guidance we’ve found useful:
- Keep OPAAL stateless. Store minimal session data and rely on the auth server for token lifetimes.
- Prefer short‑lived access tokens. If you need long sessions, re‑issue silently or switch interactive users to authorization code flow.
- Log token exchanges at INFO with request IDs, not token contents. Never log raw tokens.
- Rate‑limit exchanges to protect your auth server during login spikes.

Minimal lab sketch (≤4 commands)
This sketch shows the essence: exchange a signed assertion for an access token, then call a service. Use your language’s JWT library to sign the assertion; curl shows the endpoints.

```bash
# 1) Exchange your signed JWT assertion for an access token (Hydra example)
ACCESS=$(curl -sS -X POST http://auth.local/oauth2/token \
	-d 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
	-d 'assertion=YOUR_SIGNED_JWT' | jq -r .access_token)

# 2) Call an API with that token (e.g., SMD)
curl -H "Authorization: Bearer $ACCESS" http://smd.local/v1/nodes | jq '. | length'
```

If you already run Hydra, register OPAAL as a trusted issuer for the JWT bearer grant and publish OPAAL’s public key. Start with a small claim set, then add more only when a service needs them.

What about an internal IdP?
OPAAL includes a minimal example IdP used for training. It is not OIDC compliant and is not meant for production. In production, use a real IdP (your enterprise IdP, GitLab, Google, etc.) for login and keep OPAAL as the bridge.

When to use this pattern
Use OPAAL when:
- You must accept external IdP login you do not control.
- Your services need tokens issued by your own authorization server.
- You want explicit control over token content and lifetimes.

Skip OPAAL when:
- You can make your services trust the external IdP’s access tokens directly.
- You’re ready to move entirely to your own end‑to‑end IdP and authorization server.

Wrap‑up
OPAAL gives you a clean, testable way to keep external IdP login and still issue access tokens your services trust. Verify the ID token, map the claims you need, exchange via JWT bearer, and you’re done. It’s small, auditable, and fits well with OpenCHAMI’s modular approach.

References
- OPAAL: https://github.com/OpenCHAMI/opaal
- Hydra JWT bearer grant: https://www.ory.sh/docs/hydra/guides/jwt
- RFC 7523 (JWT bearer): https://www.rfc-editor.org/rfc/rfc7523
- RFC 9068 (Access Tokens as JWTs): https://www.rfc-editor.org/rfc/rfc9068

{{< blog-cta >}}
