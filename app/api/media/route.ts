import { getChatGPTUser } from "../../chatgpt-auth";import { repository, bucket, errorResponse, sameOrigin } from "../../lib/server";import { uploadMedia } from "../../lib/media";
// Confirmed owner-private Site: Dispatch authorizes every request, including service-token ingestion.
// A service credential is consumed by Dispatch and is never accepted, stored or exposed here.
export async function POST(request:Request){try{sameOrigin(request);const user=await getChatGPTUser();return Response.json(await uploadMedia(request,await repository(request.headers.get('x-project-id')??undefined,request.headers.get('x-artifact-id')??undefined),bucket(),user?{id:user.userId,role:"user"}:{id:"private-service",role:"dot"}))}catch(e){return errorResponse(e)}}
