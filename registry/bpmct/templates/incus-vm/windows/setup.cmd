@echo off
rem Runs one time at the first logon of the golden image build (see autounattend.xml).
rem It uses cmd tools only. PowerShell is slow to start until Defender is up to date.
rem If a step fails, the VM stays on so that you do not publish a broken image.

mkdir C:\coder
copy /y "%~dp0bootstrap.ps1" C:\coder\bootstrap.ps1 || exit /b 1
schtasks /create /tn CoderAgent /xml "%~dp0coder-agent-task.xml" /f || exit /b 1

rem The Defender engine on the install media is old. In testing, it made
rem PowerShell wait for minutes at each boot. This step needs internet access.
rem Defender is not ready immediately after the first logon, so try again on failure.
set updated=
for /l %%i in (1,1,30) do if not defined updated (
  "%ProgramFiles%\Windows Defender\MpCmdRun.exe" -SignatureUpdate
  if not errorlevel 1 set updated=1
  rem ping is the sleep command here. It waits for approximately 60 seconds.
  if not defined updated ping -n 61 127.0.0.1 >nul
)
if not defined updated exit /b 1

shutdown /s /t 10
