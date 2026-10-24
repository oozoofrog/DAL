"""Filesystem transaction shared by real installation and isolated rollback regressions."""
from pathlib import Path
import shutil,uuid

def install_verified(source,destination,backups,verify,assert_stopped):
 source,destination,backups=Path(source),Path(destination),Path(backups)
 assert_stopped(destination)
 backups.mkdir(parents=True,exist_ok=True)
 token=uuid.uuid4().hex[:12]
 stage=destination.parent/('.DAL.stage-'+token+'.app')
 previous=destination.parent/('.DAL.previous-'+token+'.app')
 retained=None;swapped=False
 try:
  shutil.copytree(source,stage,symlinks=True);verify(stage);assert_stopped(destination)
  if destination.exists():
   retained=backups/('DAL-'+token+'.app');shutil.copytree(destination,retained,symlinks=True)
   destination.rename(previous)
  stage.rename(destination);swapped=True;verify(destination)
  if previous.exists():shutil.rmtree(previous)
  return retained
 except BaseException:
  # Includes unexpected SystemExit/interrupts: a present failed new target must not prevent restoration.
  hidden_failed=None
  if swapped and destination.exists():
   assert_stopped(destination)
   hidden_failed=destination.parent/('.DAL.failed-'+token+'.app')
   destination.rename(hidden_failed)
  if previous.exists():previous.rename(destination)
  # Restore first with same-volume renames. Quarantine storage can be unavailable.
  if hidden_failed and hidden_failed.exists():
   try:shutil.copytree(hidden_failed,backups/('failed-'+token+'.app'),symlinks=True)
   except OSError:pass
   else:
    try:shutil.rmtree(hidden_failed)
    except OSError:pass
  if stage.exists():shutil.rmtree(stage)
  raise
