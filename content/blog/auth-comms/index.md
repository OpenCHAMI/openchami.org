+++
title = "Service-to-Service Auth in OpenCHAMI: Client Credentials, Simple and Safe"
description = "How microservices in OpenCHAMI get signed JWTs without a user present, plus a minimal test flow."
summary = "A short guide to use OAuth2 client credentials to call another service with a JWT in OpenCHAMI."
slug = "auth-comms-client-credentials"
tags = ["auth", "JWT", "OAuth2", "OpenCHAMI"]
categories = ["HPC", "Operations"]
contributors = ["David J. Allen (LANL)"]
date = 2024-03-01T10:00:00-04:00
lastmod = "2025-11-06"
draft = false
canonical = "/blog/auth-comms/"
+++

Every request in OpenCHAMI must be authenticated. When a user calls a service, the request carries a signed JWT. But some calls are not started by a user. For example, BSS may call SMD to look up node details while building a boot script. We still need a valid token.

The answer is the OAuth2 client credentials flow. A service asks the auth server for a token that represents the service, not a human. The service then adds that token to the Authorization header when it calls another service.

Repos
- OPAAL (token service for OpenCHAMI): https://github.com/OpenCHAMI/opaal
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd

Minimal test flow (≤4 commands)
The exact endpoints depend on your auth server. This example uses an OAuth-compatible server. Replace URLs and secrets for your lab.

```bash
# 1) Register a client (once). The response includes client_id and client_secret.
curl -sS -X POST http://auth.local/admin/clients -d '{"client_name":"bss","grant_types":["client_credentials"],"token_endpoint_auth_method":"client_secret_post"}' -H 'Content-Type: application/json'

# 2) Ask for a token using client credentials
ACCESS=$(curl -sS -X POST http://auth.local/oauth2/token -d 'grant_type=client_credentials&client_id=bss&client_secret=secret' | jq -r .access_token)

# 3) Call SMD with the token
curl -H "Authorization: Bearer $ACCESS" http://smd.local/v1/nodes/x0c0s1b0n0
```

Operational notes
- Scope: issue only the scopes the service needs. Keep tokens short-lived.
- Rotation: rotate client secrets on a schedule; keep two active during cutover.
- Propagation: when a user call triggers other calls, pass the user token. Use client credentials only when there is no user.
- Auditing: log who called what. Include the token subject and the client ID.

Where to put this in code
Add a small helper to fetch a token and cache it until it is near expiry. On a 401 from a downstream service, fetch a new token and retry once. Keep the code small and well-tested.

Closing thoughts
With client credentials, services in OpenCHAMI can talk to each other safely without a user in the loop. Keep scopes tight, rotate secrets, and log requests. You now have a clean pattern you can reuse in every microservice.

References
- OPAAL: https://github.com/OpenCHAMI/opaal
- BSS: https://github.com/OpenCHAMI/bss
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

If you're interested in using cloud-like design patterns for the next generation of HPC System Management, we'd love to hear from you. You can reach us through our [Slack](https://openchami.org/slack) or [GitHub](https://github.com/OpenCHAMI).

{{< blog-cta >}}
