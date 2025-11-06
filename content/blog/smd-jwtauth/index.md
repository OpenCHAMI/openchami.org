+++
title = 'Implementing Authn/Authz in OpenCHAMI Microservices'
date = 2024-01-24T10:24:44-05:00
draft = false
categories = ['LANL', 'Development']
contributors = ["David J. Allen (LANL)"]
+++

Since we're pushing to use OpenCHAMI for Supercomputing Institute 2024, we needed to have both authentication and authorization implemented in our microservices to only allow students to access hardware assigned to them. Therefore, we found an off-the-shelf OAuth2 and OIDC implementation for handling this: [Ory Hydra](https://github.com/ory/hydra). We also had to make some *more* changes to SMD to inject middleware that made verifying the public key retrieved from the Hydra server trivial.

For this post, I will be referring to [this commit of our deployment recipes](https://github.com/OpenCHAMI/deployment-recipes/commit/a243ddfcbf5e40f709daa37167c41e4fc851662a) and [this commit of our custom SMD](https://github.com/OpenCHAMI/smd/commit/802123c620559ac365b8855b8a5540b0aaf5e4b8).

## Replacing the HTTP Router

To get things working without too much fuss, we first had to replace the gorilla package with go-chi for its ability to inject middleware. This was a fairly straight-forward process which you can see in detail from the diff in [this commit]([Added middleware to verify JWTs in router · OpenCHAMI/smd@ba87b3f · GitHub](https://github.com/OpenCHAMI/smd/commit/ba87b3f62c3b1eb2ba07c767d739f8c9c7f3d7e2). The highlight of the change was mostly regarding the creation of routers:

```go
func (s *SmD) NewRouter(publicRoutes []Route, protectedRoutes []Route) *chi.Mux {
    router := chi.NewRouter()
    router.NotFound(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        s.Logger(http.NotFoundHandler(), "NotFoundHandler")
    }))
    if s.requireAuth {
        router.Group(func(r chi.Router) {
            r.Use(
                jwtauth.Verifier(s.tokenAuth),
                jwtauth.Authenticator(s.tokenAuth),
            )

            // Register protected routes
            for _, route := range protectedRoutes {
                ...
            }
        })

        // Register public routes
        for _, route := range publicRoutes {
            ...
        }

    } else {
        routes := append(publicRoutes, protectedRoutes...)
        // Only pubilc routes and no auth
        for _, route := range routes {
            ...
        }
    }
    ...
    return router
}
```

The code above was edited for brevity and to focus on the main points. The gist here is that we're now using `chi.NewRouter()` to create the router and then set up our [`jwauth`](https://github.com/go-chi/jwtauth) middleware using `jwtauth.Verifier` and `jwauth.Authenticator`. For this to work, we will need to obtain a JSON web token (JWT) to pass into the header of our HTTP request that we will get from Hydra. The middleware will intercept this header and try to verify the token before authorizing access to any protected resources. Further down we can also see that the `SmD` object now has a `s.requireAuth` variable that is set when a new optional `--require-auth` flag is passed to the CLI, which is disabled by default to maintain the original behavior. We are now able to set protected endpoints that require a valid JWT and signature to be able to access certain endpoint and resources. This was the first step to getting a microservice prepped for verifying tokens.

As a side note, changing the router did introduce a small bug that was caught by our integration tests with BSS. The bug was related to how parameters were being pulled from URL endpoints. Essentially, every endpoint with a URL parameter, such as `/Inventory/RedfishEndpoints/{xname}` and `/Inventory/ComponentEndpoints/{xname}`, were erroring out because the parameters was not being extracting property by chi, but it did not affect any of the other non-parameterized ones. Fortunately, the fix was simply to change a few lines of code in one file:

```go
// this is how it was done
vars := mux.Vars(r)
xname := base.NormalizeHMSCompID(vars["xname"])
// this is what is was changed to
xname := base.NormalizeHMSCompID(chi.URLParam(r, "xname"))
```

After making this change, the `go-chi` router worked exacty like it did before with no further issues.

## Setting Up Hydra and Getting a Token

JWTs are obtained by supplying credentials to an issuer. For this, we set up Hydra server in our deployment recipes for handling JWT creation and for making authentication requests. Hydra is a certified OAuth2 and OpenID connect implementation that has a bunch of handy features and is fairly easy to get up and running. The official website has a [5-minute, quick tutorial](https://www.ory.sh/docs/hydra/5min-tutorial) that is certainly worth a read. It covers how to configure and deploy a server using their quick start tools in details, but I will cover the relevant bits here. This mini-tutorial here, however, will by no means be comprehensive.

First, get Hydra either with `go get -d github.com/ory/hydra` or `git clone https://github.com/ory/hydra.git` and `cd` into that directory. To get the correct `access_token` format later when we perform a credentials grant, you'll have to add the following to your configuration file:

```yaml
strategies:
  access_token: jwt
```

By default, Hydra uses opaque token instead of using JWT encoded strings, which is advised not to do this [here](https://github.com/ory/hydra/blob/master/internal/config/config.yaml#L370) with the reasoning [here](https://www.ory.sh/docs/hydra/advanced#json-web-tokens). Next, assuming that docker-compose is installed, run the following to start the containers with Postgres:

```bash
docker-compose -f quickstart.yml \
    -f quickstart-postgres.yml \
    up --build
```

So far, so good. Now we will need to create an OAuth2 client, which we can create with the following:

```bash
client=$(docker-compose -f quickstart.yml exec hydra \
    hydra create client \
    --endpoint http://127.0.0.1:4445/ \
    --format json \
    --grant-type client_credentials)
```

We set the `client` variable so we can extract the `client_id` and `cilent_secret` using `jq`:

```bash
client_id=$(echo $client | jq -r '.client_id')
client_secret=$(echo $client | jq -r '.client_secret')
```

Now, we can get a token with the client ID and secret obtained above. We're going to use `curl` here instead of docker-compose like in the tutorial.

```bash
TOKEN=$(curl -s -k -u "$client_id:$client_secret" \
     -d grant_type=client_credentials \
     -d scope=openid \
     https://127.0.0.1:4444/oauth2/token \
)
# the token should look like this
#{"access_token":"ory_at_a59sQd0cK1etcqemS0YnZiw_IDW4UjtrA-ygI-sM4dk.udmBh1sM8HJ-lTGyGbO8SPMZQ6B6TOsm8-hTB9CWBig","expires_in":3599,"scope":"openid","token_type":"bearer"}
```

And voila! We have our token that we will use to make a HTTP request to a protected SMD endpoint as described in the above section.

## Accessing the Protected Endpoints

Now that we have the Hydra server and made the appropriate modifications to SMD, we should be able to make a request to SMD to access a protected endpoint. For this example, I will try to access the `/Inventory/RedfishEndpoints` endpoint both with and without the token to show what happens. First, we need to start the OpenCHAMI services with docker-compose:

```bash
docker compose -f ochami-services.yml -f ochami-krakend-ce.yml -f hydra.yml down --volumes && docker compose -f ochami-services.yml -f ochami-krakend-ce.yml -f hydra.yml up
```

Once the services are up, we can check to make sure SMD running with the `/service/ready` endpoint, which should not be protected:

```bash
curl http://localhost:27779/hsm/v2/service/ready
{"code":0,"message":"HSM is healthy"}
```

Try making a request to the `/Inventory/RedfishEndpoints`.

```bash
curl http://localhost:27779/hsm/v2/Inventory/RedfishEndpoints
no token found
```

Doing so now should result in a "no token found" response. We can use the token we created earlier with the request for authorization to this endpoint:

```bash
JWT=$(echo $TOKEN | jq -r .access_token')
curl http://localhost:27779/hsm/v2/Inventory/RedfishEndpoints -H 'Authorization: BEARER $JWT'
{"RedfishEndpoints":[]}
```

If everything works like it should, then you should see the normal response for that endpoint. Otherwise, if the token is no good, you should see a "token is unauthorized" indicating that SMD intercepted the token, but was unable to verify it with the issuer.

## Verifying Tokens with a JSON Web Key

To access protected endpoints shown above, SMD has to be able to verify with an issuer that the request contains a JWT with a valid signature. This is done by SMD fetching a JSON web key set (JWKS), iterating through the set, and passing a vaild key to the middeware authenticator where the magic happens underneath. The tricky part in all of this was figuring out how to extract the public key from the JWK:

```go
func (s *SmD) loadPublicKeyFromURL(url string) error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	set, err := jwk.Fetch(ctx, url)
	if err != nil {
		return fmt.Errorf("%v", err)
	}
	for it := set.Iterate(context.Background()); it.Next(context.Background()); {
		pair := it.Pair()
		key := pair.Value.(jwk.Key)

		var rawkey interface{}
		if err := key.Raw(&rawkey); err != nil {
			continue
		}

		s.tokenAuth = jwtauth.New(jwa.RS256.String(), nil, rawkey)
		return nil
	}

	return fmt.Errorf("failed to load public key: %v", err)
}
```

As you can see here, the raw key is deserialized to an interface and not something like a `rsa.PublicKey` like we might expect. That's because the key could also be deserialized as a `rsa.PrivateKey`, `ecdsa.PublicKey`, etc. Therefore, you'd have to know beforehand what the key should be when creating a new `*jwtauth.JWTAuth` object (in our case, a RS256 public key).

## So what's the Next Step?

That wraps up the main parts of implementing authentication and authorization into OpenCHAMI microservices. The next thing to do is to include roles and scopes to define who has access to what resource. Then afterwards, we'll have to revisit looking at integrating all of this with partitions and groups.


