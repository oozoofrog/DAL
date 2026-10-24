import { env } from "cloudflare:workers";
import { getChatGPTUser } from "../chatgpt-auth";
import { ReviewError, requireScope, type Actor } from "./review";
import { WorkspaceRepository } from "./workspace";
import { ReviewRepository } from "./repository";
export async function workspace(){if(!env.DB)throw new ReviewError(503,"저장소가 준비되지 않았습니다.");const ws=new WorkspaceRepository(env.DB as any);return ws}
export async function repository(projectId?:string,artifactId?:string){const scope=requireScope({projectId,artifactId});const ws=await workspace();await ws.artifact(scope.projectId,scope.artifactId);return new ReviewRepository(env.DB as any,scope)}
export function bucket(){if(!env.BUCKET)throw new ReviewError(503,"영상 저장소가 준비되지 않았습니다.");return env.BUCKET}
export async function browserActor():Promise<Actor>{const user=await getChatGPTUser();if(!user)throw new ReviewError(401,"로그인한 뒤 다시 시도해 주세요.");return{id:user.userId,role:"user"}}
export function sameOrigin(request:Request){const origin=request.headers.get("origin");if(origin&&origin!==new URL(request.url).origin)throw new ReviewError(403,"같은 사이트에서 다시 시도해 주세요.")}
export function errorResponse(error:unknown){return Response.json({error:error instanceof ReviewError?error.message:"저장하지 못했습니다. 잠시 뒤 다시 시도해 주세요."},{status:error instanceof ReviewError?error.status:500,headers:{"cache-control":"no-store"}})}
export async function jsonBody(request:Request){const raw=await request.text();if(raw.length>16000)throw new ReviewError(413,"내용이 너무 깁니다.");try{return JSON.parse(raw)}catch{throw new ReviewError(400,"요청 내용을 확인해 주세요.")}}
