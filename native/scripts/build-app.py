#!/usr/bin/env python3
"""Explicit verified milestone build. No credentials, watcher, deployment or security changes."""
from pathlib import Path
import hashlib,json,os,plistlib,shutil,subprocess,urllib.parse,uuid
root=Path(__file__).resolve().parent.parent
output=root.parent/'outputs';output.mkdir(exist_ok=True)
bundle=output/'DAL.app'
if bundle.exists():subprocess.run(['swift',str(root/'scripts/app-state.swift'),'check',str(bundle)],check=True)
origin=os.environ.get('DOT_BACKEND_ORIGIN','')
parsed=urllib.parse.urlsplit(origin)
if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/'):
 raise SystemExit('Set DOT_BACKEND_ORIGIN to the intended HTTPS workspace origin; no private default is stored in source.')
version=json.loads((root/'VERSION.json').read_text())
subprocess.run(['python3','-m','unittest','discover','-s','scripts/tests'],cwd=root,check=True)
tests=subprocess.run(['swift','test','--cache-path','/tmp/dot-workspace-swift-cache'],cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
(output/'native-swift-tests.log').write_text(tests.stdout)
if tests.returncode:print(tests.stdout);raise SystemExit(tests.returncode)
subprocess.run(['swift','build','--cache-path','/tmp/dot-workspace-swift-cache'],cwd=root,check=True)
printed=subprocess.check_output(['swift','build','--show-bin-path'],cwd=root,text=True).strip()
binary=next((p for p in [Path(printed)/'DotWorkspace',root/'.build/out/Products/Debug/DotWorkspace'] if p.is_file()),None)
if binary is None:raise SystemExit('Built executable not found')
stage=output/'DAL-staged.app'
if stage.exists():shutil.rmtree(stage)
(stage/'Contents/MacOS').mkdir(parents=True);(stage/'Contents/Resources').mkdir()
shutil.copy2(binary,stage/'Contents/MacOS/DotWorkspace');os.chmod(stage/'Contents/MacOS/DotWorkspace',0o755)
icon=root/'Resources/AppIcon.icns'
if not icon.is_file():raise SystemExit('The approved AppIcon.icns resource is required.')
shutil.copy2(icon,stage/'Contents/Resources/AppIcon.icns')
info={'CFBundleDevelopmentRegion':'ko','CFBundleDisplayName':'DAL','CFBundleExecutable':'DotWorkspace','CFBundleIdentifier':'com.eyerama.dotworkspace','CFBundleName':'DAL','CFBundlePackageType':'APPL','CFBundleShortVersionString':version['version'],'CFBundleVersion':str(version['build']),'CFBundleIconFile':'AppIcon.icns','LSMinimumSystemVersion':'14.0','LSApplicationCategoryType':'public.app-category.productivity','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','DotBackendOrigin':origin.rstrip('/')}
with(stage/'Contents/Info.plist').open('wb')as f:plistlib.dump(info,f)
subprocess.run(['codesign','--force','--deep','--sign','-',str(stage)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(stage)],check=True)
if bundle.exists():
 subprocess.run(['swift',str(root/'scripts/app-state.swift'),'check',str(bundle)],check=True)
 backups=output/'build-backups';backups.mkdir(exist_ok=True)
 bundle.rename(backups/('DotWorkspace-'+uuid.uuid4().hex[:12]+'.app'))
stage.rename(bundle)
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
manifest={'version':version['version'],'build':version['build'],'signature':'local ad-hoc; not notarized','swiftTestsPassed':True,'mediaFixtureProvided':bool(os.environ.get('DOT_TEST_VIDEO')),'testSummary':[s for s in tests.stdout.splitlines() if 'Test run with' in s], 'executableSHA256':sha(bundle/'Contents/MacOS/DotWorkspace'),'infoSHA256':sha(bundle/'Contents/Info.plist'),'iconSHA256':sha(bundle/'Contents/Resources/AppIcon.icns')}
(output/'native-verification.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps({'bundle':str(bundle),**manifest},indent=2))
