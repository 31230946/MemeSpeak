# ==============================================================================
# Multi-stage Dockerfile for MemeSpeak backend
#
# Stage 1 (build): Compiles the application with Maven inside a JDK 21 image.
#                  Dependencies are cached in a separate layer for faster builds.
# Stage 2 (runtime): Runs the JAR in a minimal JRE image — no build tools included.
# ==============================================================================

# ---- Stage 0: Build the React frontend ----
# The built site is bundled into the backend JAR below, so one container serves
# both the website and the API on the same origin (no CORS, one Google origin).
FROM node:22-alpine AS frontend

WORKDIR /build/frontend

COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY frontend/ ./

# The Google client ID is public (it is visible in the browser) and must be
# known at build time. Hosts such as Render pass service env vars as build args.
ARG VITE_GOOGLE_CLIENT_ID=""
ENV VITE_GOOGLE_CLIENT_ID=$VITE_GOOGLE_CLIENT_ID
RUN npm run build

# ---- Stage 1: Build ----
FROM maven:3.9-eclipse-temurin-21-alpine AS build

WORKDIR /build

# Copy only the POM first to cache the dependency download layer.
# Dependencies are re-downloaded only when pom.xml changes.
COPY pom.xml .
RUN mvn dependency:go-offline --no-transfer-progress -q

# Copy source and the built frontend (served by Spring Boot from classpath:/static),
# then build — skip tests (tests run in CI, not in Docker build)
COPY src ./src
COPY --from=frontend /build/frontend/dist ./src/main/resources/static
RUN mvn package -DskipTests --no-transfer-progress -q

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:21-jre-alpine

# Security: run as a non-root user
RUN addgroup -S memespeak && adduser -S memespeak -G memespeak

WORKDIR /app

# Copy only the executable JAR from the build stage
COPY --from=build /build/target/*.jar app.jar

# Set ownership
RUN chown memespeak:memespeak app.jar

USER memespeak

EXPOSE 8080

# JVM flags:
#   -XX:+UseContainerSupport  — respects Docker CPU/memory limits (on by default in JDK 11+)
#   -XX:MaxRAMPercentage=65.0 — leave headroom for metaspace/threads on small (512 MB) hosts
#   -XX:+UseSerialGC          — lowest-overhead collector, fine for a small single-user demo
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=65.0", \
  "-XX:+UseSerialGC", \
  "-jar", "app.jar"]
