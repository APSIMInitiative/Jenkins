@echo off
rem This script run inside a docker container by the Jenkins
rem infrastructure. It will build and upload the windows .NET Core
rem installer.
rem
rem Requires no command line arguments, but requires that a few
rem environment variables are set:
rem
rem PULL_ID: The ID/number of the pull request which triggered this
rem release.
rem APSIM_CERT_PWD: Password on the certificate file.
rem APSIM_CERT: Path to the certificate file on disk.
rem APSIM_SITE_CREDS: Credentials required to upload the installer.

setlocal enableDelayedExpansion
setlocal

rem Ensure the necessary environment variables are set.
if not defined PULL_ID (set PULL_ID=%ghprbPullId%)
if not defined PULL_ID (echo PULL_ID not set && exit /b 1)
if not defined APSIM_CERT_PWD (echo APSIM_CERT_PWD not set && exit /b 1)
if not defined APSIM_CERT (echo APSIM_CERT not set && exit /b 1)
if not defined APSIM_SITE_CREDS (echo APSIM_SITE_CREDS not set && exit /b 1)
if not defined MERGE_COMMIT (echo MERGE_COMMIT not set && exit /b 1)

rem Clone the repository.
set "apsimx=%TEMP%\ApsimX"
git clone https://github.com/APSIMInitiative/ApsimX "%apsimx%"
if errorlevel 1 exit /b 1
cd "%apsimx%"
rem Checkout the pull request's merge commit.
git checkout %MERGE_COMMIT%
if errorlevel 1 exit /b 1

rem Get version info.
echo Getting version number from web service...
curl -ks https://apsimdev.apsim.info/APSIM.Builds.Service/Builds.svc/GetNextVersion > temp.txt
if errorlevel 1 exit /b 1
echo Done.
for /F "tokens=3 delims==><" %%I IN (temp.txt) DO SET REVISION=%%I
del temp.txt
set YEAR=%date:~10,4%
set MONTH=%date:~4,2%
set VERSION=%YEAR%.%MONTH%.%REVISION%.0
set SHORT_VERSION=%YEAR%.%MONTH%.%REVISION%
echo version=%VERSION%

rem Version stamp the build.
echo using System.Reflection; > "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyTitle("APSIM %SHORT_VERSION%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyVersion("%VERSION%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyFileVersion("%VERSION%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyCopyright("Copyright © APSIM Initiative %YEAR%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
copy /y "%apsimx%\Models\Properties\AssemblyVersion.cs" "%apsimx%\ApsimNG\Properties\AssemblyVersion.cs"

rem Build the solution.
dotnet publish -c Release -f netcoreapp3.1 -r win-x64 --no-self-contained "%apsimx%\ApsimNG\ApsimNG.csproj"
dotnet publish -c Release -f netcoreapp3.1 -r win-x64 --no-self-contained "%apsimx%\Models\Models.csproj"
if errorlevel 1 exit /b 1

rem Generate the installer.
set "setup=%apsimx%\Setup\netcoreapp3.1\windows"
iscc /Q "%setup%\apsimx.iss"
if errorlevel 1 exit /b 1
set "INSTALLER=apsim-%REVISION%.exe"
move "%setup%\Output\ApsimSetup.exe" "%INSTALLER%"
if errorlevel 1 exit /b 1

rem Sign the installer.
rem ----- This requires SignTool.exe to be on PATH.
rem ----- Also assumes that APSIM_CERT_PWD is an existing environment variable (it's set by jenkins)
set TIMESTAMP="http://timestamp.comodoca.com/?td=sha256"
SignTool sign /q /as /fd sha256 /tr %TIMESTAMP% /td sha256 /f %APSIM_CERT% /p %APSIM_CERT_PWD% %INSTALLER%
if errorlevel 1 exit /b 1
SignTool verify /pa /v /d %INSTALLER%
if errorlevel 1 exit /b 1

rem Upload the installer.
curl -s -u !APSIM_SITE_CREDS! -T "%INSTALLER%" ftp://apsimdev.apsim.info/APSIM/ApsimXFiles/
if errorlevel 1 exit /b 1

endlocal
