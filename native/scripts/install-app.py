#!/usr/bin/env python3
"""Explicit verified DAL milestone installation. No forced quits or user-data changes."""
from pathlib import Path
import argparse,hashlib,json,plistlib,shutil,subprocess,uuid
from install_lib import install_verified
root=Path(__file__).resolve().parent.parent;out=root.parent/'outputs';destination=Path('/Applications/DAL.app');legacy=Path('/Applications/DotWorkspace.app');backups=out/'installed-backups'
parser=argparse.ArgumentParser();parser.add_argument('--launch',action='store_true');parser.add_argument('--rollback',type=Path);args=parser.parse_args()
source=args.rollback.resolve() if args.rollback else out/'DAL.app'
if args.rollback:
 if not source.is_relative_to(backups.resolve()):raise RuntimeError('Choose a retained installed backup under outputs/installed-backups.')
 manifest=json.loads(source.with_suffix('.json').read_text())
else:manifest=json.loads((out/'native-verification.json').read_text())
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def identity(app):
 subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
 info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
 if info.get('CFBundleIdentifier')!='com.eyerama.dotworkspace':raise RuntimeError('Unexpected bundle identity')
 return info
def verify(app):
 info=identity(app)
 for path,key in [('Contents/MacOS/DotWorkspace','executableSHA256'),('Contents/Info.plist','infoSHA256'),('Contents/Resources/AppIcon.icns','iconSHA256')]:
  if sha(app/path)!=manifest[key]:raise RuntimeError('Verified package checksum mismatch: '+path)
 return info
def stopped(app):subprocess.run(['swift',str(root/'scripts/app-state.swift'),'check',str(app)],check=True)
def receipt_for(app):
 info=identity(app);return{'version':info.get('CFBundleShortVersionString'),'build':info.get('CFBundleVersion'),'signature':'local ad-hoc; retained previous verified app','executableSHA256':sha(app/'Contents/MacOS/DotWorkspace'),'infoSHA256':sha(app/'Contents/Info.plist'),'iconSHA256':sha(app/'Contents/Resources/AppIcon.icns')}
if not args.rollback and not manifest.get('swiftTestsPassed'):raise RuntimeError('Passing native tests required')
info=verify(source);legacyBackup=None;legacyHidden=None
# Migrate only the matching, verified old app. Preserve it outside /Applications before removing its name.
if legacy.exists():
 stopped(legacy);old=receipt_for(legacy)
 known=json.loads((out/'install-receipt.json').read_text())
 if known.get('installed')!=str(legacy) or known.get('executableSHA256')!=old['executableSHA256']:raise RuntimeError('Old app does not match this task\'s verified installed receipt; leave it untouched.')
 backups.mkdir(exist_ok=True);legacyBackup=backups/('DotWorkspace-'+uuid.uuid4().hex[:12]+'.app');shutil.copytree(legacy,legacyBackup,symlinks=True);identity(legacyBackup);legacyBackup.with_suffix('.json').write_text(json.dumps(old,indent=2)+'\n');stopped(legacy)
 legacyHidden=legacy.parent/('.DotWorkspace.migration-'+uuid.uuid4().hex[:12]+'.app');legacy.rename(legacyHidden)
try:
 backup=install_verified(source,destination,backups,verify,stopped)
except BaseException:
 if legacyHidden and legacyHidden.exists():legacyHidden.rename(legacy)
 raise
if backup:backup.with_suffix('.json').write_text(json.dumps(receipt_for(backup),indent=2)+'\n')
if legacyHidden and legacyHidden.exists():shutil.rmtree(legacyHidden)
receipt={'installed':str(destination),'displayName':info['CFBundleDisplayName'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'executableSHA256':manifest['executableSHA256'],'signature':'local ad-hoc; not notarized','previousInstalledBackup':str(backup or legacyBackup) if backup or legacyBackup else None,'preferencesAndBackendRecords':'untouched'}
(out/'install-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt,indent=2))
if args.launch:subprocess.run(['open',str(destination)],check=True)
