+++
title = "Use an External IdP and Still Issue Your Own Tokens (Part 2: OPAAL)"
description = "How OPAAL lets you accept an external IdP’s login and mint access tokens from your own auth server using a JWT bearer grant."
summary = "A practical bridge: verify the IdP’s ID token, map claims, and exchange for an access token your services trust."
slug = "bridging-idp-part-2"
date = 2024-12-01T03:43:00-05:00
draft = false
weight = 13
categories = ["HPC", "Operations"]
tags = ["auth", "OIDC", "JWT", "LANL", "Development"]
contributors = ["David J. Allen (LANL)"]
lastmod = 2025-11-06
canonical = "/blog/bridging-idp-2/"
+++


# Bridging the Gap between Identity Provider and Authorization Server (Part 2)

This post is going to cover in more detail about addressing the issues mentioned in the last post by discussing the initial solution for issuing access token JSON web tokens (JWT) used in OpenCHAMI, [OPAAL](https://github.com/OpenCHAMI/opaal). It will also cover some of the other things that were considered before coming to this solution as well and why OPAAL was necessary for what we were trying to accomplish at the time. Hopefully this post will shed some like on what OPAAL was meant to do and how it was used.

## So what is OPAAL exactly?

The acronym stands for "OIDC Provider Automated Authorization Login" and is a tool designed specifically to streamline consuming ID tokens from an external identity provider (IDP) from the OpenCHAMI stack. OPAAL would use the claims from the ID token to create another JWT to use with our internal OIDC authorization server to grant access to internal resources via an access token. This didn't seem like an unreasonable thing to do at the time, but we ran into some problems before coming to this solution.

Our use case required logging into a self-hosted instance of GitLab that we did not control and routing the response to back somewhere we could consume the ID token. This was really beneficial because it did not require us to set up our own IDP service. Initially, this was done with Ory Hydra, but we ran into complications trying to set up the login flow with Kratos's self-service nodes for Identity and Session management within the Ory stack. Documentation was limited and support was almost non-existent, so we moved on. And so, here we are.

First, let's take a brief look at how other web apps might work with external IDPs.

### How might a web app do authentication?

A web app might offer multiple ways to register an account and log into their service with social sign-on. If a user has an option to login with their already existing Google account for example, they would be redirected to a Google sign in page to enter their Google credentials. This would require that our web application be registered with Google as an OAuth 2.0 application so Google would know who and where to send the requested identity information that our application would need later. After the user logs into Google, Google will present a consent page telling the user what information our web application is requesting. If the user accepts, our web application will receive the information to consume, ideally in the form of a JWT. An oversimpified diagram of this process would look some like this:

```mermaid
flowchart LR
a[web app login page] -- redirect --> b[external IDP login]
b --> c[external IDP consent]
c -- redirect with token --> d[web app service]
```

At this point, our web application has the identity information from the IDP it would need for the user to proceed to using our service. Depending on the service, there would not be a need to issue access tokens if our service did not provide any APIs to access. However, if our service was something like Github, we would need to issue our own token that must be included in every request to our APIs.

### Where does OPAAL fit in all of this?

Considering the example above, we can see that *OPAAL takes the place of a web application*. However, OPAAL adds another step to the process.

```mermaid
flowchart LR
a["web app login (from OPAAL)"] -- redirect --> b[external IDP login]
b --> c[external IDP consent]
c -- redirect with token --> d[OPAAL]
d --> e["authorization server (Hydra)"]
```

After consuming the ID token, OPAAL creates and signs another JWT, but not to return to the user as an access token however. Since OPAAL is not an OIDC-compliant provider, having *it issue access tokens would be a bad idea*. Instead, the JWT that OPAAL creates is to perform a JWT bearer grant with Hydra. The details about how this work is explained in [Hydra's documentation](https://www.ory.sh/docs/hydra/guides/jwt). Ultimately, using the JWT bearer grant allowed for flexible access token customization that was needed to include information from the ID token, which would not have been possible using the other grant types.

### Why does the tool exists?

During SI, our specific use-case required students to log-in through a web UI that would return an access token that was usable with OpenCHAMI services. Unfortunately, there was no good off-the-shelf solution at the time that did what we needed it to do without being too overly complicated to set up. This tool exist to solve the problems mentioned in the previous post, which if summed up into a single sentence: to bridge the gap between external identity provider logins and authorizing access to internal resources. That's it. The tool is not designed to be an OIDC provider nor a JWT issuer.

Initially, the plan was to try to get the identity provider to speak to another tool in the Ory stack called Kratos using a self-service node. We had some success initially getting the self-service node up and running with our other services, but there were certainly some issues trying to integrate the UI to work with Hydra. I'm not sure if there's documentation that explains throughly how this is supposed to work out there, but trying to piece things together was not trivial which lead to OPAAL as an alternate solution.

The scope of the tool is only meant to encapsulate the specific problems of that comes with bridging identity providers, however, and should not required to use the rest of OpenCHAMI. Therefore, it can easily be removed and replaced with your own solution if it already exists (i.e. an existing web application like mentioned above). However, it is important to emphasize again that OPAAL *is not* meant to replace the role of a complete OIDC implementation like Hydra, Authelia, Keycloak,  and/or other solutions that are more developed and battle tested. In fact, having an IDP would still be required to work with this setup.

### Wait...what is OPAAL-IDP then?

Although there is an example IDP built into OPAAL, it only contains the bare minimum to replicate the functionality of an OIDC provider and is not fully OIDC compliant. **The internal IDP was made to work for SI and should not be used for anything else.** This will likely be replaced entirely for a more complete, tested, familiar, and reliable solution in the future.

## Conclusion

As stated before, OPAAL is a tool created with a very pecific purpose in mind for a very specific use-case: to bridge the use of an external IDP with an internal authorization server for a specific use case. Keep in mind that this tool is not mandatory to use with the rest of the OpenCHAMI tools and services. Thanks to the modular design, you should be able to easily replace OPAAL with your own solution if you would like.

{{< blog-cta >}}
