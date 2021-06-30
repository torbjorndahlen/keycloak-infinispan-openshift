FROM registry.redhat.io/rh-sso-7/sso74-openshift-rhel8
ENV SSO_ADMIN_USERNAME="admin"
ENV SSO_ADMIN_PASSWORD="secret"
COPY standalone-openshift.xml /opt/eap/standalone/configuration/standalone-openshift.xml

COPY extensions/postconfigure.sh /opt/eap/extensions/
COPY extensions/actions.cli /opt/eap/extensions/

USER root
RUN chmod 774 /opt/eap/extensions/*.sh
USER jboss

CMD ["/opt/eap/bin/openshift-launch.sh"]