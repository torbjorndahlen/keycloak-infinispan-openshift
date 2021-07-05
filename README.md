# keycloak-infinispan-openshift
Demo on deploying a cross DC replication with Red Hat SSO and a cross-DC replicated Infinispan cluster and an external PostgreSQL DB.

A new RHSSO image is built by adding configuration scripts in the 'extensions' directory containing PostgreSQL DB configuration and Infinispan Hotrod client configuration and replicated/distributed caches.

Two OpenShift clusters, here called C1 and C2 are deployed.

## Preparations

### Create project 

Create the project 'rhsso-rhdg' in C1 and C2 (tested with OpenShift 4.7). Note that the project name must be identical in both clusters.

### Deploy Postgresql 

Deploy PostgreSQL DB in C1 only. The RHSSO instance in C2 will use this DB. In a full cross-DC set up each cluster would have its own DB with DB-replication set up between them. Here we're just using a single DB for simplicity.

In this example the DB name is 'keycloak', username 'keycloak' and password 'password'

### Create service accounts and secrets 

For Infinispan cross-DC communication tokens are required for authentication.

Create a service account 'site1' in C1.

$ oc create sa site1

Add cluster-admin role to the service account (Note: likely a 'view' role will be sufficient).

$ oc policy add-role-to-user cluster-admin system:serviceaccount:rhsso-rhdg:site1

Retrieve the service account token

$ oc sa get-token site1 > site1-token.txt

Repeat the same steps for C2, using 'site2' as name for the service account.


    

### Infinispan deployed in OpenShift in project rhsso-rhdg (tested with RHDG 8.1)

See below for more details.

## Build and push modified RHSSO image

docker build -t torbjorndahlen/keycloak-infinispan:latest .

docker push torbjorndahlen/keycloak-infinispan:latest

## Deploy modified RHSSO image in OpenShift in project rhsso-rhdg


oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest -e SSO_ADMIN_USER=admin -e SSO_ADMIN_PASSWORD=secret -e INFINISPAN_USERNAME=developer -e INFINISPAN_PASSWORD=b913dv5zSPWhtdAy -e INFINISPAN_SERVERNAME=infinispan -e JAVA_OPTS_APPEND=-Djboss.site.name=site1
 

oc create route edge secure-keycloak-infinispan --service=keycloak-infinispan --port=8080


Note that the INFINISPAN_USERNAME and INFINISPAN_PASSWORD values should be fetched from the Secret generated y Infinispan


## Deploy Red Hat Data Grid with the Openshift Operator

Note: use RHDG v 8.1 with RHSSO 7.4

apiVersion: infinispan.org/v1
kind: Infinispan
metadata:
  name: infinispan
  namespace: rhsso-rhdg
spec:
  expose:
    type: Route
  logging:
    categories:
      org.infinispan: info
      org.jgroups: info
      org.jgroups.protocols.TCP: error
      org.jgroups.protocols.relay.RELAY2: fatal
  replicas: 1
  service:
    sites:
      local:
        expose:
          type: LoadBalancer
        name: site2
      locations:
        - name: site2
          secretName: site2-token
          url: 'openshift://api.cluster-f4d9.f4d9.example.opentlc.com:6443'
        - name: site1
          secretName: site1-token
          url: 'openshift://api.cluster-aa58.aa58.sandbox1151.opentlc.com:6443'
    type: DataGrid


Note: It's easiest to deploy RHSSO and RHDG in the same namespace. Then, RHSSO could just use the service name (e.g. infinispan) to access RHDG.

Note: hostname can be omitted in the CRD spec.expose

## TODO

### The remaining caches can be modified in the same way as the clientSessions cache:

                <distributed-cache name="sessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>
                <distributed-cache name="authenticationSessions" owners="${env.CACHE_OWNERS_AUTH_SESSIONS_COUNT:1}"/>
                <distributed-cache name="actionTokens" owners="${env.CACHE_OWNERS_COUNT:2}">
                <distributed-cache name="offlineSessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>               
                <distributed-cache name="offlineClientSessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>
                <distributed-cache name="loginFailures" owners="${env.CACHE_OWNERS_COUNT:1}"/>




### Deploy RHDG cross-DC with single RHSSO instance in each DC using the same PostgreSQL DB located in one of the clusters

#### Use Case:

1. Log in user1 in cluster1
2. Login user2 in cluster2
3. View the Sessions menu in each RHSSO instance
4. There should be 2 sessions visible in each RHSSO instance

### Import truststore into RHSSO from RHDG


### Deploy 2 RHSSO instances in one OCP cluster and verify that both sees the same RHDG cache



## PostgreSQL

    > oc rsh <postgresql-pod>
    $ psql
    postgres# \l /** list DBs */    
    postgres# \c keycloak /** connect to DB keycloak */
    keycloak=# \dt /** list tables */
    keycloak=# SELECT name FROM REALM;

## References

    https://access.redhat.com/solutions/3402171