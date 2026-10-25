from pathlib import Path
import sys, unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_config import hand_input_metadata, verification_environment

class HandShippingGuardTests(unittest.TestCase):
 def test_camera_purpose_is_only_static_capability(self):
  metadata = hand_input_metadata()
  self.assertEqual(set(metadata), {'NSCameraUsageDescription'})
  self.assertIsInstance(metadata['NSCameraUsageDescription'], str)
  self.assertIn('직접', metadata['NSCameraUsageDescription'])
  self.assertIn('저장', metadata['NSCameraUsageDescription'])
 def test_verification_forbids_hardware_even_if_parent_environment_did_not(self):
  incoming = {'PATH':'/synthetic/bin','DAL_FORBID_REAL_CAMERA':'0','DOT_TEST_VIDEO':'synthetic-fixture.mp4'}
  verified = verification_environment(incoming)
  self.assertEqual(verified['DAL_FORBID_REAL_CAMERA'], '1')
  self.assertEqual(verified['PATH'], '/synthetic/bin')
  self.assertEqual(verified['DOT_TEST_VIDEO'], 'synthetic-fixture.mp4')
  self.assertEqual(incoming['DAL_FORBID_REAL_CAMERA'], '0')
 def test_unconfigured_verification_still_forbids_hardware(self):
  self.assertEqual(verification_environment({})['DAL_FORBID_REAL_CAMERA'], '1')
