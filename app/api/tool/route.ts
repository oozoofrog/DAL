import {workspace,browserActor,sameOrigin,jsonBody,errorResponse} from '../../lib/server';
export async function GET(){try{await browserActor();return Response.json(await(await workspace()).toolSnapshot(),{headers:{'cache-control':'no-store'}})}catch(e){return errorResponse(e)}}
export async function POST(request:Request){try{sameOrigin(request);const actor=await browserActor(),body=await jsonBody(request);return Response.json(await(await workspace()).createToolRequest({body:body.body},body.operationKey,actor))}catch(e){return errorResponse(e)}}
