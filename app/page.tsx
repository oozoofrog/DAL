import {getChatGPTUser,chatGPTSignInPath,chatGPTSignOutPath} from './chatgpt-auth';
export const dynamic='force-dynamic';
export default async function Page(){
 const user=await getChatGPTUser();
 return <main className="connection-landing">
  <span className="star">✳</span>
  <p>DAL · OFFICIAL BROWSER LOGIN</p>
  <h1>DAL 공식 로그인</h1>
  {user?<>
   <h2>이 브라우저에서 로그인했어요</h2>
   <p>이 로그인은 브라우저에서만 유효해요.<br/>DAL Mac 앱이 연결된 상태를 뜻하지는 않아요.</p>
   <a href={chatGPTSignOutPath('/')} target="_top">이 브라우저에서 로그아웃</a>
  </>:<>
   <p>공식 로그인 화면에서 계속해 주세요.<br/>암호·패스키·Touch ID 등의 선택지는 운영체제와<br/>로그인 제공자가 지원하는 경우 안내돼요.</p>
   <a className="signin" href={chatGPTSignInPath('/')} target="_top">공식 ChatGPT 로그인</a>
  </>}
  <small>DAL에는 이 브라우저의 로그인 세션을 Mac 앱에 연결하는 기능이 아직 없어요. 로그인 완료로 앱이 연결되지는 않아요.</small>
 </main>
}
