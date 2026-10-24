"""Optional dormant backend metadata; local builds require no website provisioning."""
from urllib.parse import urlsplit

def backend_metadata(origin):
 if not origin:return {}
 parsed=urlsplit(origin)
 if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/'):
  raise ValueError('Optional DOT_BACKEND_ORIGIN must be an HTTPS origin without credentials, path, query or fragment.')
 return {'DotBackendOrigin':origin.rstrip('/')}
