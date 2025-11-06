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

{{< blog-cta >}}
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

If you're interested in using cloud-like design patterns for the next generation of HPC System Management, we'd love to hear from you. You can reach us through our [Slack](https://openchami.org/slack) or [GitHub](https://github.com/OpenCHAMI).

{{< blog-cta >}}
