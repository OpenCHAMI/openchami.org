+++
title = "Bridging an External IdP to Your Auth Server (Part 1)"
description = "Use an external IdP for login and still issue your own access tokens. A practical path that works with OpenCHAMI."
summary = "Why forwarding the IdP’s ID token won’t work, and a simple pattern that does."
slug = "bridging-idp-part-1"
date = 2024-06-03T03:43:00-05:00
draft = false
weight = 12
categories = ["HPC", "Operations"]
tags = ["auth", "OIDC", "JWT", 'LANL', 'Development']
contributors = ["David J. Allen (LANL)"]
lastmod = 2025-11-06
canonical = "/blog/bridging-idp-1/"
+++

When it comes to authentication, it is not unrealistic to want to use an existing identity provider, like Gitlab or Google, to provide users with multiple login options. This prevents burdening the user to register another account with your service and lowers the barrier for them to use your service. Instead, the user is able to use an account they are more likely to already have with other sites. This is also good for developers as it allows them to skip having to create their own login page and maintain their own backend with a lot of the wiring need to grant users access to resources, given that the developers trust the identity provider. The application or service presenting the login challenge must first register their application with the trusted identity provider so that the IDP can verify the application credentials, ask the user to consent to allowing certain information or actions, and send an ID token and/or access token to the appropriate callback URI  for the service provider to consume.

## So what's the Problem?

And so, once we capture the ID token from the external IDP, we are immediately presented with a problem. Normally, we would only want an ID token to verify the user's identity so we can grant access to specific services or resources, such as an account or pro features, that the user is entitled to access. If our service was also *the thing that granted access tokens* (i.e. the authorization server), then this would not be a problem at all. However, the service and the authorization server are two separate entities. The service is responsible for checking that the ID token is authentic and valid then act accordingly.

So when we want to get an access token for our service, we would have to go through the IDP to initiate the authentication process. Afterwards, the process proceeds as described below:

1. The resource owner (user) is redirected using a authorization URL to a login page with a challenge for identity verification.

2. The resource owner successful logs in and is presented with a consent page to allow IDP to present identity information to service or perform certain actions based on the defined scope.

3. If the user agrees to consent, then the IDP sends an authorization code to the service as defined by [RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749#section-4.1) with an authorization code.

4. Finally, the service must make a request back to the IDP presenting the code in the HTTP headers to perform the token grant and receive a bearer token.

   Here's an example of what an ID token would look like coming from an OIDC implementation as an encoded string:

   ```json
   eyJhbGciOiJSUzI1NiIsImtpZCI6IjBiYTdjYjhlLWRhZDItNGY5ZS05NmU0LWIzNzMyYjcxYWU3NyIsInR5cCI6IkpXVCJ9.eyJhdWQiOltdLCJjbGllbnRfaWQiOiI3MzhhYzYwMS04ZmQ0LTQ3OTctOTIyZC1lZWI0YzU5MjcwNjciLCJleHAiOjE3MTc0NDg5MzQsImV4dCI6e30sImlhdCI6MTcxNzQ0NTMzNCwiaXNzIjoiaHR0cHM6Ly90ZS1oZWFkLm9wZW5jaGFtaS5jbHVzdGVyLyIsImp0aSI6ImUzMTg2Njc1LTQzN2QtNGFjNi04NzQ1LWQ4NGU1MGJiNDkxZiIsIm5iZiI6MTcxNzQ0NTMzNCwic2NwIjpbIm9wZW5pZCIsInNtZC5yZWFkIl0sInN1YiI6IjczOGFjNjAxLThmZDQtNDc5Ny05MjJkLWVlYjRjNTkyNzA2NyJ9.YdPW9frHjFUBOwKdIO9ax84KB33WCSKSCLC9IlBsvWOyXo38EWzyICn31sRR_xACr2YETe90b5LpulXLON05S-NRvkPmBRDUeHdmLtLSHOivFuzvmqF9C0UmCVNkWdQqR4rUcuytSGpgwadXdLDzdy-vSj6gB5kpUT6h9WwavdAbAipvNnR81l_Kpuf7OAmJG3yF1lDkLYXBEm1-6xcbzBCKuK--8sojMlkykT3UolafCVy1jCWLTwVpGCG39O2aJkYuXb5XsdVziY9j-1v_9N60QQA13ntRuCCSGSlGqGEhldzkHHJ4sCAVR-HoQyMKMEMetFh1rt_h8U3FNprTW1Q1sai3N1GD5g345zO2kDezCGhBHbIiDkVpsUXHH39T4wkDoOe5v9Kvl6Gq8R5xhw3oq2yrb9OgFeZm0EqEwP3UZp2wnOuXA75qQzKg2Q9uI6Y7Bf0w_coPGrwWnzfuE9_Cvcu5mwbgRDnMvEN_JpotDbPLbm1YIUYgWBuBipf512HJFz_sn3iMiXLDJGHQ-qRYIzX7oZp4OzKBvxJe2UtXs9alneULa20un75bbJMbGqhw9PgJo6sjQiGGt4t9NZBw8lYPwG5KWp4eeEB_olr6zsvnIAZPuEsNI7xVVJqNaniqrdz9VY0TlLoRH2_Hj0c7vH3grXHCa4vxYGYi08E
   ```

   And this is what it would look like decoded into JSON objects excluding the signature. (Note: This is actually an access token, but an ID token would look similar.)

   ```json
    // header
    {
    "alg": "RS256",
    "kid": "0ba7cb8e-dad2-4f9e-96e4-b3732b71ae77",
    "typ": "JWT"
    }
    // payload
    {
    "aud": [],
    "client_id": "738ac601-8fd4-4797-922d-eeb4c5927067",
    "exp": 1717448934,
    "ext": {},
    "iat": 1717445334,
    "iss": "https://example.openchami.cluster/",
    "jti": "e3186675-437d-4ac6-8745-d84e50bb491f",
    "nbf": 1717445334,
    "scp": [
        "openid",
    ],
    "sub": "738ac601-8fd4-4797-922d-eeb4c5927067"
    }
   ```

The bearer token in the token grant response will include the ID token, access token, and some other metadata as a JSON string, but we're only interested in the ID token for our purposes.But then, what do we do with the ID token itself? It might be tempting to simply forward the ID token to your authorization server, but that can be problematic if you're using an off-the-shelf implementation like [Ory Hydra](https://www.ory.sh/hydra/). The issue here is that the ID token you got from your external IdP has no way of including the token's intended audience which the authorization server will expect. Again, this is assuming that you have no control over this IdP and it provides no way of specifying the audience in the authorization code URL. Therefore, the audience in the ID token will not point to the correct endpoint as required by the [OIDC specification](https://openid.net/specs/openid-connect-core-1_0.html#IDTokenValidation). The diagram below illustrates the two possible paths to consume the ID token.

```mermaid
graph TD
    subgraph Token Forwarding
        a[user] -- login challenge --> b[identity provider]
        b -- sends ID token --> c[authorization server]
    end
    subgraph Service Processing
        d[user] -- login challenge --> e[identity provider]
        e -- sends ID token --> f[service]
        f -- performs token grant --> g[authorization server]
    end
```

If your authorization server is OIDC compliant, then this is bad news since the server will be required to reject the ID token. One solution would be to provided a way of specifying the audience when registering a client or with the authorization code URL as just mentioned. Most sites probably won't allow this out-of-the-box or have their own custom, non-standard way of doing this which is certainly not ideal. [RFC 8707](https://datatracker.ietf.org/doc/html/rfc8707#name-authorization-request) mentions resource indicators which may have remedy the situation, but as for now, this does not seem the way to go.

A better solution would be for your application or service to consume the ID token itself and then handle the an access token grant separately. This is the route that OpenCHAMI is taking for now, and it seems to work fine for our purposes, but it certainly has its advantages and disadvantages. Let's take a closer look at this solution to understand why we might and might not want to go forward with it.

## Concocting a Solution

First, consuming the ID token requires extra logic from your service handle JWTs and to verify the authenticity of the token itself. We certainly would not want just anyone to create a JWT to gain access to any resource they are not authorized to access. Therefore, we must make a HTTP request to fetch a JWKS from the IDP and use it to verify signatures from the received tokens. Next, the service must register itself with the authorization server as a trusted issuer and provide a public key to issue JWTs to the authorization server (assuming that your authorization server supports this). The public key is used by the authorization server to verify the integrity of JWTs sent to it like how we verify the ID token before. Finally, the service must create and sign JWTs to perform a grant as as stated in [RFC 7523](https://datatracker.ietf.org/doc/html/rfc7523#section-3.1) with the appropriate claims.

### The Good, the Bad, and the not so pretty

As mentioned before, going with this type of solution has its positives and negatives. Here are a couple of important details worth mentioning when going with the JWT bearer solution.

**The good:** The most appealing advantage to using the JWT bearer grant type is the JWT customization and flexibility that the grant allows. Unlike the other grant types, it is possible to easily add custom claims, including mapping the ones from your ID token, into the access token. Therefore, your application or service can inject other useful information into the access token that is required by your services.

**The bad:** However, the JWT bearer grant type seems to be much less popular (or used) than the other more common ones like the authorization code or client credentials, excluding the ones that have been deprecated. This may partially be due to the fact that the JWT bearer grant was defined later in [RFC 9068](https://datatracker.ietf.org/doc/html/rfc9068) and was specifically created to handle more specific edge cases, but who knows. Consequentially, the support for performing the JWT bearer grant is limited among the many OIDC implementations. So far, the only implementation that I have found that supports this is Hydra, and even that comes with some limitations. I did not look much into support in [keycloak](https://github.com/keycloak/keycloak/) since it seems that we don't want to go that route.

**The not so pretty:** One enormous limitation with this solution is that it is not possible to issue refresh tokens when performing token grants with Hydra. I don't know if this limitation only exist with Hydra's implementation, but support for the JWT bearer grant is already poor all around as mentioned above, so I think it is safe to assume other implementations likely do not support this as well. Of course, this is certainly not ideal since refresh tokens allow your services to transparently grant new access tokens without having to complete an entire flow again. There are ways to imitate the refresh token process with the service, but may not be the best solution to this problem.

## What's Next?

As you can see, implementing a solution to use an external identity provider with your own services can be a struggle without any good off-the-shelf solutions. The next post will talk specifically about one solution that is currently being used for some of our needs with OpenCHAMI called OPAAL and how it solves the issues addressed in this post. It will also talk a little bit about some of the limitations with the way it is designed, what it is and isn't, and some of the things it may do in the future.

{{< blog-cta >}}
