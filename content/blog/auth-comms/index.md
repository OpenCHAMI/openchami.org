---
title: 'Authenticated Service to Service Communication with client credentials'
date: 2024-03-01T10:00:00-04:00
description: "In this post, David describes how we authenticate every request within OpenCHAMI without a service mesh."
summary: "OpenCHAMI uses signed JWTs for authentication and authorization.  Users must include a valid token with every request which will then be passed on to every subsequent microservice involved in processing that request.  However, there are some internal requests that aren't triggered directly by a user.  For these, we still need a valid token, but without a specific user to tie it to, we need to use a different kind of JWT." 
draft: false
weight: 11
categories: ["Development", "LANL"]
tags: []
contributors: ["David J. Allen (LANL)"]
pinned: false
homepage: false
seo:
  title: "" # custom title (optional)
  description: "" # custom description (recommended)
  canonical: "" # custom canonical URL (optional)
  noindex: false # false (default) or true
---

## Authentication and Authorization in OpenCHAMI

OpenCHAMI is a loose collection of microservices that all obey the same rules for interoperability.  One important rule is that every request must be positively authenticated.  We have chosen bearer token authentication for each request as our preferred authentication method.  As covered in our [roadmap issue #11](https://github.com/OpenCHAMI/roadmap/issues/11), we have selected JSON Web Tokens(JWTs) as our token of choice.  It is a signed token that the caller can send in an HTTP header contains enough information to authenticate the user and describe how the token can be used.  Users follow a standard Oauth2 authorization flow to obtain their token.  Each microservice can then read the token to make decisions about what is permitted in the context of the request.  It is common for one microservice to get some information from another microservice in order to fulfil a request.  In that case, the user's original JWT can be forwarded along for other services to work with.  Following this pattern, it doesn't matter how many microservices are involved, the user's token can be reused in every context without changes.

However, there are some situations in which the user isn't the originator of the request.  For example, when a compute node requests a boot script from [bss](https://github.com/OpenCHAMI/bss), there is no "user" involved.  When bss makes a call to smd to get more context , we need a way to indicate to smd that it should process the request. We also need a way to record who made the request and why.  The Oauth standard has a path we can take.  BSS can request its own token through the client credentials grant flow.  In this post, we'll explore how the OpenCHAMI project has extended JWT-based authentication to support client credentials in addition to user-based authentication.

The OAuth 2.0 framework specification, [RFC 6749](https://datatracker.ietf.org/doc/html/rfc6749#section-4.4), details how an OAuth client may request a token from an authentication server. This is achieved by performing a client credentials grant flow, similar to how it was described in a [previous post](https://ochami.org/posts/smd-jwtauth/), but now we want to implement it directly into the microservice. Of course for this flow, **we assume that the clients are trusted** and that we have access to the authentication server's admin endpoints. Like before, Ory Hydra will be used as our authentication server, but we will use the HTTP RESTful API instead of the Hydra CLI tool.

Implementing the flow requires to receive a token only requires three simple steps:

1. Create an OAuth2 client and make a `POST` request to the `/admin/clients`

2. Authorize the OAuth2 client with another `POST` request to the `/oauth2/auth`

3. Receive an access token with a final `POST` request to the `/oauth2/token`

The implementation is done in Go and integrated into our OpenCHAMI fork of BSS.

## Implementing the Client Credentials Flow in BSS

We need to be able to make HTTP requests to our authentication server to complete each step listed above. To simply things a bit, we can wrap some of the relevant OAuth2 details in a HTTP client.

```go
type OAuthClient struct {
    http.Client
    Id                      string
    Secret                  string
    RegistrationAccessToken string
    RedirectUris            []string
}
```

These are all common parameters need for our requests either in the request's body or header. We then implement the `CreateOAuthClient` function. 

### Creating an OAuth2 Client With the Authentication Server

```go
func (client *OAuthClient) CreateOAuthClient(registerUrl string) ([]byte, error) {
    // hydra endpoint: POST /clients
    data := []byte(`{
        "client_name":                "bss",
        "token_endpoint_auth_method": "client_secret_post",
        "scope":                      "openid email profile read",
        "grant_types":                ["client_credentials"],
        "response_types":             ["token"],
        "redirect_uris":               ["http://hydra:5555/callback"],
        "state":                      "12345678910"
    }`)

    req, err := http.NewRequest("POST", registerUrl, bytes.NewBuffer(data))
    if err != nil {
        return nil, fmt.Errorf("failed to make request: %v", err)
    }
    req.Header.Add("Content-Type", "application/json")
    res, err := client.Do(req)
    if err != nil {
        return nil, fmt.Errorf("failed to do request: %v", err)
    }
    defer res.Body.Close()

    b, err := io.ReadAll(res.Body)
    if err != nil {
        return nil, fmt.Errorf("failed to read response body: %v", err)
    }
    // fmt.Printf("%v\n", string(b))
    var rjson map[string]any
    err = json.Unmarshal(b, &rjson)
    if err != nil {
        return nil, fmt.Errorf("failed to unmarshal response body: %v", err)
    }
    // set the client ID and secret of registered client
    client.Id = rjson["client_id"].(string)
    client.Secret = rjson["client_secret"].(string)
    client.RegistrationAccessToken = rjson["registration_access_token"].(string)
    return b, nil
}
```

The trickest part of making this request is knowing what to include in each request body and header. Most of the request body parameters can be hard coded, but make sure that the body includes `redirect_uris` with an "s" and to set any other parameters you'd want the client to have such as scope. The response should then include the client ID, secret, and registeration access token that is needed for the other two requests, which is stored using the `OAuthClient` struct declared earlier. *(Note: If you included a client ID and secret in the request body, it will be used instead of a generated one.)*

### Authorizing the OAuth2 Client

The next piece of the puzzle is to authorize the OAuth2 client to receive a token. This step will not work if you don't set `oidc.dynamic_client_registration.enabled=true` in the Hydra config. Also, regardless of the `token_endpoint_auth_method`, you are **required to include the `registration_access_token` in the authorization header when using dynamic registration**. 

Like in the previous step, this step includes making another request to the authentication server. We include the client ID and secret in the request body, but set the `Authorization` header to `Bearer {registrationAccessToken}`. Make sure to also include the correct URL encoded `redirect_uri` (without an "s") string, set the same `state` parameter as before, and to set the `Content-Type` header to `application/x-www-form-urlencoded`.

```go
func (client *OAuthClient) AuthorizeOAuthClient(authorizeUrl string) ([]byte, error) {
    body := []byte("grant_type=client_credentials&scope=read&client_id=" + client.Id +
        "&client_secret=" + client.Secret +
        "&redirect_uri=" + url.QueryEscape("http://hydra:5555/callback") +
        "&response_type=token" +
        "&state=12345678910",
    )
    headers := map[string][]string{
        "Authorization": {"Bearer " + client.RegistrationAccessToken},
        "Content-Type":  {"application/x-www-form-urlencoded"},
    }

    req, err := http.NewRequest("POST", authorizeUrl, bytes.NewBuffer(body))
    req.Header = headers
    if err != nil {
        return nil, fmt.Errorf("failed to make request: %v", err)
    }
    res, err := client.Do(req)
    if err != nil {
        return nil, fmt.Errorf("failed to do request: %v", err)
    }
    defer res.Body.Close()

    return io.ReadAll(res.Body)
}
```

The response doesn't return anything all that interesting, and as long as you don't received an error (likely caused by a typo or incorrect request parameter), everything should work fine.

### Performing the Token Grant for an Access Token

Finally, the last step includes making a request for the access token from the authentication server. Again, we use our client ID, secret, and registration access token to perform the request with similar headers as before. The scope can only be set to one used to create the client in the first step.

```go
func (client *OAuthClient) PerformTokenGrant(remoteUrl string) (string, error) {
    // hydra endpoint: /oauth/token
    body := "grant_type=" + url.QueryEscape("client_credentials") +
        "&client_id=" + client.Id +
        "&client_secret=" + client.Secret +
        "&scope=read"
    headers := map[string][]string{
        "Content-Type":  {"application/x-www-form-urlencoded"},
        "Authorization": {"Bearer " + client.RegistrationAccessToken},
    }
    req, err := http.NewRequest("POST", remoteUrl, bytes.NewBuffer([]byte(body)))
    req.Header = headers
    if err != nil {
        return "", fmt.Errorf("failed to make request: %s", err)
    }
    res, err := client.Do(req)
    if err != nil {
        return "", fmt.Errorf("failed to do request: %v", err)
    }
    defer res.Body.Close()

    b, err := io.ReadAll(res.Body)
    if err != nil {
        return "", fmt.Errorf("failed to read response body: %v", err)
    }

    var rjson map[string]any
    err = json.Unmarshal(b, &rjson)
    if err != nil {
        return "", fmt.Errorf("failed to unmarshal response body: %v", err)
    }

    return rjson["access_token"].(string), nil
}
```

After the response is received, the access token has to be extracted from the JSON and then cast to a string. We should now be able to return this token to make requests to other microservices.

### Putting It All Together To Execute

After implementing the entire flow, all we need to do now is call the functions and set a variable. Don't forget to set the endpoint URL strings to point to the appropriate endpoints.

```go
var client OAuthClient
_, err = client.CreateOAuthClient("http://hydra:4445/admin/clients")
if err != nil {
    log.Fatalf("failed to register OAuth client: %v", err)
}
_, err = client.AuthorizeOAuthClient("http://hydra:4445/oauth2/auth")
if err != nil {
    log.Fatalf("failed to authorize OAuth client: %v", err)
}
accessToken, err = client.PerformTokenGrant("http://hydra:4444/oauth2/token")
if err != nil {
    log.Fatalf("failed to fetch token from authorization server: %v", err)
}
log.Printf("Access Token: %v\n", accessToken)
```

Running this should print the access token if everything worked correctly. 

## Conclusion

And that's all there is to it! There's still some cleaning up to do and improvements to be made to the code presented above, but this gets the job done. Keep in mind that it should not be necessary to have to create and authorize another client to receive another token after each one expires unless you unregister it. Also, it may be a good idea to control when the microservice is requesting a new token such as before making a request and receiving a 401 response. Anyways, these are just some of the considerations to think about and maybe cover in a future post.

If you're interested in using cloud-like design patterns for the next generation of HPC System Management, we'd love to hear from you.  You can reach us through our [public Slack instance](https://openchami.org/slack) or [Github](https://github.com/openchami).
