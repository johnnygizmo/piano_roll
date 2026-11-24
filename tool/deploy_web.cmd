@echo off
rem Wrapper so the deploy script runs without changing PowerShell's execution policy.
rem Usage: tool\deploy_web.cmd [-Push] [-SkipChecks] [-AllowDirty] ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_web.ps1" %*
