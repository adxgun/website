---
title: "Creating Docker Registry Token Authentication Server with Go"
date: 2020-02-19 00:00:00 +0000
draft: false
---

Recently, I was working on a project that uses a private docker registry to store docker images produced by users. The access to these images needs to be controlled so that user `foo` MUST not be able to access(pull/push) images that belongs to user `bar` . Also, a user should be able to authenticate with the private docker registry from their local or remote development machine with the famous docker login command, additionally users should be able to perform basic docker operations — docker push, pull etc with proper authentication and authorization. This is similar to Google cloud’s grc.io container registry.

## The Problem

You can easily get up and running with the [registry docker image,](https://hub.docker.com/_/registry) by running the command below, you’ll have a docker registry running on your machine:

`docker run -d -p 5000:5000 --restart always --name registry registry:2`

Boom! docker registry is up and running on localhost:5000 . But this is limited because of the following reasons

1. If this were to be on a cloud VM/server, anyone with an access to the host IP would be able to pull and push images to our precious private docker registry.

2. You can take it a step further by configuring the registry to use a htpasswd file for authentication. By default, docker registry uses HTTP basic authentication to authenticates with the registry, the attached username and password would be compared against the values in the htpasswd file and if matches, all access would be granted to the client. As you can imagine, this is not what we want. Remember, we want each user to be able to authenticate individually, we also want different access level for these users, e.g we might want user foo to only be able to pull images while we might want user bar to be able to push and pull images.

## The Solution

One of the methods of authenticating with a registry server is token method, where, according to a specification that can be found [here,](https://docs.docker.com/registry/spec/auth/) we can create a custom, trusted token authentication server. The job of this token server is very specific, respond to successful authentication and authorization requests with a specially crafted JWT token, the documentation on how to create this token can be found [here](https://docs.docker.com/registry/spec/auth/jwt/).

The question here now is: How can we achieve our goal by using this token authentication method.
> The solution we’re building is programming language agnostic because of the specification we’re building on-top, although Go programming language is used for this example, you can easily adapt the solution to your favourite programming language.

Note: This post assumed you have the following installed on your machine.

* [Go](https://golang.org/doc/install)

* [Docker](https://docs.docker.com/install/)

* [docker-compose](https://docs.docker.com/compose/install/)

Firstly, let’s configure a bare minimum docker registry server using docker-compose

```yaml
version: "3"
services:
  registry:
    restart: on-failure
    image: registry:2
    ports:
      - 5010:5000
```
When you run docker-compose up , a docker registry will start running on localhost:5010 . Note: i choose port :5010 for my new docker registry, you can use any available port on your machine.
Let’s perform some operations to make sure our local docker registry works as expected.

```
$ docker pull ubuntu*
$ docker tag localhost:5010/ubuntu*
$ docker push localhost:5010/ubuntu*
```

The above commands pull an image from public docker registry(dockerhub) and then tag the image to include the url of our local registry, this instructs docker to push the image to the docker registry running at localhost:5010 when docker push is invoked, if all goes well, you should see the push progress indicator in your terminal, yay!!!

Now, let’s configure our new docker registry server to use token authentication. First thing we want to do is to create a SSL certificate because it is a requirement for token authentication to work, registry server will forcefully quit when it is configured to use token authentication and SSL certificate is not provided. For this purpose, we’ll generate a self-signed SSL certificate with [openssl](https://www.openssl.org/).
Before we continue, let’s create a basic project setup for our token authentication server. I am creating a new Go project, with go mod as my dependency manager.

* create project/directory/folder registry-auth

* create a sub-directory certs to store our self-signed SSL certificates and cd into this dir: cd registry-auth/certs

* generate certiticates 
$ openssl req -x509 -nodes -new -sha256 -days 1024 -newkey rsa:2048 -keyout RootCA.key -out RootCA.pem -subj "/C=US/CN=Registry Auth CA"
 $ openssl x509 -outform pem -in RootCA.pem -out RootCA.crt 
Both registry-auth/certs/RootCA.crt and registry-auth/certs/RootCA.key should be available now.

Now, we’ve sorted SSL certificate generation. Note: In production, a valid SSL certificate must be provisioned with [LetsEncrypt](https://letsencrypt.org/) or other similar services.
Let’s move on to configuring our docker registry server to use token authentication and the self-signed certificate.

```yaml
version: "3"
services:
  registry:
    restart: on-failure
    image: registry:2
    ports:
      - 5010:5000
    environment:
      - REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data
      - REGISTRY_AUTH=token
      - REGISTRY_AUTH_TOKEN_REALM=https://localhost:5011/auth
      - REGISTRY_AUTH_TOKEN_SERVICE=Authentication
      - REGISTRY_AUTH_TOKEN_ISSUER=Example Issuer
      - REGISTRY_AUTH_TOKEN_ROOTCERTBUNDLE=/mnt/local/certs/RootCA.crt
      - REGISTRY_HTTP_TLS_CERTIFICATE=/mnt/local/certs/RootCA.crt
      - REGISTRY_HTTP_TLS_KEY=/mnt/local/certs/RootCA.key
    volumes:
      - "${HOME}/mnt/auth/registry/data:/mnt/registry/data"
      - "./certs:/mnt/local/certs"
```

The configuration are passed through environment variables, you can also mount a config.yml file into the container but generally, configuring with environment variable is easier and straightforward. As you can see from the docker-compose.yml snippet above, we mounted our certs directory into the container so that we can use our SSL certificate to secure our docker registry server.

* REGISTRY_AUTH=token which instructs the registry to activate token authentication method.

* REGISTRY_AUTH_TOKEN_REALM=https://localhost:5011/auth — this is the url of our soon to be implemented token authentication server.

* REGISTRY_AUTH_TOKEN_SERVICE=Authentication — As we’ll soon see, this value is needed to create a valid JWT in the token authentication server.

* REGISTRY_AUTH_TOKEN_ISSUER=Example Issuer — this value is also needed by the token server to create a valid JWT. It should be your service name according to the authentication spec.

* REGISTRY_AUTH_TOKEN_ROOT_CERTBUNDLE — This is set to the path of the private key used to decode and validate a signed JWT. The public key of this private key is what token authentication server must use to sign its JWT token as we’ll soon see.

* REGISTRY_HTTP_TLS_CERTIFICATE and REGISTRY_HTTP_TLS_KEY which specify the SSL certificate and key respectively.

### Creating the token authentication server

First of all, we need to understand what happens when users make an attempt to access our private docker registry without authentication. Basically, if the registry is configured to use token authentication like we’re doing, the configured token server will be called with the following parameters https://${SAMPLE_REGISTRY}/auth?service=registry.docker.io&scope=repository:samalba/my-app:pull,push , the token server should first make an attempt to authenticate the user using the authentication credentials provided along with the request (HTTP basic authentication as of Docker 1.8), if the authentication succeeds, an authorization should follow using the scope parameter added to the request’s query parameters, the format of this scope is scope=repository:samalba/my-app:pull,push which contains basically the **type**, **repository name**, and **the requested actions. **These information should be use to determine if user should be given permission or not. Once it is decided whether to give users permission or not, authorization operation should return the list of permissions that should be granted the authorized user or an empty list should be return if the user is unauthorized to access the requested resources.

Let’s write some code to make all of these explanation makes sense.

```go
import (
    "github.com/docker/libtrust"
    "crypto/tls"
    "crypto/x509"
)
type tokenServer struct {
	privateKey libtrust.PrivateKey
	pubKey     libtrust.PublicKey
	crt, key   string
}
// newTokenServer creates a new tokenServer
func newTokenServer(crt, key string) (*tokenServer, error) {
	pk, prk, err := loadCertAndKey(crt, key)
	if err != nil {
		return nil, err
	}
	t := &tokenServer{privateKey: prk, pubKey: pk, crt: crt, key: key}
	return t, nil
}

// loadCertAndKey from filesystem
func loadCertAndKey(certFile, keyFile string) (libtrust.PublicKey, libtrust.PrivateKey, error) {
	cert, err := tls.LoadX509KeyPair(certFile, keyFile)
	if err != nil {
		return nil, nil, err
	}
	x509Cert, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		return nil, nil, err
	}
	pk, err := libtrust.FromCryptoPublicKey(x509Cert.PublicKey)
	if err != nil {
		return nil, nil, err
	}
	prk, err := libtrust.FromCryptoPrivateKey(cert.PrivateKey)
	if err != nil {
		return nil, nil, err
	}
}
```
The above code setups the basic structure of our token server. Lines 6-10 defines a structure to hold some important values. Lines 12-19 is a helper function to form a usable tokenServer structure, this function basically loads in the certificate data into go struct so that we can use them later on to sign the JWTs we’re going to be producing. Lines 22-40 is a helper function to load raw certificate data into libtrust.Privatekey and libtrust.Publickey .

```go
type Option struct {
	issuer, typ, name, account, service string
	actions []string // requested actions
}

type Token struct {
	Token       string `json:"token"`
	AccessToken string `json:"access_token"`
}

func (srv *tokenServer) createToken(opt *Option, actions []string) (*Token, error) {
	// sign any string to get the used signing Algorithm for the private key
	_, algo, err := srv.privateKey.Sign(strings.NewReader("AUTH"), 0)
	if err != nil {
		return nil, err
	}
	header := token.Header{
		Type:       "JWT",
		SigningAlg: algo,
		KeyID:      srv.pubKey.KeyID(),
	}
	headerJson, err := json.Marshal(header)
	if err != nil {
		return nil, err
	}
	now := time.Now().Unix()
	exp := now + time.Now().Add(24*time.Hour).Unix()
	claim := token.ClaimSet{
		Issuer:     opt.issuer,
		Subject:    opt.account,
		Audience:   opt.service,
		Expiration: exp,
		NotBefore:  now - 10,
		IssuedAt:   now,
		JWTID:      fmt.Sprintf("%d", rand.Int63()),
		Access:     []*token.ResourceActions{},
	}
	claim.Access = append(claim.Access, &token.ResourceActions{
		Type:    opt.typ,
		Name:    opt.name,
		Actions: actions,
	})
	claimJson, err := json.Marshal(claim)
	if err != nil {
		return nil, err
	}
	payload := fmt.Sprintf("%s%s%s", encodeBase64(headerJson), token.TokenSeparator, encodeBase64(claimJson))
	sig, sigAlgo, err := srv.privateKey.Sign(strings.NewReader(payload), 0)
	if err != nil && sigAlgo != algo {
		return nil, err
	}
	tk := fmt.Sprintf("%s%s%s", payload, token.TokenSeparator, encodeBase64(sig))
	return &Token{Token: tk, AccessToken: tk}, nil
}


func (srv *tokenServer) createTokenOption(r *http.Request) *Option {
	opt := &Option{}
	q := r.URL.Query()

	opt.service = q.Get("service")
	opt.account = q.Get("account")
	opt.issuer = "Sample Issuer" // issuer value must match the value configured via docker-compose

	parts := strings.Split(q.Get("scope"), ":")
	if len(parts) > 0 {
		opt.typ = parts[0] // repository
	}
	if len(parts) > 1 {
		opt.name = parts[1] // foo/repoName
	}
	if len(parts) > 2 {
		opt.actions = strings.Split(parts[2], ",") // requested actions
	}
	return opt
}
```
The above code made up the huge chunk of this whole solution. Lines 2-5 defined a struct Option{} to hold the docker registry request’s parameter, which are basically the values needed to create a valid JWT for our registry client. Lines 7-10 defined a Token{} struct to hold the value of the generated token. Lines 12-55 is a function that takes a Option{} and list of actions granted to authenticating user and then create a valid token according to [THIS SPECIFICATION,](https://github.com/docker/distribution/blob/1b9ab303a477ded9bdd3fc97e9119fa8f9e58fca/docs/spec/auth/jwt.md) the code comments are straightforward and should be easy to follow. And lastly, Lines 58-77 parses the request’s data and create an Option{} from it, this will allow us to easily have access to the information we need to create a valid token.

**Putting it all together.**

```go
func (srv *tokenServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	username, password, ok := r.BasicAuth()
	if !ok {
		http.Error(w, "auth credentials not found", http.StatusUnauthorized)
		return
	}
	// compare username and password against your datasets
	// our example only allows foo:bar
	if username != "foo" || password != "bar" {
		http.Error(w, "invalid auth credentials", http.StatusUnauthorized)
		return
	}
	// do authorization check
	opt := srv.createTokenOption(r)
	actions := srv.authorize(opt)
	tk, err := srv.createToken(opt, actions)
	if err != nil {
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}
	srv.ok(w, tk)
}

func (srv *tokenServer) authorize(opt *Option) []string {
	// do proper comparison to check for user's access
	// against the requested actions
	if opt.account == "foo" {
		return []string{"pull", "push"}
	}
	if opt.account == "bar" {
		return []string{"pull"}
	}
	// unauthorized, no permission is granted
	return []string{}
}

func (srv *tokenServer) run() error {
	addr := fmt.Sprintf(":%s", os.Getenv("PORT"))
	http.Handle("/auth", srv)
	return http.ListenAndServeTLS(addr, srv.crt, srv.key, nil)
}
```
`tokenServer` implements http.Handler function so that we can handle authentication and authorization requests from our private docker registry. The first thing we did was retrieve username and password from the request, as expected we immediately return http 401 error if this values are absent. We also did a static comparison to simulate real life authentication, in production you would normally compare these authentication credentials against a real datastore. And then we went ahead to extract Option{} out of our http request, we then do a dummy authorization by passing opt to a fake authorize function. Again, in real life or production scenario, authorize function would work according to your business logic. And finally, we generate our token using the list of authorized actions returned from calling authorize function. Lines 37-41 setup an https server and therefore our token authentication server is read to issue out valid JWT tokens.

### **Containerizing the token authentication server**

We need to package our token authentication server into a container so that we can run it along the docker registry in a simple docker-compose.yml file.

```go
FROM alpine:3.2
RUN apk update && apk add --no-cache ca-certificates
ADD . /app
WORKDIR /app
RUN chmod +x /app/sample-auth
ENTRYPOINT [ "/app/sample-auth" ]
```
We need to create a bash file, we’re naming it build.sh , it’s just a simple file to group our command so that we won’t need to be repeating commands every single time.
```shell script
#!/bin/bash
# Generate a random uuid to use as a docker tag
NEW_UUID=$(cat /dev/urandom | LC_CTYPE=C tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
# build binary
export GOOS=linux && go build -o sample-auth main.go
# build docker image
docker build -t "sample-auth" .
# tag image
docker tag sample-auth localhost:5010/sample-auth:${NEW_UUID}
# push image to registry running at localhost:5010
docker push localhost:5010/sample-auth:${NEW_UUID}
```

Your final docker-compose.yml file should look like the one pasted below —

```yaml
version: "3"

services:
  sample-server:
    build: ./
    container_name: sample-server
    restart: on-failure
    environment:
      - PORT=5008
    ports:
      - 5011:5008
    volumes:
      - "./certs:/mnt/certs"

  docker-registry:
    restart: always
    image: registry:2
    ports:
      - 5010:5000
    environment:
      - REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY=/data
      - REGISTRY_AUTH=token
      - REGISTRY_AUTH_TOKEN_REALM=https://localhost:5011/auth
      - REGISTRY_AUTH_TOKEN_SERVICE=Authentication
      - REGISTRY_AUTH_TOKEN_ISSUER=Sample Issuer
      - REGISTRY_AUTH_TOKEN_ROOTCERTBUNDLE=/mnt/local/certs/RootCA.crt
      - REGISTRY_HTTP_TLS_CERTIFICATE=/mnt/local/certs/RootCA.crt
      - REGISTRY_HTTP_TLS_KEY=/mnt/local/certs/RootCA.key
    volumes:
      - "${HOME}/mnt/auth/registry/data:/mnt/registry/data"
      - "./certs:/mnt/local/certs"
```
Use docker-compose upstart up the app, both registry and the token authentication server should start.

**Testing our implementation**
On first try, the push should be rejected anddocker client should force you to authenticate. Use foo and bar for your username and password respectively and you should get a Login Succeeded response after which you can now push and pull images from our new docker registry. Voila!

Side note: I put together a simple package that does most of the work describes here. If you’re interested, [it is here on my Github,](https://github.com/adigunhammedolalekan/registry-auth) also the code written in this post can be found [HERE](https://github.com/adigunhammedolalekan/secure-docker-registry)

Feel free to DM me on [Twitter](https://twitter.com/L3kanAdigun) if there’s any issue you want to point out or if there’s any way i can help. Happy coding!
