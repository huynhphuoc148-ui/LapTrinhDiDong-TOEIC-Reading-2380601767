FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src
COPY ["src/ToeicExam.Web.Host/ToeicExam.Web.Host.csproj", "src/ToeicExam.Web.Host/"]
COPY ["src/ToeicExam.Web.Core/ToeicExam.Web.Core.csproj", "src/ToeicExam.Web.Core/"]
COPY ["src/ToeicExam.Application/ToeicExam.Application.csproj", "src/ToeicExam.Application/"]
COPY ["src/ToeicExam.Core/ToeicExam.Core.csproj", "src/ToeicExam.Core/"]
COPY ["src/ToeicExam.EntityFrameworkCore/ToeicExam.EntityFrameworkCore.csproj", "src/ToeicExam.EntityFrameworkCore/"]
WORKDIR "/src/src/ToeicExam.Web.Host"
RUN dotnet restore 

WORKDIR /src
COPY ["src/ToeicExam.Web.Host", "src/ToeicExam.Web.Host"]
COPY ["src/ToeicExam.Web.Core", "src/ToeicExam.Web.Core"]
COPY ["src/ToeicExam.Application", "src/ToeicExam.Application"]
COPY ["src/ToeicExam.Core", "src/ToeicExam.Core"]
COPY ["src/ToeicExam.EntityFrameworkCore", "src/ToeicExam.EntityFrameworkCore"]
WORKDIR "/src/src/ToeicExam.Web.Host"
RUN dotnet publish -c Release -o /publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0
EXPOSE 80
WORKDIR /app
COPY --from=build /publish .
ENTRYPOINT ["dotnet", "ToeicExam.Web.Host.dll"]
