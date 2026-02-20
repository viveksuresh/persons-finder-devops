# syntax=docker/dockerfile:1.4

# Multi-stage Dockerfile for Spring Boot (Gradle) application

# -------------------------
# Builder stage
# -------------------------
FROM eclipse-temurin:21-jdk-jammy AS builder
WORKDIR /home/gradle/project

# Copy only files needed for dependency resolution to maximize cache reuse
COPY gradle/ gradle/
COPY gradlew settings.gradle.kts build.gradle.kts gradle.properties ./

# Ensure gradlew is executable and normalize line endings (lightweight)
RUN chmod +x gradlew && sed -i 's/\r$//' gradlew

# Resolve dependencies and cache Gradle artifacts using BuildKit cache mount
RUN --mount=type=cache,target=/root/.gradle ./gradlew --no-daemon assemble -x test

# Copy source and run the full build (artifacts go to build/libs)
COPY src/ src/
RUN --mount=type=cache,target=/root/.gradle ./gradlew --no-daemon clean build -x test


# -------------------------
# Runtime stage
# -------------------------
FROM eclipse-temurin:21-jre-jammy AS runtime


# Standard OCI/maintainer labels for traceability
LABEL org.opencontainers.image.title="Persons Finder"
LABEL org.opencontainers.image.description="Persons Finder - Spring Boot API"
LABEL org.opencontainers.image.version="0.0.1"
LABEL org.opencontainers.image.licenses="MIT"
LABEL maintainer="DevOps Team <devops@example.com>"

# Install minimal runtime utilities then cleanup lists
RUN apt-get update && apt-get install -y --no-install-recommends dumb-init curl \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for runtime
RUN groupadd -r appuser && useradd -r -g appuser appuser

WORKDIR /app

# Copy the application JAR from the builder stage
COPY --from=builder --chown=appuser:appuser /home/gradle/project/build/libs/*.jar app.jar

# Switch to the non-root user
USER appuser

# Expose application port
EXPOSE 8080

# Health check for container orchestrators
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/api/v1/persons || exit 1

# Use dumb-init for proper PID 1 signal handling
ENTRYPOINT ["dumb-init", "--"]
CMD ["java", "-jar", "app.jar"]
