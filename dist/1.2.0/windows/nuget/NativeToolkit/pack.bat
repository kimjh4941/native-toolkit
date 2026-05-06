@echo off
setlocal

REM Package NativeToolkit.nuspec into .nupkg in this folder
nuget pack NativeToolkit.nuspec -OutputDirectory .

endlocal
