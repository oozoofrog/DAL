"""Privacy invariant: inspect SwiftPM's actual Sources/Tests, never execute website probes."""
from pathlib import Path
import json,subprocess,unittest

class ShippingWebsiteExclusionTests(unittest.TestCase):
 def test_all_swiftpm_source_and_test_targets_exclude_website_paths(self):
  root=Path(__file__).resolve().parents[2]
  description=json.loads(subprocess.check_output(['swift','package','describe','--type','json'],cwd=root,text=True))
  forbidden=['import WebKit','SafariWorkspaceLauncher','BrowserLoginCoordinator','OfficialBrowserOpening','DOT_SHOW_AUTH','DAL_TEST_SAFARI_ORIGIN','DAL_SAFARI_RECEIPT_PATH','workspace.open(','NSWorkspace.shared.open','connect(cookies:','allowPending:']
  scanned=[];violations=[]
  for target in description['targets']:
   for source in target.get('sources',[]):
    path=root/target['path']/source
    if path.suffix!='.swift':continue
    scanned.append(path);text=path.read_text()
    for token in forbidden:
     if token in text:violations.append(str(path.relative_to(root))+': '+token)
  self.assertGreaterEqual(len(scanned),10,'Actual SwiftPM targets must be inspected')
  self.assertEqual(violations,[], '\n'.join(violations))
