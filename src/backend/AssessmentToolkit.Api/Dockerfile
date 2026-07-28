# Pre-built Dockerfile — run build.ps1 first to produce publish/ locally.
# No dotnet restore or publish happens inside Docker.
FROM mcr.microsoft.com/dotnet/aspnet:8.0
WORKDIR /app
EXPOSE 8080
COPY publish/ .
ENTRYPOINT ["dotnet", "AssessmentToolkit.Api.dll"]
