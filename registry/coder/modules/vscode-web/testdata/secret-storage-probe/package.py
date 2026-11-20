#!/usr/bin/env python3
"""Package the test-only extension without downloading a VSIX build tool."""
from pathlib import Path
import sys
from zipfile import ZipFile, ZIP_DEFLATED

source = Path(__file__).parent
with ZipFile(sys.argv[1], "w", ZIP_DEFLATED) as archive:
    archive.writestr("[Content_Types].xml", '''<?xml version="1.0"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json"/>
  <Default Extension="js" ContentType="application/javascript"/>
  <Default Extension="vsixmanifest" ContentType="text/xml"/>
</Types>''')
    archive.writestr("extension.vsixmanifest", '''<?xml version="1.0"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="secret-storage-probe" Version="1.0.0" Publisher="registry-test"/>
    <DisplayName>Registry Secret Storage Probe</DisplayName>
    <Description xml:space="preserve">Test-only extension secret storage probe</Description>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.90.0"/></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>''')
    for filename in ("package.json", "extension.js"):
        archive.write(source / filename, "extension/" + filename)
