FROM --platform=linux/amd64 openjdk:7u211-jdk

ENV GLASSFISH_VERSION=3.1.2.2 \
    GLASSFISH_HOME=/opt/glassfish3 \
    PATH=$PATH:/opt/glassfish3/bin

# socat proxies the admin console so GlassFish sees requests as coming from localhost
# (Debian jessie is archived, so point apt at archive.debian.org)
RUN echo "deb http://archive.debian.org/debian jessie main" > /etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update -qq && \
    apt-get install -y -qq --force-yes socat && \
    rm -rf /var/lib/apt/lists/*

# Download and extract GlassFish 3.1.2.2 from Maven Central
RUN curl -fSL "https://repo.maven.apache.org/maven2/org/glassfish/main/distributions/glassfish/${GLASSFISH_VERSION}/glassfish-${GLASSFISH_VERSION}.zip" -o /tmp/glassfish.zip && \
    unzip -q /tmp/glassfish.zip -d /opt && \
    rm -f /tmp/glassfish.zip

# Set the admin password from the .env build secret and bind the admin listener to loopback only
RUN --mount=type=secret,id=envfile \
    . /run/secrets/envfile && \
    printf 'AS_ADMIN_PASSWORD=\nAS_ADMIN_NEWPASSWORD=%s\n' "$AS_ADMIN_PASSWORD" > /tmp/pw-change.txt && \
    printf 'AS_ADMIN_PASSWORD=%s\n' "$AS_ADMIN_PASSWORD" > /tmp/pw.txt && \
    asadmin start-domain && \
    asadmin --user admin --passwordfile=/tmp/pw-change.txt change-admin-password && \
    asadmin --user admin --passwordfile=/tmp/pw.txt set configs.config.server-config.network-config.network-listeners.network-listener.admin-listener.address=127.0.0.1 && \
    asadmin stop-domain && \
    rm -f /tmp/pw-change.txt /tmp/pw.txt

# Admin console: plain HTTP on container port 4850 -> GlassFish on 127.0.0.1:4848
EXPOSE 8080 8181 4850

CMD ["sh", "-c", "socat TCP-LISTEN:4850,fork,reuseaddr TCP:127.0.0.1:4848 & exec asadmin start-domain --verbose"]
