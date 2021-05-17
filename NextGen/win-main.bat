@echo off
rem This script run inside a docker container by the Jenkins
rem infrastructure. It will build and upload the windows .NET Core
rem installer.

set container=apsiminitiative/apsimng-build-win
docker pull -q %container%
docker run --rm --entrypoint=deploy-win.bat -v "%~dp0container-scripts":C:/container-scripts -w /container-scripts -e PULL_ID -e APSIM_SITE_CREDS -e APSIM_CERT -e APSIM_CERT_PWD -e APSIM_SITE_CREDS %container%
