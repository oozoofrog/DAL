"""Optional dormant backend metadata; local builds require no website provisioning."""
from urllib.parse import urlsplit

def backend_metadata(origin):
 if not origin:return {}
 parsed=urlsplit(origin)
 if parsed.scheme!='https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/'):
  raise ValueError('Optional DOT_BACKEND_ORIGIN must be an HTTPS origin without credentials, path, query or fragment.')
 return {'DotBackendOrigin':origin.rstrip('/')}

def hand_input_metadata():
 return {'NSCameraUsageDescription':'손으로 영상 위치를 가리키려면 이 실행에서 직접 켜고 카메라를 선택해 주세요. 영상과 손 좌표는 저장하거나 전송하지 않아요. 표시는 저장 전 초안으로만 만들어요.'}

def verification_environment(source):
 environment = dict(source)
 environment['DAL_FORBID_REAL_CAMERA'] = '1'
 return environment
