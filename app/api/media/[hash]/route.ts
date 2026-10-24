import { bucket, errorResponse } from "../../../lib/server";import { streamMedia } from "../../../lib/media";
// Protected by the confirmed owner-private Sites access policy for GET and HEAD, including ranges.
export async function GET(request:Request,{params}:{params:Promise<{hash:string}>}){try{return await streamMedia(request,bucket(),(await params).hash)}catch(e){return errorResponse(e)}}
export const HEAD=GET;
