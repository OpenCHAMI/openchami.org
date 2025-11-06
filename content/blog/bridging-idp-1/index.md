+++
title = "Bridging an External IdP to Your Auth Server (Part 1)"
description = "Use an external IdP for login and still issue your own access tokens. A practical path that works with OpenCHAMI."
summary = "Why forwarding the IdP’s ID token won’t work, and a simple pattern that does."
slug = "bridging-idp-part-1"
date = 2024-06-03T03:43:00-05:00
draft = false
weight = 12
categories = ["HPC", "Operations"]
tags = ["auth", "OIDC", "JWT", "OpenCHAMI"]
contributors = ["David J. Allen (LANL)"]
lastmod = 2025-11-06
canonical = "/blog/bridging-idp-1/"
+++
Many sites want to let users log in with an external identity provider (IdP) like Google or GitLab, but still issue their own access tokens for microservices. That sounds simple, but just forwarding the IdP’s ID token to your authorization server won’t work in most OIDC servers. The audience will not match, and the server must reject it.

This post explains the problem and shows a simple pattern that does work. In Part 2, we’ll connect this to OPAAL for OpenCHAMI.

Why the naive approach fails
An ID token from the external IdP proves the user’s identity to your application. It does not prove the user is a valid audience for your authorization server. Most off‑the‑shelf OIDC servers require the token audience (aud) to point to them. You can’t change that in many hosted IdPs, so forwarding the token gets rejected.

A working pattern
Instead of forwarding the ID token, your service should:
1) Verify the ID token locally using the IdP’s JWKS.
2) Map claims you care about (subject, email, groups).
3) Ask your authorization server for an access token using a flow it supports (e.g., JWT bearer or standard code flow), including the mapped claims when allowed.

This keeps the IdP for login but lets your auth server issue the access token your services understand.

Minimal test flow (≤4 commands)
This is a lab‑only sketch. Replace URLs. The idea is to verify the token, extract claims, and perform a grant to your own auth server.

```bash
# 1) Fetch the IdP’s JWKS and verify ID token (use your language lib; curl shows the endpoint)
curl https://idp.example/.well-known/jwks.json | jq

# 2) Exchange: post a signed JWT (from your service) to your auth server for an access token
ACCESS=$(curl -sS -X POST http://auth.local/oauth2/token \
  -d 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=YOUR_SIGNED_JWT' | jq -r .access_token)

# 3) Call a service with that access token
curl -H "Authorization: Bearer $ACCESS" http://smd.local/v1/nodes
```

If your authorization server is OIDC compliant, then this is bad news since the server will be required to reject the ID token. One solution would be to provided a way of specifying the audience when registering a client or with the authorization code URL as just mentioned. Most sites probably won't allow this out-of-the-box or have their own custom, non-standard way of doing this which is certainly not ideal. [RFC 8707](https://datatracker.ietf.org/doc/html/rfc8707#name-authorization-request) mentions resource indicators which may have remedy the situation, but as for now, this does not seem the way to go.

A better solution would be for your application or service to consume the ID token itself and then handle the an access token grant separately. This is the route that OpenCHAMI is taking for now, and it seems to work fine for our purposes, but it certainly has its advantages and disadvantages. Let's take a closer look at this solution to understand why we might and might not want to go forward with it.

## Concocting a Solution

First, verify the ID token locally using the IdP’s JWKS. Next, register your service as a trusted issuer with your auth server and provide a public key. Finally, sign a JWT and perform a grant as in RFC 7523 with the claims you need.

### The Good, the Bad, and the not so pretty

As mentioned before, going with this type of solution has its positives and negatives. Here are a couple of important details worth mentioning when going with the JWT bearer solution.

**The good:** The most appealing advantage to using the JWT bearer grant type is the JWT customization and flexibility that the grant allows. Unlike the other grant types, it is possible to easily add custom claims, including mapping the ones from your ID token, into the access token. Therefore, your application or service can inject other useful information into the access token that is required by your services.

**The bad:** However, the JWT bearer grant type seems to be much less popular (or used) than the other more common ones like the authorization code or client credentials, excluding the ones that have been deprecated. This may partially be due to the fact that the JWT bearer grant was defined later in [RFC 9068](https://datatracker.ietf.org/doc/html/rfc9068) and was specifically created to handle more specific edge cases, but who knows. Consequentially, the support for performing the JWT bearer grant is limited among the many OIDC implementations. So far, the only implementation that I have found that supports this is Hydra, and even that comes with some limitations. I did not look much into support in [keycloak](https://github.com/keycloak/keycloak/) since it seems that we don't want to go that route.

**The not so pretty:** Some servers don’t issue refresh tokens with JWT bearer grants. If you need long sessions, use short‑lived access tokens with silent re‑auth, or consider an authorization code flow for interactive sessions.

## What's Next?

As you can see, there’s a clean way to use an external IdP for login and still issue your own tokens. In the next post, we’ll show how OpenCHAMI does this with OPAAL.

References
- OPAAL: https://github.com/OpenCHAMI/opaal
- SMD: https://github.com/OpenCHAMI/smd
- Org: https://github.com/OpenCHAMI

{{< blog-cta >}}
