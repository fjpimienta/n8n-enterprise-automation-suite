# Etapa de compilación
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY ["FeaSignerAPI.csproj", "./"]
RUN dotnet restore "./FeaSignerAPI.csproj"
COPY . .
RUN dotnet publish "FeaSignerAPI.csproj" -c Release -o /app/publish

# Etapa de producción
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app
COPY --from=build /app/publish .

# Hardening: Usuario no privilegiado
RUN adduser --disabled-password \
  --home /app \
  --gecos '' dotnetuser && chown -R dotnetuser /app
USER dotnetuser

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "FeaSignerAPI.dll"]
