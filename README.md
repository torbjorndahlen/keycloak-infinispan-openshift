# keycloak-infinispan-openshift
Demo on deploying a cross DC replication with Red Hat SSO and a cross-DC replicated Infinispan cluster and an external PostgreSQL DB.

A new RHSSO image is built by adding configuration scripts in the 'extensions' directory containing PostgreSQL DB configuration and Infinispan Hotrod client configuration and replicated/distributed caches.

Two OpenShift 4.x clusters, here called C1 and C2 are used.

Red Hat SSO version: 7.4

Red Hat Data Grid version: 8.1

## Preparations

### Create project 

Create the project 'rhsso-rhdg' in C1 and C2. Note that the project name must be identical in both clusters.

### Deploy Postgresql 

Deploy PostgreSQL DB in C1 only. The RHSSO instance in C2 will also use this DB. In a full cross-DC set up each cluster would have its own DB with DB-replication set up between them. Here we're just using a single DB for simplicity.

In this example the DB name is 'keycloak', username 'keycloak' and password 'password'

### Create service accounts and tokens 

For Infinispan cross-DC communication tokens are required for authentication.

Create a service account 'site1' in C1.

$ oc create sa site1

Add cluster-admin role to the service account (Note: likely a 'view' role will be sufficient).

$ oc policy add-role-to-user cluster-admin system:serviceaccount:rhsso-rhdg:site1

Retrieve the service account token

$ oc sa get-token site1 > site1-token.txt

Repeat the same steps for C2, using 'site2' as name for the service account.

### Exchange tokens between the clusters

Log in to C2 and generate a secret with the token from site1

$ oc create secret generic site1-token --from-literal=token=$(cat site1-token.txt)

Log in to C1 and generate a secret with the token from site2

$ oc create secret generic site2-token --from-literal=token=$(cat site2-token.txt)
    

## Deploy Infinispan 

Deploy an Infinispan Cluster in project 'rhsso-rhdg' in C1 and in C2 using the Data Grid operator with the following CR. Note that the project name must be identical in both clusters.

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
                name: site1
            locations:
                - name: site2
                secretName: site2-token
                url: 'openshift://<Kubernetes API endpoint for C2>:6443'
                - name: site1
                secretName: site1-token
                url: 'openshift://<Kubernetes API endpoint for C1>:6443'
        type: DataGrid



Notes: 

* metadata.name and metadata.namespace must be identical in C1 and C2.
* spec.expose.hostname can be omitted 
* service.sites.locations.url must be the Kubernetes API endpoint (without the /api path, for example api.cluster-aa58.aa58.sandbox1151.opentlc.com), which is where for example 'oc login' is sent.


### Create the Infinispan Caches required by RHSSO

Navigate to the Infinispan console and create the caches using the XML definition, for example

    <infinispan>
        <cache-container>
            <replicated-cache name="work">
                <encoding media-type="application/x-protostream"/>
                <backups>
                    <backup site="site2" strategy="SYNC">
                        <take-offline min-wait="120000"/>
                    </backup>
                </backups>
            </replicated-cache>
        </cache-container>
    </infinispan>


Also create the required caches in C2 using identical cache names.


### Create the Infinispan keystore, JGROUPS key and truststore

Do these steps in both C1 and C2:

    $ oc get secret rhsso-rhdg-infinispan-cert-secret -o jsonpath='{.data.tls\.crt}' | base64 --decode > tls.crt
    $ openssl req -new -newkey rsa:4096 -x509 -keyout xpaas.key -out xpaas.crt -days 365 -subj "/CN=xpaas-sso-demo.ca"
    $ keytool -genkeypair -keyalg RSA -keysize 2048 -dname "CN=secure-sso-sso-app-demo.openshift.example.com" -alias jboss -keystore keystore.jks
    $ keytool -certreq -keyalg rsa -alias jboss -keystore keystore.jks -file sso.csr
    $ openssl x509 -req -CA xpaas.crt -CAkey xpaas.key -in sso.csr -out sso.crt -days 365 -CAcreateserial
    $ keytool -import -file xpaas.crt -alias xpaas.ca -keystore keystore.jks
    $ keytool -import -file sso.crt -alias jboss -keystore keystore.jks
    $ keytool -genseckey -alias secret-key -storetype JCEKS -keystore jgroups.jceks
    $ keytool -import -file xpaas.crt -alias xpaas.ca -keystore truststore.jks

### Create secret and link to service account

    $ oc create secret generic sso-app-secret --from-file=keystore.jks --from-file=jgroups.jceks --from-file=truststore.jks
    $ oc secrets link default sso-app-secret

## Build and push modified RHSSO image

docker build -t torbjorndahlen/keycloak-infinispan:latest .

docker push torbjorndahlen/keycloak-infinispan:latest

## Deploy modified RHSSO image in OpenShift in project rhsso-rhdg

Note: It's easiest to deploy RHSSO and RHDG in the same namespace. Then, RHSSO could just use the service name (e.g. infinispan) to access RHDG.


oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest -e SSO_ADMIN_USER=admin -e SSO_ADMIN_PASSWORD=secret -e INFINISPAN_USERNAME=developer -e INFINISPAN_PASSWORD=b913dv5zSPWhtdAy -e INFINISPAN_SERVERNAME=infinispan -e JAVA_OPTS_APPEND=-Djboss.site.name=site1
 

oc create route edge secure-keycloak-infinispan --service=keycloak-infinispan --port=8080


Note that the INFINISPAN_USERNAME and INFINISPAN_PASSWORD values should be fetched from the Secret generated by Infinispan

### Import truststore into RHSSO from RHDG



## TODO

### The remaining caches can be modified in the same way as the clientSessions cache:

                <distributed-cache name="sessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>
                <distributed-cache name="actionTokens" owners="${env.CACHE_OWNERS_COUNT:2}">
                <distributed-cache name="offlineSessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>               
                <distributed-cache name="offlineClientSessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>
                <distributed-cache name="loginFailures" owners="${env.CACHE_OWNERS_COUNT:1}"/>




### Deploy RHDG cross-DC with single RHSSO instance in each DC using the same PostgreSQL DB located in one of the clusters

Add an environment variable, DB_CONNECTION_URL, to the actions.cli datasources config.


#### Use Case:

1. Log in user1 in cluster1
2. Login user2 in cluster2
3. View the Sessions menu in each RHSSO instance
4. There should be 2 sessions visible in each RHSSO instance



### Deploy 2 RHSSO instances in one OCP cluster and verify that both sees the same RHDG cache



## PostgreSQL

    > oc rsh <postgresql-pod>
    $ psql
    postgres# \l /** list DBs */    
    postgres# \c keycloak /** connect to DB keycloak */
    keycloak=# \dt /** list tables */
    keycloak=# SELECT name FROM REALM;

## References

    (https://access.redhat.com/solutions/3402171)
    (https://access.redhat.com/documentation/en-us/red_hat_data_grid/8.1/html/running_data_grid_on_openshift/backup_sites)
    (https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html/server_installation_and_configuration_guide/operating-mode#assembly-setting-up-crossdc)
    (https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html-single/red_hat_single_sign-on_for_openshift_on_openjdk/index#Configuring-Keystores)