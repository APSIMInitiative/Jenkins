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
rem BUILDS_JWT: JWT for auth with builds API, required to upload the installer.

setlocal enableDelayedExpansion
setlocal

rem Ensure the necessary environment variables are set.
if not defined PULL_ID (set PULL_ID=%ghprbPullId%)
if not defined PULL_ID (echo PULL_ID not set && exit /b 1)
if not defined APSIM_CERT_PWD (echo APSIM_CERT_PWD not set && exit /b 1)
if not defined APSIM_CERT (echo APSIM_CERT not set && exit /b 1)
if not defined MERGE_COMMIT (echo MERGE_COMMIT not set && exit /b 1)
if not defined BUILDS_JWT (echo BUILDS_JWT not set && exit /b 1)

rem Clone the repository.
set "apsimx=%TEMP%\ApsimX"
echo About to clone APSIMX repo.
git clone https://github.com/APSIMInitiative/ApsimX "%apsimx%"
echo Clone completed
if errorlevel 1 exit /b 1
cd "%apsimx%"
rem Checkout the pull request's merge commit.
echo About to checkout branch
git checkout %MERGE_COMMIT%
echo Checkout completed.
if errorlevel 1 exit /b 1

rem Get version info.
echo Getting version number from web service...
curl -s https://builds.apsim.info/api/nextgen/nextversion > temp.txt
if errorlevel 1 exit /b 1
echo Done.
SET /p REVISION=<temp.txt
del temp.txt
for /f "tokens=1,2 delims==" %%i in ('wmic os get LocalDateTime /VALUE 2^>nul') do (
    if ".%%i."==".LocalDateTime." set mydate=%%j
)
set YEAR=%mydate:~0,4%
rem The line below is to get around set /a MONTH=08 failing because of the leading zero in the month number.
set /a MONTH=100%mydate:~4,2% %% 100
set VERSION=%YEAR%.%MONTH%.%REVISION%.0
set SHORT_VERSION=%YEAR%.%MONTH%.%REVISION%
echo version=%VERSION%

rem Version stamp the build.
echo using System.Reflection; > "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyVersion("%VERSION%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyFileVersion("%VERSION%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
echo [assembly: AssemblyCopyright("Copyright © APSIM Initiative %YEAR%")] >> "%apsimx%\Models\Properties\AssemblyVersion.cs"
copy /y "%apsimx%\Models\Properties\AssemblyVersion.cs" "%apsimx%\ApsimNG\Properties\AssemblyVersion.cs"
rem Build the solution.

rem Without the -m:1 below, the order of builds can be incorrect sometimes resulting in this order:
rem     Models -> C:\container-scripts\ApsimX\bin\Release\net8.0\win-x64\Models.dll
rem     Models -> C:\container-scripts\ApsimX\bin\Release\net8.0\Models.dll
rem     Models -> C:\container-scripts\ApsimX\bin\Release\net8.0\win-x64\publish\Models.dll
rem This can lead to an incorrect  publish\models.deps.json. taken from net8.0 directory rather than from netcoreapp3.1\win-x64 directory
rem bug: https://github.com/APSIMInitiative/ApsimX/issues/7829
dotnet publish -c Release -f net8.0 -r win-x64 -m:1 --no-self-contained "%apsimx%\ApsimX.sln"
if errorlevel 1 exit /b 1

rem Generate the installer.
set "setup=%apsimx%\Setup\net8.0\windows"
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
set "url=https://builds.apsim.info/api/nextgen/upload/installer?revision=!REVISION!&platform=Windows"
@curl -s -X POST -H "Authorization: bearer !BUILDS_JWT!" -F "file=@%INSTALLER%" "!url!"
if errorlevel 1 exit /b 1

endlocal
