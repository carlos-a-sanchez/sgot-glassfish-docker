Because both GlassFish 3 and Java 7 are end-of-life, there is no actively maintained official Docker image combining this specific stack (the legacy official Docker Hub `glassfish` images only started at version 4.0).

The most reliable approach is to build a custom image using an archived OpenJDK 7 base image and pull the final GlassFish 3 release (`3.1.2.2`) directly from Maven Central.

### 1. Create the `Dockerfile`

Save the following configuration as `Dockerfile` in an empty directory:

```dockerfile
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

```

---

### 2. Build and Run the Container

Create a `.env` file next to the `Dockerfile` (and add it to `.gitignore` and `.dockerignore`):

```
AS_ADMIN_PASSWORD=AvTo1sa
```

Build the image locally, passing `.env` as a BuildKit secret:

```bash
DOCKER_BUILDKIT=1 docker build --secret id=envfile,src=.env -t glassfish3-java7 .

```

Run the container, mapping the HTTP (`8080`), HTTPS (`8181`), and Admin Console ports (host `4848` maps to the in-container proxy on `4850`):

```bash
docker run -d \
  --name glassfish3 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 4848:4850 \
  glassfish3-java7

```

---

### Key Operational Notes

* **Admin Console over HTTP:** open `http://localhost:4848/` (not `/login.jsf` directly) and log in as `admin` with the password from `.env`. The password is read from `AS_ADMIN_PASSWORD` in `.env` at build time (via a BuildKit secret, so it is not stored in an image layer).
* **Why the proxy:** GlassFish 3.1.2.2 only offers TLS 1.0/1.1 with an expired bundled certificate, so modern browsers cannot use its HTTPS admin port. Secure admin is therefore left off, the admin listener is bound to `127.0.0.1`, and `socat` forwards container port `4850` to it so GlassFish treats requests as local. Do not expose port 4848 on untrusted networks: it is plain HTTP.
* **Application Deployment:** To deploy a `.war` or `.ear` file, either mount your artifact directory to `/opt/glassfish3/glassfish/domains/domain1/autodeploy` or add a `COPY your-app.war /opt/glassfish3/glassfish/domains/domain1/autodeploy/` instruction to the `Dockerfile`.
* **Base Image Availability:** `openjdk:7u211-jdk` (the plain `7-jdk` tag no longer exists) is based on Debian jessie, whose package mirrors are archived. The `Dockerfile` repoints `/etc/apt/sources.list` to `archive.debian.org` to install `socat`; the image is amd64-only (emulated on Apple Silicon).