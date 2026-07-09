FROM registry.access.redhat.com/ubi9/openjdk-17:latest AS build
USER root
WORKDIR /build
COPY pom.xml .
COPY src ./src
RUN mvn -q -B package -DskipTests -Dmaven.compiler.release=17

FROM registry.access.redhat.com/ubi9/openjdk-17:latest
WORKDIR /deployments
COPY --from=build /build/target/quarkus-app/ /deployments/
EXPOSE 8080
USER 185
ENV JAVA_OPTS="-Dquarkus.http.host=0.0.0.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
ENV JAVA_APP_JAR="/deployments/quarkus-run.jar"
ENTRYPOINT [ "/opt/jboss/container/java/run/run-java.sh" ]
