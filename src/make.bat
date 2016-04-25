@call perlapp src\nodepoint.perlapp
@call perlapp src\nodepoint-automate.perlapp
@call "C:\Program Files (x86)\Windows Kits\8.0\bin\x64\signtool.exe" sign /n "Patrick Lambert" /t http://timestamp.verisign.com/scripts/timstamp.dll Windows\nodepoint\www\nodepoint.exe
@call "C:\Program Files (x86)\Windows Kits\8.0\bin\x64\signtool.exe" sign /n "Patrick Lambert" /t http://timestamp.verisign.com/scripts/timstamp.dll Windows\nodepoint\www\nodepoint-automate.exe
