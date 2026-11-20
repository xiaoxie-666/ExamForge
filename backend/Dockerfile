# Build stage: Maven/JDK live inside Docker; the host machine does not need either installed.
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /app

# Keep dependency resolution in a separate layer so source-only changes can reuse it.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -DskipTests package

# Runtime stage contains only the Java 17 JRE and the executable application jar.
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/examforge-backend-1.0.0.jar app.jar
EXPOSE 8080 9998
ENTRYPOINT ["java","-jar","/app/app.jar"]
