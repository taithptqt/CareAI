# CareAI Backend - Production Dockerfile (.NET 9 LTS Sovereign Modular Monolith)
# Multi-stage build for optimal image size and non-root security.

FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy project files for layer caching
COPY ["src/CareAI.Core/CareAI.Core.csproj", "src/CareAI.Core/"]
COPY ["src/CareAI.Infrastructure/CareAI.Infrastructure.csproj", "src/CareAI.Infrastructure/"]
COPY ["src/CareAI.API/CareAI.API.csproj", "src/CareAI.API/"]

# Restore dependencies
RUN dotnet restore "src/CareAI.API/CareAI.API.csproj"

# Copy all source files
COPY src/ src/

# Build and publish release binaries
WORKDIR "/src/src/CareAI.API"
RUN dotnet publish "CareAI.API.csproj" -c Release -o /app/publish /p:UseAppHost=false --no-restore

# Final runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

# Run as non-root user for enterprise container security
USER $APP_UID

# Environment defaults
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_EnableDiagnostics=0

EXPOSE 8080

COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "CareAI.API.dll"]
