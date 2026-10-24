from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from build_config import backend_metadata
class OptionalBackendConfigTests(unittest.TestCase):
 def test_unconfigured_build_has_no_backend_metadata(self):
  self.assertEqual(backend_metadata(None),{})
  self.assertEqual(backend_metadata(''),{})
 def test_optional_origin_is_validated(self):
  self.assertEqual(backend_metadata('https://example.invalid/'),{'DotBackendOrigin':'https://example.invalid'})
  for value in ['http://example.invalid','https://user@example.invalid','https://example.invalid/login','https://example.invalid?token=x']:
   with self.assertRaises(ValueError):backend_metadata(value)
