FROM registry.redhat.io/rh-sso-7/sso74-openshift-rhel8
ENV SSO_ADMIN_USERNAME="admin"
ENV SSO_ADMIN_PASSWORD="secret"
ENV JAVA_OPTS_APPEND=-Djboss.site.name=site1
ADD standalone-openshift.xml /opt/eap/standalone/configuration/standalone-openshift.xml
