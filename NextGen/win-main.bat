@echo off
rem This script run inside a docker container by the Jenkins
rem infrastructure. It will build and upload the windows .NET Core
rem installer.

rem Need to copy the code signing certificate into the container.
mkdir cert
copy "%APSIM_CERT%" cert\apsim.p12

set container=apsiminitiative/apsimng-build-win
docker pull -q %container%
docker run --rm --dns 1.1.1.1 --entrypoint=deploy-win.bat -v "%~dp0container-scripts":C:/container-scripts -v "%cd%\cert":C:\cert -w /container-scripts -e BUILDS_JWT -e MERGE_COMMIT -e APSIM_CERT=C:\cert\apsim.p12 -e ghprbPullId -e PULL_ID -e APSIM_CERT_PWD %container%
