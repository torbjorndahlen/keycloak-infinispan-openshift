# keycloak-infinispan-openshift
Demo on integrating Keycloak with an external Infinispan server and external PostgreSQL DB

A new RHSSO image is built by adding configuration scripts in the 'extensions' directory containing PostgreSQL DB configuration and Infinispan Hotrod client configuration and replicated/distributed caches.

## Prerequisites

### Created project rhsso-rhdg in OpenShift (tested with OpenShift 4.7)

### Postgres deployed in OpenShift in project rhsso-rhdg

In this example the DB name is 'keycloak'

### Infinispan deployed in OpenShift in project rhsso-rhdg (tested with RHDG 8.1)

See below for more details.

## Build and push modified RHSSO image

docker build -t torbjorndahlen/keycloak-infinispan:latest .

docker push torbjorndahlen/keycloak-infinispan:latest

## Deploy modified RHSSO image in OpenShift in project rhsso-rhdg


oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest -e SSO_ADMIN_USER=admin -e SSO_ADMIN_PASSWORD=secret -e INFINISPAN_USERNAME=developer -e INFINISPAN_PASSWORD=password -e INFINISPAN_SERVERNAME=infinispan -e JAVA_OPTS_APPEND=-Djboss.site.name=site1
 

oc create route edge secure-keycloak-infinispan --service=keycloak-infinispan --port=8080


Note that the INFINISPAN_USERNAME and INFINISPAN_PASSWORD values should be fetched from the Secret generated y Infinispan


## Deploy Red Hat Data Grid with the Openshift Operator

Note: use RHDG v 8.1 with RHSSO 7.4

Add the following to the CRD for RHDG:

    expose:

        host: infinispan-external-<namespace>.<openshift-cluster-domain>

        type: Route

    logging:

        categories:

        org.infinispan: trace

        org.jgroups: trace

    replicas: 1

    security:

        endpointEncryption:

        type: None

    service:

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

### Fix the JGROUPS config


### Deploy 2 RHSSO instances in one OCP cluster and verify that both sees the same RHDG cache



## PostgreSQL

    > oc rsh <postgresql-pod>
    $ psql
    postgres# \l /** list DBs */    
    postgres# \c keycloak /** connect to DB keycloak */
    keycloak=# \dt /** list tables */
    keycloak=# SELECT name FROM REALM;