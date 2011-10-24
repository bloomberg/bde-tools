@echo off
REM Utility batch file which runs its first argument (usually
REM another batch file, like vsvars32.bat), then dumps the resulting
REM environment settings to STDOUT.
REM
REM Used as a helper script by bde_bldmgr.slave.pl

REM Run first argument
call %1

REM Dump environment
SET

