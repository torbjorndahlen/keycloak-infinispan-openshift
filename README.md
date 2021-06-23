# keycloak-infinispan-openshift
Demo on integrating Keycloak with an external Infinispan server

A new RHSSO image is built by adding a modified version of standalone-openshift.xml containing Infinispan Hotrod client configuration and replicated/distributed caches.

# Modifications to the original standalone-openshift.xml

## Extract the standalone-openshift.xml file from the RHSSO image
docker run -it --rm registry.redhat.io/rh-sso-7/sso74-openshift-rhel8 /bin/bash

cat /opt/eap/standalone/configuration/standalone-openshift.xml

## Make the following modifications
This example only shows the work cache and the clientSessions cache.

### Line 223
<subsystem xmlns="urn:jboss:domain:infinispan:9.0">
            <cache-container name="keycloak" module="org.keycloak.keycloak-model-infinispan">

### Lines 245 - 279

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


## Lines 369 - 371

           <stacks>
                <stack name="udp">
                    <transport type="UDP" socket-binding="jgroups-udp" site="${jboss.site.name}/>


## Lines 679 - 682

### This is where the location of the Infinispan server needs to be inserted

        <outbound-socket-binding name="remote-cache"> 
            <remote-destination host="${remote.cache.host:infinispan}" 
                      port="${remote.cache.port:11222}"/> 
        </outbound-socket-binding>

If RHSSO adn RHDG is deployed in the same namespace, the service name for RHDG (infinispan) is used.
For external RHDG clients, infinispan-external should be used as host name 

## Build and push image
docker build . -t torbjorndahlen/keycloak-infinispan:latest

docker push torbjorndahlen/keycloak-infinispan:latest

## Deploy image in OpenShift
oc new-app --docker-image=torbjorndahlen/keycloak-infinispan:latest

oc create route edge secure-keycloak-infinispan --service=keycloak-infinispan --port=8080



## Other

### The remaining caches can be modified in the same way as the clientSessions cache:

                <distributed-cache name="sessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>
                <distributed-cache name="authenticationSessions" owners="${env.CACHE_OWNERS_AUTH_SESSIONS_COUNT:1}"/>
                <distributed-cache name="offlineSessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>               
                <distributed-cache name="offlineClientSessions" owners="${env.CACHE_OWNERS_COUNT:1}"/>
                <distributed-cache name="loginFailures" owners="${env.CACHE_OWNERS_COUNT:1}"/>

### TODO

The hostname, username and password for the Infinispan server are currently not configurable.


## Deploying Red Hat Data Grid with the Opoenshift Operator

Note: use RHDG v 8.1 with RHSSO

Add the following to the CRD for RHDG:

expose:
    host: infinispan-external-rhdg.apps.cluster-1782.1782.sandbox379.opentlc.com
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
