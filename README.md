# keycloak-infinispan-openshift
Demo on deploying a cross DC replication with Red Hat SSO and a cross-DC replicated Infinispan cluster and an external PostgreSQL DB.

A new RHSSO image is built by adding configuration scripts in the 'extensions' directory containing PostgreSQL DB configuration and Infinispan Hotrod client configuration and replicated/distributed caches.

Two OpenShift 4.x clusters, here called C1 and C2 are used.

Red Hat SSO version: 7.4

Red Hat Data Grid version: 8.1

## Preparations

### Create project 

Create the project 'rhsso-rhdg' in C1 and C2:

    $ oc new-project rhsso-rhdg

Notes:
* The project name must be identical in both clusters

### Deploy Postgresql 

Deploy PostgreSQL DB in C1 only. The RHSSO instance in C2 will also use this DB. In a full cross-DC set up each cluster would have its own DB with DB-replication set up between them. Here we're just using a single DB for simplicity.

In this example the PostgreSQL DB name is 'keycloak' which is referred to in the data source connection-url in the actions.cli file.

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


Also create the clientSessions cache:

    <infinispan>
        <cache-container>
            <distributed-cache name="clientSessions">
                <encoding media-type="application/x-protostream"/>
                <backups>
                    <backup site="site2" strategy="SYNC">
                        <take-offline min-wait="120000"/>
                    </backup>
                </backups>
            </distributed-cache>
        </cache-container>
    </infinispan>


The remaining caches required by RHSSO are:

* sessions
* actionTokens
* offlineSessions              
* offlineClientSessions
* loginFailures

Use the same XML template as for clientSessions to create these.

Also create the required caches in C2 using identical cache names, however change the backup site to "site1".

## Deploy RHSSO

    Do these steps in both C1 and C2.

### Create the RHSSO keystore, JGROUPS key and truststore

    $ oc get secret signing-key -n openshift-service-ca -o jsonpath='{.data.tls\.crt}' | base64 --decode > xpaas.crt
    $ oc get secret signing-key -n openshift-service-ca -o jsonpath='{.data.tls\.key}' | base64 --decode > xpaas.key
    $ keytool -genkeypair -keyalg RSA -keysize 2048 -dname "CN=secure-keycloak-infinispan-rhsso-rhdg.apps.<Your OpenShift domain>" -alias jboss -keystore keystore.jks
    $ keytool -certreq -keyalg rsa -alias jboss -keystore keystore.jks -file sso.csr
    $ openssl x509 -req -CA xpaas.crt -CAkey xpaas.key -in sso.csr -out sso.crt -days 365 -CAcreateserial
    $ keytool -import -file xpaas.crt -alias xpaas.ca -keystore keystore.jks
    $ keytool -import -file sso.crt -alias jboss -keystore keystore.jks
    $ keytool -genseckey -alias secret-key -storetype JCEKS -keystore jgroups.jceks
    $ keytool -import -file xpaas.crt -alias xpaas.ca -keystore truststore.jks
    $ oc get secret infinispan-cert-secret -o jsonpath='{.data.tls\.crt}' | base64 --decode > tls.crt
    $ keytool -importcert -file tls.crt -keystore truststore.jks

Notes:
* For convenience RHSSO and RHDG are deployed in the same namespace. Then, RHSSO will just use the service name (e.g. infinispan) as remote-cache host name to access RHDG (see actions.cli).

### Create secret and link to service account

    $ oc create secret generic sso-app-secret --from-file=keystore.jks --from-file=jgroups.jceks --from-file=truststore.jks
    $ oc secrets link default sso-app-secret

### Build and push the modified RHSSO image

    $ docker build -t torbjorndahlen/keycloak-infinispan:latest .
    $ docker push torbjorndahlen/keycloak-infinispan:latest

### Alternative 1: Deploy the modified RHSSO image in OpenShift in project rhsso-rhdg

Do the following in both C1 and C2:

    $ oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest -e SSO_ADMIN_USERNAME=admin -e SSO_ADMIN_PASSWORD=secret -e INFINISPAN_USERNAME=developer -e INFINISPAN_PASSWORD=xoJZLSX37iV7BCDf -e INFINISPAN_SERVERNAME=infinispan -e DB_USERNAME=keycloak -e DB_PASSWORD=password -e JAVA_OPTS_APPEND=-Djboss.site.name=site1 -e HTTPS_SECRET="sso-app-secret" -e HTTPS_KEYSTORE="keystore.jks" -e HTTPS_NAME="jboss" -e HTTPS_PASSWORD="secret" -e HTTPS_KEYSTORE_DIR=/etc/eap-secret-volume -e JGROUPS_ENCRYPT_SECRET="sso-app-secret" -e JGROUPS_ENCRYPT_KEYSTORE="jgroups.jceks" -e JGROUPS_ENCRYPT_NAME="secret-key" -e JGROUPS_ENCRYPT_PASSWORD="secret" -e JGROUPS_ENCRYPT_KEYSTORE_DIR=/etc/jgroups-encrypt-secret-volume -e SSO_TRUSTSTORE="truststore.jks" -e SSO_TRUSTSTORE_PASSWORD="secret" -e SSO_TRUSTSTORE_SECRET="sso-app-secret" -e SSO_TRUSTSTORE_DIR=/etc/sso-secret-volume
 
Notes: 
* The INFINISPAN_USERNAME and INFINISPAN_PASSWORD values can be found in the Secret infinispan-generated-secret generated by the Operator
* Rename the jboss.site.name to site2 when deploying in C2


#### Create volumes with secrets

    $ oc set volume dc/keycloak-infinispan --add --name=eap-keystore-volume -m /etc/eap-secret-volume -t secret --secret-name=sso-app-secret --default-mode='0755'
    $ oc set volume dc/keycloak-infinispan --add --name=eap-jgroups-keystore-volume -m /etc/jgroups-encrypt-secret-volume -t secret --secret-name=sso-app-secret --default-mode='0755'
    $ oc set volume dc/keycloak-infinispan --add --name=sso-truststore-volume -m /etc/sso-secret-volume -t secret --secret-name=sso-app-secret --default-mode='0755'


#### Create a Route to RHSSO

    $ oc create route edge secure-keycloak-infinispan --service=keycloak-infinispan --port=8080

Notes: 
* Make sure the Route exposed for RHSSO matches the dname used when creating the keystore, e.g. 'secure-keycloak-infinispan-rhsso-rhdg.apps.<Your OpenShift domain>'


### Alternative 2: Use the Template

#### Upload the template

    $ oc create -f sso74-https-infinispan.json -n rhsso-rhdg

#### Import the image

    $ oc import-image torbjorndahlen/keycloak-infinispan --confirm
    
#### Create the RHSSO application

    $ oc new-app --template=sso74-https-infinispan -p SSO_ADMIN_USERNAME=admin -p SSO_ADMIN_PASSWORD=secret -p INFINISPAN_USERNAME=developer -p INFINISPAN_PASSWORD=xoJZLSX37iV7BCDf -p INFINISPAN_SERVERNAME=infinispan -p DB_USERNAME=keycloak -p DB_PASSWORD=password -p JAVA_OPTS_APPEND=-Djboss.site.name=site1 -p HTTPS_SECRET="sso-app-secret" -p HTTPS_KEYSTORE="keystore.jks" -p HTTPS_NAME="jboss" -p HTTPS_PASSWORD="secret" -p JGROUPS_ENCRYPT_SECRET="sso-app-secret" -p JGROUPS_ENCRYPT_KEYSTORE="jgroups.jceks" -p JGROUPS_ENCRYPT_NAME="secret-key" -p JGROUPS_ENCRYPT_PASSWORD="secret" -p SSO_TRUSTSTORE="truststore.jks" -p SSO_TRUSTSTORE_PASSWORD="secret" -p SSO_TRUSTSTORE_SECRET="sso-app-secret"




## Test case

1. Log in user1 in C1
2. Login user2 in C2
3. View the Sessions menu in each RHSSO instance
4. There should be 2 sessions visible in each RHSSO instance


## PostgreSQL commands

    > oc rsh <postgresql-pod>
    $ psql
    postgres# \l /** list DBs */    
    postgres# \c keycloak /** connect to DB keycloak */
    keycloak=# \dt /** list tables */
    keycloak=# SELECT name FROM REALM;

## References

* [https://access.redhat.com/solutions/3402171](https://access.redhat.com/solutions/3402171)
* [https://access.redhat.com/documentation/en-us/red_hat_data_grid/8.1/html/running_data_grid_on_openshift/backup_sites](https://access.redhat.com/documentation/en-us/red_hat_data_grid/8.1/html/running_data_grid_on_openshift/backup_sites)
* [https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html/server_installation_and_configuration_guide/operating-mode#assembly-setting-up-crossdc](https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html/server_installation_and_configuration_guide/operating-mode#assembly-setting-up-crossdc)
* [https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html-single/red_hat_single_sign-on_for_openshift_on_openjdk/index#Configuring-Keystores](https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.4/html-single/red_hat_single_sign-on_for_openshift_on_openjdk/index#Configuring-Keystores)
* [https://docs.jboss.org/infinispan/12.0/apidocs/org/infinispan/client/hotrod/configuration/package-summary.html](https://docs.jboss.org/infinispan/12.0/apidocs/org/infinispan/client/hotrod/configuration/package-summary.html)
