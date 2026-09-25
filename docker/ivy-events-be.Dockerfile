# Build context is the ZM workspace root (C:/Projects/ZM) so this build can
# see BOTH ivy-events-be and its private dependency zm-iam-provisioning-client.
# All compilation happens with JDK 25 from the maven base image — the host JDK
# is irrelevant.

FROM maven:3-eclipse-temurin-25 AS builder
WORKDIR /workspace

# jitpack.io is declared in ivy-events-be/pom.xml for one artifact:
# com.github.zorannmitkovskii:zm-iam-provisioning-client. Maven asks every
# declared repository for every artifact, and jitpack answers for things it
# does not have — with an empty 200.
#
# That is how this build used to die on xml-apis:xml-apis-ext:1.3.04: jitpack
# served a zero-byte .pom and .jar, the checksum mismatch was logged as a
# WARNING, the empty files were cached, and the compiler then reported
# "cannot access org.ivyinc" with a ZipException underneath. The symptom
# pointed at our source; the cause was a repository answering a question it
# should never have been asked.
#
# Written inline rather than COPYed: .dockerignore keeps the context down to
# the two Maven modules, and widening it for one config file is a worse trade
# than a heredoc.
RUN mkdir -p /root/.m2 && cat > /root/.m2/settings.xml <<'SETTINGS'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <mirrors>
    <mirror>
      <id>central-for-everything-else</id>
      <url>https://repo.maven.apache.org/maven2</url>
      <mirrorOf>*,!jitpack.io</mirrorOf>
    </mirror>
  </mirrors>
</settings>
SETTINGS

# 1) Build + install the private SNAPSHOT dependency into the image's local repo.
COPY zm-iam-provisioning-client/pom.xml zm-iam-provisioning-client/pom.xml
RUN mvn -B -q -f zm-iam-provisioning-client/pom.xml dependency:go-offline
COPY zm-iam-provisioning-client/src zm-iam-provisioning-client/src
RUN mvn -B -q -f zm-iam-provisioning-client/pom.xml install -DskipTests

# 2) Build ivy-events-be against it. pom first for dependency-layer caching.
COPY ivy-events-be/pom.xml ivy-events-be/pom.xml

# go-offline is allowed to fail. It downloads a few hundred artifacts and an
# interrupted one leaves a truncated jar behind; Maven then reports it as
# "cannot access org.ivyinc" with a ZipException underneath, which reads like a
# source error and is not one. Letting this step fail keeps the layer cache
# without letting one bad download stop the build.
RUN mvn -B -q -f ivy-events-be/pom.xml dependency:go-offline || true

# Delete anything that is not a readable archive. jar(1) ships with the JDK in
# this image, so no extra tool is needed. Without this a corrupt artifact
# survives in the layer cache and every later build fails on the same file —
# which is exactly what happened with xml-apis-ext-1.3.04.jar.
RUN find /root/.m2/repository -name '*.jar' -exec \
        sh -c 'jar tf "$1" >/dev/null 2>&1 || { echo "скршен, се брише: $1"; rm -f "$1"; }' _ {} \;

# Fetch the one artifact this build keeps tripping over straight from Central,
# naming the repository so no other one is consulted. Deleting the corrupt jar
# above is not enough on its own: the refetch below asks every declared
# repository, jitpack answers for xml-apis-ext with an empty 200, and the empty
# jar lands in the cache again — the same "zip file is empty" as before, just
# one layer later. Resolving it here means Maven finds it present and never
# asks. Kept separate from the mirror config because jitpack must stay
# reachable for zm-iam-provisioning-client.
RUN mvn -B -q dependency:get \
        -DremoteRepositories=central::default::https://repo.maven.apache.org/maven2 \
        -Dartifact=xml-apis:xml-apis-ext:1.3.04

COPY ivy-events-be/src ivy-events-be/src

# -U so whatever was just deleted is fetched again instead of resolving to the
# hole it left.
RUN mvn -B -f ivy-events-be/pom.xml package -DskipTests -U

# 3) Slim runtime.
FROM eclipse-temurin:25-jre-alpine
WORKDIR /app
COPY --from=builder /workspace/ivy-events-be/target/*.jar /app/app.jar
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "app.jar"]
