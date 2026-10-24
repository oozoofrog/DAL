import sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from install_lib import install_verified
class InstallTransactionTests(unittest.TestCase):
 def test_postswap_failure_restores_previous_and_quarantines_failed_build(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);source=root/'source.app';destination=root/'DAL.app';backups=root/'backups';source.mkdir();destination.mkdir();(source/'version').write_text('new');(destination/'version').write_text('old')
   def verify(path):
    if path==destination:raise RuntimeError('injected post-swap signature failure')
   with self.assertRaises(RuntimeError):install_verified(source,destination,backups,verify,lambda p:None)
   self.assertEqual((destination/'version').read_text(),'old')
   self.assertEqual(len(list(backups.glob('failed-*'))),1)
 def test_systemexit_from_verifier_also_restores_previous(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);source=root/'source.app';destination=root/'DAL.app';source.mkdir();destination.mkdir();(source/'version').write_text('new');(destination/'version').write_text('old')
   def verify(path):
    if path==destination:raise SystemExit('injected exit')
   with self.assertRaises(SystemExit):install_verified(source,destination,root/'backups',verify,lambda p:None)
   self.assertEqual((destination/'version').read_text(),'old')
 def test_running_target_is_refused_without_replacement(self):
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);source=root/'source.app';destination=root/'DAL.app';source.mkdir();destination.mkdir();(source/'version').write_text('new');(destination/'version').write_text('old')
   def running(path):raise RuntimeError('running')
   with self.assertRaises(RuntimeError):install_verified(source,destination,root/'backups',lambda p:None,running)
   self.assertEqual((destination/'version').read_text(),'old')
 def test_quarantine_io_failure_cannot_prevent_previous_restore(self):
  from unittest.mock import patch
  import shutil
  with tempfile.TemporaryDirectory() as t:
   root=Path(t);source=root/'source.app';destination=root/'DAL.app';source.mkdir();destination.mkdir();(source/'version').write_text('new');(destination/'version').write_text('old');copy=shutil.copytree
   def verify(path):
    if path==destination:raise RuntimeError('injected verification failure')
   def copy_with_failure(src,dst,*a,**k):
    if Path(dst).name.startswith('failed-'):raise OSError('injected quarantine volume unavailable')
    return copy(src,dst,*a,**k)
   with patch('install_lib.shutil.copytree',side_effect=copy_with_failure):
    with self.assertRaises(BaseException):install_verified(source,destination,root/'backups',verify,lambda p:None)
   self.assertEqual((destination/'version').read_text(),'old')
