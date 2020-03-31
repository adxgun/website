---
title: "Golang Application on Kubernetes"
date: 2020-03-14 00:00:00 +0000
draft: false
---

# Golang Applications on Kubernetes
This post is a complete walk-through of how to deploy a monolithic Go web application in a Kubernetes cluster, how to attach a domain name so that it can be publicly accessible and finally, how to secure it with `LetsEncrypt's https and cert-manager`. Lets ride!

### More About Kubernetes
Kubernetes is a portable, extensible, open-source platform for managing containerized workloads and services, that facilitates both declarative configuration and automation. It has a large, rapidly growing ecosystem. Kubernetes services, support, and tools are widely available. Containers are a good way to bundle and run your applications. In a production environment, you need to manage the containers that run the applications and ensure that there is no downtime. For example, if a container goes down, another container needs to start. Wouldn’t it be easier if this behavior was handled by a system?

That’s how Kubernetes comes to the rescue! Kubernetes provides you with a framework to run distributed systems resiliently. It takes care of scaling and failover for your application, provides deployment patterns, and more. For example, Kubernetes can easily manage a canary deployment for your system. [Find out more about Kubernetes](https://kubernetes.io/docs/concepts/overview/what-is-kubernetes/)

### Example Application
I put together an example Go application. It's a dead-simple key-value store app backed by a redis database. I have chosen `redis database` in order to show how to setup and connect to an external storage service from inside a web application when both are running in the same Kubernetes cluster. The example application contains three endpoints, `/set` to set a value in the backing redis store, `/get` to get the stored value and `/status` to check the status or health of the application. The example app code is hosted [here on github](https://github.com/adigunhammedolalekan/go-kubernetes-app).

#### Prerequisites or tools required
This post assumes you have `Docker & Kubernetes` installed. It also assumes you have access to a `kubernetes cluster(Local or Cloud)` and Kubernetes management tool like `kubectl`. I am going to be using Docker Desktop for Mac `Docker Desktop (v 2.1.0.4)` .

###  Deploying Redis
Kubernetes has support for `deployment`, where you can define a deployment spec and Kubenetes will make sure your deployment is running up to the standard of the spec you defined. Kubernetes deployment is more useful for stateless applications. What would be more suitable for a stateful application -- e.g databases or applications that needs their data to be persisted between container restarts and rescheduling, is Statefulset. Basically, the major difference between `Statefulset` and `deployment` is, Statefulset remembers its `state` after restarts or rescheduling, therefore container or application data is not lost when they crash whereas deployment is more lightweight and its mostly used for application or container that can rebuild it data from backend systems.

Let's deploy our `redis` database with a kubernetes `Statefulset`. Create a `statefulsets.yml` and paste the following content.
```yaml 
apiVersion: apps/v1  
kind: StatefulSet  
metadata:  
  name: redis-store  
spec:  
  serviceName: "kv-redis-service"  
  replicas: 1  
  selector:  
    matchLabels:  
      app: kv-redis-service  
  template:  
    metadata:  
      labels:  
        app: kv-redis-service  
    spec:  
      containers:  
        - name: redis-store  
          image: redis:latest  
          ports:  
            - containerPort: 6379  
              name: tcp-port  
          volumeMounts:  
            - name: redis-volume  
              mountPath: /var/redis/data  
              subPath: redis  
  volumeClaimTemplates:  
    - metadata:  
        name: redis-volume  
      spec:  
        accessModes: [ "ReadWriteOnce" ]    
        resources:  
          requests:  
            storage: 4Gi
```
And then run, `$ kubectl apply -f statefulsets.yml`
You should get a response like this: `statefulset.apps/redis-store created`

Run `$ kubectl get pods` to verify that statefulset pod is running
```bash
NAMESPACE       NAME                                        READY   STATUS             RESTARTS   AGE
default         redis-store-0                               1/1     Running            0          3m3s

```
If you get the above response, great! We're on the right track, if not, check the steps and make sure you have not missed anything.
Next step, we need to be able to connect to our new redis backend, we will use kubernetes `Service` for this purpose. We want to expose our redis on its usual port `6379` in a `ClusterIP` type service so that other pods in our cluster can connect to it. Create a `services.yml` file and paste the following:

```yaml
apiVersion: v1  
kind: Service  
metadata:  
  name: kv-redis-service  
  labels:  
    app: kv-redis-service  
spec:  
  type: ClusterIP  
  ports:  
    - name: http-port  
      port: 6379  
      protocol: TCP  
      targetPort: 6379  
  selector:  
    app: kv-redis-service
```
Run `$ kubectl apply -f services.yml` and you should get a response like below:
`service/kv-redis-service created` Then run, 
```bash
$ kubectl get svc
NAME                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
kv-redis-service      ClusterIP   10.107.7.35      <none>        6379/TCP   77s
```
Great! Our service is up. Now, the applications running in this cluster can connect to our new redis using the url `kv-redis-service:6379`

### Deploying the application
We need to create a kubernetes `deployment` for our `key-value store` application. A docker image is available on public [dockerhub](https://hub.docker.com/repository/docker/dockadigun/kv-app) , you can also create your own image from the example repository.
To create deployment for our application, create a `deployments.yml` file paste the below content

```yaml
apiVersion: apps/v1  
kind: Deployment  
metadata:  
  name: kv-app  
  labels:  
    web: app-service  
spec:  
  replicas: 1  
  selector:  
    matchLabels:  
      web: app-service  
  template:  
    spec:  
      containers:  
        - name: kv-app-container  
          image: dockadigun/kv-app 
          ports:  
            - containerPort: 7002  
              protocol: TCP  
              name: access-port  
          env:  
            - name: PORT  
              value: "7002"  
	  - name: REDIS_HOST  
            value: "kv-redis-service:6379"  
  imagePullPolicy: Always  
    metadata:  
      labels:  
        web: app-service
```
As you can see from the above, we're passing some values to our application through the container's environment variable, These variables are `PORT` - The port on which the application http service will run on and `REDIS_HOST` which is the accessible address for our previously created redis service. After we've defined our deployment manifest, we need to apply it using kubectl. Run `$ kubectl apply -f deployments.yml` , you should get a response like this - `deployment.apps/kv-app created`, run `$ kubectl get pods -o wide` to check the status of our new deployment.
```bash
$ kubectl apply -f deployments.yml
deployment.apps/kv-app created

$ kubectl get pods
NAME                     READY   STATUS    RESTARTS   AGE
kv-app-d584954bf-6xv4r   1/1     Running   0          3m13s

```
If you get a response similar to the above, Yay! Our application is running. Next task is to expose this deployment to a service so that we can access it publicly. We will be exposing the deployment through a `ClusterIP` service and then we will use `Nginx Ingress Controller` to route or load-balance the incoming traffic into our deployment.
The first step is creating a `ClusterIP` service, we've understood that `ClusterIP` service creates a network that can only be accessible within the cluster. To create the service, append the below content to `services.yml`

```yaml
---  
apiVersion: v1  
kind: Service  
metadata:  
  name: app-service  
  labels:  
    web: app-service  
spec:  
  type: ClusterIP  
  ports:  
    - name: http-port  
      port: 7002  
      protocol: TCP  
      targetPort: 7002  
  selector:  
    web: app-service
``` 
Then, run `$ kubectl apply -f services.yml`, you should get a message `service/app-service created` as part of your response and then run `$ kubectl get svc` to see all created services.

```bash
$ kubectl apply -f services.yml
service/app-service created

$ kubectl get svc
NAME                  TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
app-service           ClusterIP   10.102.142.208   <none>        7002/TCP   55s
kv-redis-service      ClusterIP   10.107.7.35      <none>        6379/TCP   31m
```
Now, we have `app-service` which exposes our `kv-app` deployment and a `kv-redis-service` which exposes the redis server our app is connecting to for data storage. Few more steps and we will have a world-class service that could scale from 1 to 1000s replicas in a time of crises :-)

### Installing and setting up NGINX Ingress Controller
NGINX Ingress controller is built around the [Kubernetes Ingress resource](http://kubernetes.io/docs/user-guide/ingress/), using a [ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#understanding-configmaps-and-pods) to store the NGINX configuration. As i mentioned above, we'll be using NGINX ingress controller to route or load-balance requests to our `kv-app` service. We need to install Nginx Ingress Controller in our cluster. Installation steps varies depending on the environment or cloud platform that the cluster is running on. Here, i am running Docker Desktop for Mac which includes a single node local kubernetes cluster, i am going to go ahead and install nginx ingress controller, you can follow my steps if you're on Mac or use [this link](https://kubernetes.github.io/ingress-nginx/deploy/#provider-specific-steps) to install a specific one for your environment or platform. Don't worry, it is very straight-forward. Firstly, we need to install components that are generic to all environments or platforms.
Run 
```bash
$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/mandatory.yaml
```
this command will install all the required prerequisites for nginx ingress controller, and then you will need to run the command below if you're on Mac or use the link above to run the right command for your environment. 
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/nginx-0.30.0/deploy/static/provider/cloud-generic.yaml
``` 
the above command creates a `LoadBalancer` service using your provider's underlying resources for creating a `LoadBalancer`. To check if all installation goes well, run the bellow command and compare the responses to what i have here.
```bash
$ kubectl get svc -n ingress-nginx
NAME            TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx   LoadBalancer   10.103.137.101   localhost     80:32727/TCP,443:31170/TCP   1m

```
If you're running Kubernetes in a cloud platform, value of `EXTERNAL_IP` must be the value of the `LoadBalancer's IP address` service created for Nginx Ingress Controller, technically, your service should accessible through this IP address once Nginx Ingress controller transitioned to `RUNNING` state. Also, run `kubectl get pods -n ingress nginx` to verify that nginx pod is running

```bash
$ kubectl get pods -n ingress nginx   
NAME                                        READY   STATUS    RESTARTS   AGE
nginx-ingress-controller-7fbc8f8d75-lm6gd   1/1     Running   1          10m
```
You should have a response similar to the above. Now, we're ready to access our app. Just one more step away.

### Creating Ingress resources
We need to create ingress resources that defines how we want our apps to be routed. Create an `ingress.yml` file and paste the below content

```yaml
apiVersion: networking.k8s.io/v1beta1  
kind: Ingress  
metadata:  
  name: kv-ingress  
  annotations:  
    kubernetes.io/ingress.class: "nginx"    
spec:  
  rules:  
    - host: "example.kv" # or a registered domain
  http:  
        paths:  
          - backend:  
              serviceName: app-service  
              servicePort: 7002  
  # set default backend
  backend:  
    serviceName: app-service  
    servicePort: 7002
```
Run `$ kubectl apply -f ingress.yml`  and verify that ingress resource is created by running `$ kubectl get ingress`, the response should be similar to this

```bash
$ kubectl get ingress
NAME          HOSTS        ADDRESS     PORTS     AGE                                                    
proxy-ingress example.kv   localhost   80, 443   10d
```

If you have a registered domain name and you're not running a local kubernetes cluster, you can create an `A` record pointing to the `EXTERNAL-IP` of our nginx ingress service and you'll be able to access the service directly through your registered domain name once the DNS records is propagated(takes ~5mins). If you're running a local cluster, we can do the same thing locally by modifying system hosts records. Go to terminal and run `nano /etc/hosts` and append `127.0.0.1 example.kv` to the end of the file, save and close. 

### Testing 
Curling `curl http://example.kv/set?key=key&value=value` should respond with a `200 OK` http status code. And, that's it. We're done.

### Adding https with LetsEncrypt and `cert-manager`
`Note: This step is only applicable to readers that are not running local kubernetes, have a registered domain and have an A record pointing to the EXTERNAL-IP of ingress-nginx service LoadBalance`

We can add free, automated certificate issuing and management to our service so that we're always running securely, `cert-manager` and `LetsEncrypt` can help us achieve this. Firstly, we need to install `cert-manager` components. The way that i've found easiest is by applying [this](https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager.yaml) manifest. 
```bash
$ kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.14.0/cert-manager.yaml
```
This will install `cert-manager` into your cluster, be it local or cloud based. Check for successful installation by running 
```bash 
$ kubectl get pods -n cert-manager
NAME                                       READY   STATUS    RESTARTS   AGE
cert-manager-5c6866597-zw7kh               1/1     Running   0          2m
cert-manager-cainjector-577f6d9fd7-tr77l   1/1     Running   0          2m
cert-manager-webhook-787858fcdb-nlzsq      1/1     Running   0          2m
```
If you get the above response, Congratulations. `cert-manager` is running successfully.

### Creating Issuer and Certificate object
You can find more information about `Issuer` and `Certificate` on [cert-manage website](https://cert-manager.io/docs/concepts). Basically, all we need to do to activate automated https certificate creation and maintenance is a `Issuer` object , a `Certificate` object and a little modification in our `ingress.yml` file and we're set. Create a `tls.yml` and append the following contents.

```yaml
apiVersion: cert-manager.io/v1alpha2  
kind: ClusterIssuer  
metadata:  
  name: cluster-issuer  
  namespace: cert-manager  
spec:  
  acme:  
    server: https://acme-staging-v02.api.letsencrypt.org/directory  
  #server: https://acme-v02.api.letsencrypt.org/directory  
    email: youremail@gmail.com  
    privateKeySecretRef:  
      name: certs-key  
    solvers:  
    - http01:  
        ingress:  
          class: nginx  
---  
apiVersion: cert-manager.io/v1alpha2  
kind: Certificate  
metadata:  
  name: tls-cert  
  namespace: cert-manager  
spec:  
  secretName: certs-secret  
  issuerRef:  
    name: cluster-issuer  
    kind: ClusterIssuer  
  commonName: example.kv # or your host/domain name
  dnsNames:  
    - example.kv # or your host/domain name
```
The above `yaml` creates an issuer and a certificate object which would be used by `cert-manager` to create a certificate for `example.kv`. We can check if our certificate is ready by running 
```bash
$ kubectl get certs -n cert-manager
NAME        READY   SECRET              AGE
tls-certs   True    certs-secret        10m
```
When the value of `READY` transitioned to `true`, your certificate is ready to be used.
Let's modify our ingress resource to consume the new certificate we just created.
```yaml
apiVersion: networking.k8s.io/v1beta1  
kind: Ingress  
metadata:  
  name: proxy-ingress  
  annotations:  
    kubernetes.io/ingress.class: "nginx"  
    cert-manager.io/cluster-issuer: "cluster-issuer"  
spec:  
  tls:  
    - hosts:  
        - "example.kv" # or your host/domain name
  secretName: certs-secret  
  rules:  
    - host: "example.kv" # or your host/domain name  
  http:  
        paths:  
          - backend:  
              serviceName: app-service  
              servicePort: 7002  
  backend:  
    serviceName: app-service  
    servicePort: 7002
```
Notice the new annotation `cert-manager.io/cluster-issuer: "cluster-issuer"` and the `spec.tls` value. This tells Nginx Ingress Controller to look for a certificate and apply it on the internal nginx proxy. Curling `curl https://example.kv/set?key=key&value=value` must still have the same response as we've done earlier. And then, we're done. 

Thanks for following.
