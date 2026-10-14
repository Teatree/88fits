<#
Signs the Windows build (pass 73, Garry: "any way you can make it 'trustworthy' in the eyes of Windows").
ship.sh runs it after the PC export ONLY when tools/keys/codesign.env exists (tools/keys/ is git-ignored, like the
Android keystore.env). Without that file nothing is signed and nothing changes. Why Windows warns and what a
certificate does and does not change: tools/dl/p73/UIPC/trust.md.

tools/keys/codesign.env holds KEY=value lines (ship.sh exports them), one of three ways to sign:
  CODESIGN_PFX=D:/keys/88fits.pfx         a certificate file (.pfx / .p12) ...
  CODESIGN_PASSWORD=...                   ... and its password
or
  CODESIGN_SHA1=0123abcd...               the thumbprint of a certificate in the Windows certificate store: a USB
                                          token, or a CA's cloud card that shows up there (Certum SimplySign,
                                          SSL.com eSigner CKA); signtool asks the token/app for the key
or
  CODESIGN_CMD=<a whole command>          a signing service's own command, {exe} replaced by the exe's path
                                          (Microsoft Artifact Signing's dlib, a CA's cloud tool)
and optionally
  CODESIGN_TIMESTAMP=http://timestamp.digicert.com   RFC 3161 time-stamp server ("none": no time-stamp; a
                                          time-stamped signature stays valid after the certificate expires)
  CODESIGN_DESCRIPTION=88fits             the name Windows shows in the UAC / SmartScreen dialog
  SIGNTOOL=C:/.../signtool.exe            default: the newest x64 signtool of the Windows 10/11 SDK, else signtool on
                                          PATH, else PowerShell's own Set-AuthenticodeSignature

  powershell -NoProfile -ExecutionPolicy Bypass -File tools/sign_exe.ps1 -Exe game/export/88fits.exe

Exit 0: the exe carries a signature by that certificate (whether this PC trusts the certificate is printed: a
self-signed one is "not trusted"); 1: not signed, with the reason.
#>
param([Parameter(Mandatory = $true)][string]$Exe)

$ErrorActionPreference = "Stop"

function Fail([string]$why) {
	Write-Output "sign_exe: NOT SIGNED: $why"
	exit 1
}

if (-not (Test-Path -LiteralPath $Exe)) { Fail "no file at $Exe" }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$pfx = [string]$env:CODESIGN_PFX
$pass = [string]$env:CODESIGN_PASSWORD
$sha1 = ([string]$env:CODESIGN_SHA1) -replace "\s", ""
$cmd = [string]$env:CODESIGN_CMD
$ts = [string]$env:CODESIGN_TIMESTAMP
if ($ts -eq "") { $ts = "http://timestamp.digicert.com" }
$desc = [string]$env:CODESIGN_DESCRIPTION
if ($desc -eq "") { $desc = "88fits" }

# the certificate the signature must come from (null for a service's own command: any signature counts)
$expect = $null
if ($cmd -eq "") {
	if ($pfx -ne "") {
		if (-not (Test-Path -LiteralPath $pfx)) { Fail "CODESIGN_PFX names no file: $pfx" }
		try {
			# read for its thumbprint only: the key stays in the file (EphemeralKeySet, .NET 4.7.2+)
			$flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
			$probe = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfx, $pass, $flags)
		} catch {
			Fail "the certificate file did not open (password?): $($_.Exception.Message)"
		}
		$expect = $probe.Thumbprint
		$probe.Reset()
	} elseif ($sha1 -ne "") {
		$expect = $sha1.ToUpper()
		$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $expect } | Select-Object -First 1
		if ($cert -eq $null) { Fail "no certificate with thumbprint $expect in the certificate store (is the token in, the signing app running?)" }
	} else {
		Fail "codesign.env names no CODESIGN_PFX, CODESIGN_SHA1 or CODESIGN_CMD"
	}
}

if ($cmd -ne "") {
	$line = $cmd.Replace("{exe}", '"' + $Exe + '"')
	Write-Output "sign_exe: running the signing command"
	& cmd.exe /c $line
	if ($LASTEXITCODE -ne 0) { Fail "the signing command exited with $LASTEXITCODE" }
} else {
	$tool = [string]$env:SIGNTOOL
	if ($tool -eq "") {
		$kits = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
		$found = Get-ChildItem -Path $kits -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match "\\x64\\" } | Sort-Object { $v = [version]"0.0"; [void][version]::TryParse($_.Directory.Parent.Name, [ref]$v); $v } | Select-Object -Last 1
		if ($found) { $tool = $found.FullName }
		elseif (Get-Command signtool.exe -ErrorAction SilentlyContinue) { $tool = "signtool.exe" }
	}
	if ($tool -ne "") {
		$sa = @("sign", "/fd", "SHA256", "/d", $desc)
		if ($pfx -ne "") { $sa += @("/f", $pfx, "/p", $pass) } else { $sa += @("/sha1", $expect) }
		if ($ts -ne "none") { $sa += @("/tr", $ts, "/td", "SHA256") }
		$sa += @($Exe)
		Write-Output "sign_exe: $tool"
		& $tool @sa
		if ($LASTEXITCODE -ne 0) { Fail "signtool exited with $LASTEXITCODE" }
	} else {
		Write-Output "sign_exe: no signtool (Windows SDK); PowerShell's Set-AuthenticodeSignature"
		if ($pfx -ne "") {
			$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfx, $pass)
		}
		$p = @{ FilePath = $Exe; Certificate = $cert; HashAlgorithm = "SHA256" }
		if ($ts -ne "none") { $p["TimestampServer"] = $ts }
		$r = Set-AuthenticodeSignature @p
		if ($r.SignerCertificate -eq $null) { Fail "Set-AuthenticodeSignature: $($r.StatusMessage)" }
	}
}

# the proof: the signature Windows reads back
$sig = Get-AuthenticodeSignature -LiteralPath $Exe
if ($sig.SignerCertificate -eq $null) { Fail "the exe carries no signature after signing ($($sig.StatusMessage))" }
if ($expect -ne $null -and $sig.SignerCertificate.Thumbprint -ne $expect) {
	Fail "the exe is signed by $($sig.SignerCertificate.Thumbprint), not by $expect"
}
$who = $sig.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
$stamp = if ($sig.TimeStamperCertificate) { "time-stamped" } else { "no time-stamp" }
if ($sig.Status -eq "Valid") {
	Write-Output "sign_exe: signed by $who ($stamp), trusted on this PC"
} else {
	Write-Output "sign_exe: signed by $who ($stamp), NOT trusted on this PC: $($sig.StatusMessage)"
}
exit 0
