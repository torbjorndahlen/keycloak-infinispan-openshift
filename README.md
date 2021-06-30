# keycloak-infinispan-openshift
Demo on integrating Keycloak with an external Infinispan server

A new RHSSO image is built by adding a modified version of standalone-openshift.xml containing Infinispan Hotrod client configuration and replicated/distributed caches.

## Modifications to the original standalone-openshift.xml

### Extract the standalone-openshift.xml file from the RHSSO image
docker run -it --rm registry.redhat.io/rh-sso-7/sso74-openshift-rhel8 /bin/bash

cat /opt/eap/standalone/configuration/standalone-openshift.xml

### Make the following modifications
This example only shows the work cache and the clientSessions cache.

#### Line 223

    <subsystem xmlns="urn:jboss:domain:infinispan:9.0">
            <cache-container name="keycloak" module="org.keycloak.keycloak-model-infinispan">

#### Lines 245 - 279

               <replicated-cache name="work">
                    <remote-store cache="work" 
                            remote-servers="remote-cache" 
                            passivation="false"
                            fetch-state="false"
                            purge="false"
                            preload="false"
                            shared="true">
                        <property name="rawValues">true</property>
                        <property name="marshaller">org.keycloak.cluster.infinispan.KeycloakHotRodMarshallerFactory</property>
                        <property name="infinispan.client.hotrod.auth_username">developer</property>
                        <property name="infinispan.client.hotrod.auth_password">password</property>
                        <property name="infinispan.client.hotrod.auth_realm">default</property>
                        <property name="infinispan.client.hotrod.auth_server_name">infinispan</property>
                    </remote-store>
                </replicated-cache>

                <distributed-cache name="clientSessions" owners="1">
                    <remote-store cache="clientSessions" 
                            remote-servers="remote-cache" 
                            passivation="false"
                            fetch-state="false"
                            purge="false"
                            preload="false"
                            shared="true">
                        <property name="rawValues">true</property>
                        <property name="marshaller">org.keycloak.cluster.infinispan.KeycloakHotRodMarshallerFactory</property>
                        <property name="infinispan.client.hotrod.auth_username">developer</property>
                        <property name="infinispan.client.hotrod.auth_password">password</property>
                        <property name="infinispan.client.hotrod.auth_realm">default</property>
                        <property name="infinispan.client.hotrod.auth_server_name">infinispan</property>
                    </remote-store>
                </distributed-cache>



Note that the auth_username and auth_password is generated by the RHDG Operator and can be found under Secrets in the RHDG namespace.

#### Lines 369 - 371

           <stacks>
                <stack name="udp">
                    <transport type="UDP" socket-binding="jgroups-udp" site="${jboss.site.name}/>


#### Lines 679 - 682

This is where the location of the Infinispan server needs to be inserted

        <outbound-socket-binding name="remote-cache"> 
            <remote-destination host="${remote.cache.host:infinispan}" 
                      port="${remote.cache.port:11222}"/> 
        </outbound-socket-binding>

If RHSSO and RHDG are deployed in the same namespace, the service name for RHDG (infinispan) is used.
For external RHDG clients, infinispan-external should be used as host name 

## Build and push image

docker build -t torbjorndahlen/keycloak-infinispan:latest .

docker push torbjorndahlen/keycloak-infinispan:latest

## Deploy image in OpenShift

oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest 

oc create route edge secure-keycloak-infinispan --service=keycloak-infinispan --port=8080

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


### Add environment variables

The hostname, username and password for the Infinispan server are currently not configurable, and should be 
configured using environment variables in the standalone-openshift.xml file, e.g.

    <property name="infinispan.client.hotrod.auth_username">${env.INFINISPAN_USERNAME}</property>
    <property name="infinispan.client.hotrod.auth_password">${env.INFINISPAN_PASSWORD}</property>

Also the site name needs to be passed as an environment variable.

Then deploy RHSSO as follows

oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest -e INFINISPAN_USERNAME=developer -e INFINISPAN_PASSWORD=password -e INFINISPAN_SERVERNAME=infinispan -e JAVA_OPTS_APPEND=-Djboss.site.name=site1


## Deploy RHDG cross-DC with single RHSSO instance in each DC

### Deploy PostgreSQL DB for use by the 2 RHSSO clusters

#### Modify standalone-openshift.xml as follows:

<subsystem xmlns="urn:jboss:domain:datasources:5.0">
            <datasources>
                <!-- ##DATASOURCES## -->
                <datasource jndi-name="java:jboss/datasources/KeycloakDS" pool-name="KeycloakDS" enabled="true" use-java-context="true">
                    <connection-url>jdbc:postgresql://postgresql/keycloak</connection-url>
                    <driver>postgresql</driver>
                    <security>
                        <user-name>${env.DB_USERNAME}</user-name>
                        <password>${env.DB_PASSWORD}</password>
                    </security>
                </datasource>
                <drivers>
                    <driver name="h2" module="com.h2database.h2">
                        <xa-datasource-class>org.h2.jdbcx.JdbcDataSource</xa-datasource-class>
                    </driver>
                    <driver name="postgresql" module="org.postgresql">
                        <xa-datasource-class>org.postgresql.xa.PGXADataSource</xa-datasource-class>
                    </driver>
                    <!-- ##DRIVERS## -->
                </drivers>
            </datasources>



#### Depoly RHSSO

oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest -e INFINISPAN_USERNAME=developer -e INFINISPAN_PASSWORD=password -e INFINISPAN_SERVERNAME=infinispan -e JAVA_OPTS_APPEND=-Djboss.site.name=site1 -e DB_USERNAME=keycloak -e DB_PASSWORD=password


### Deploy 2 RHSSO instances in one OCP cluster and verify that both sees the same RHDG cache