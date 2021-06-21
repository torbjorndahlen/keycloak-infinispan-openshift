# keycloak-infinispan-openshift
Demo on integrating Keycloak with an external Infinispan server

A new RHSSO image is built by adding a modified version of standalone-openshift.xml containing Infinispan Hotrod client configuration and replicated/distributed caches.

# Modifications to the original standalone-openshift.xml

## Line 223
<subsystem xmlns="urn:jboss:domain:infinispan:9.0">
            <cache-container name="keycloak" module="org.keycloak.keycloak-model-infinispan">

## Lines 245 - 279

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
                        <property name="infinispan.client.hotrod.auth_username">admin</property>
                        <property name="infinispan.client.hotrod.auth_password">secret</property>
                        <property name="infinispan.client.hotrod.auth_realm">default</property>
                        <property name="infinispan.client.hotrod.auth_server_name">infinispan</property>
                        <property name="infinispan.client.hotrod.sasl_mechanism">DIGEST-MD5</property>
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
                        <property name="infinispan.client.hotrod.auth_username">admin</property>
                        <property name="infinispan.client.hotrod.auth_password">secret</property>
                        <property name="infinispan.client.hotrod.auth_realm">default</property>
                        <property name="infinispan.client.hotrod.auth_server_name">infinispan</property>
                        <property name="infinispan.client.hotrod.sasl_mechanism">DIGEST-MD5</property>
                    </remote-store>
                </distributed-cache>

## Lines 679 - 682

### This is where the location of the Infinispan server needs to be inserted

        <outbound-socket-binding name="remote-cache"> 
            <remote-destination host="${remote.cache.host:localhost}" 
                      port="${remote.cache.port:11222}"/> 
        </outbound-socket-binding>



## Other
TODO: The hostname for the Infinispan server it currently not configurable.
